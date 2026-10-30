// AIAgent.swift — vòng lặp tra cứu: hỏi AI → AI xin gọi công cụ → app chạy công cụ (chỉ đọc) → trả kết quả cho AI → lặp (tối đa 6 vòng).
// Model/nhà không hỗ trợ công cụ (HTTP 400/404/422 ở vòng đầu) thì lùi về hỏi đáp thường.
// Chống treo: tổng thời gian cả lượt ≤ 180 giây, mỗi lần gọi AI ≤ 60 giây, mỗi công cụ ≤ 45 giây (aiRace), gọi trùng lệnh thì dùng lại kết quả,
// dữ liệu tra cũ được rút gọn để mỗi vòng không phình to. Mọi bước ghi vào AILog. Chưa build/chưa thử trên máy thật.

import Foundation

enum AIAgent {
    static let maxRounds = 6
    static let totalSeconds: Double = 180
    static let requestSeconds: Double = 60
    static let toolSeconds: Double = 45
    static let toolBudgetChars = 90_000     // tổng dữ liệu tra gửi lại AI mỗi vòng; vượt thì rút gọn kết quả cũ
    static let keepOldChars = 3_000

    static func run(provider: AIProvider, key: String, model: String, system: String,
                    history: [AIMsg], tools: [AIToolDef],
                    exec: @escaping (String, [String: Any]) async -> String,
                    status: @escaping (String) -> Void,
                    budget: Double = 180) async throws -> String {
        let t0 = Date()
        var msgs = history
        var useTools = !tools.isEmpty
        var cache: [String: String] = [:]
        AILog.step("Bắt đầu lượt hỏi: " + provider.name + " · " + model + " · công cụ " + (useTools ? "bật" : "tắt") + " · " + String(history.count) + " tin")

        for round in 0..<maxRounds {
            try Task.checkCancellation()
            let remaining = budget - Date().timeIntervalSince(t0)
            if remaining < 8 {
                AILog.add("✗ Hết " + String(Int(budget)) + "s cho cả lượt hỏi")
                throw AIError(message: "Quá " + String(Int(budget)) + " giây mà chưa có kết quả. Hãy hỏi gọn hơn, hoặc chọn model nhanh hơn ở đầu khung chat.")
            }
            let wait = min(requestSeconds, remaining)
            AILog.step("Vòng " + String(round + 1) + "/" + String(maxRounds) + ": gửi " + String(msgs.count) + " tin cho " + provider.name)
            status(round == 0 ? "Đang suy nghĩ…" : "AI đang đọc dữ liệu vừa tra…")

            var got: AITurn? = nil
            do {
                got = try await AIClient.chat(provider, key: key, model: model, system: system, msgs: msgs, tools: useTools ? tools : [], timeout: wait)
            } catch let e as AIError {
                if useTools && round == 0 && (e.status == 400 || e.status == 404 || e.status == 422) {
                    useTools = false
                    AILog.add("Model không nhận công cụ (HTTP " + String(e.status) + ") → hỏi đáp thường")
                    status("Model này không hỗ trợ công cụ — chuyển sang hỏi đáp thường…")
                    got = try await AIClient.chat(provider, key: key, model: model, system: system, msgs: msgs, tools: [], timeout: min(requestSeconds, max(10, remaining - 5)))
                } else {
                    throw e
                }
            }
            guard let turn = got else { throw AIError(message: "Không có phản hồi.") }

            if turn.calls.isEmpty || !useTools {
                let t = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
                AILog.step("Xong sau " + String(format: "%.1f", Date().timeIntervalSince(t0)) + "s, " + String(round + 1) + " vòng, trả lời " + String(t.count) + " ký tự")
                return t.isEmpty ? "(AI không trả lời nội dung nào.)" : t
            }

            AILog.add("AI xin " + String(turn.calls.count) + " công cụ: " + turn.calls.map { $0.name }.joined(separator: ", "))
            msgs.append(.assistant(turn))
            var results: [AIToolResult] = []
            for c in turn.calls {
                try Task.checkCancellation()
                let sig = c.name + "|" + canonical(c.args)
                var out: String
                if let hit = cache[sig] {
                    AILog.add("↺ " + c.name + " gọi trùng lệnh cũ → dùng lại kết quả")
                    out = "(Lệnh này đã gọi ở vòng trước, kết quả y hệt. Hãy dùng dữ liệu đã có hoặc đổi bộ lọc.)\n" + String(hit.prefix(2000))
                } else {
                    status("Đang tra DESM: " + c.name + "…")
                    AILog.step("Công cụ " + c.name + " " + argSummary(c.args))
                    let ts = Date()
                    let timeoutMsg = "Công cụ " + c.name + " quá " + String(Int(toolSeconds)) + " giây không trả kết quả (DESM chậm hoặc trang đang bận). Hãy báo người dùng, hoặc thử lại với bộ lọc hẹp hơn."
                    let name = c.name
                    let args = c.args
                    out = await aiRace(toolSeconds, fallback: timeoutMsg) { await exec(name, args) }
                    let timedOut = (out == timeoutMsg)
                    AILog.add("◀ " + c.name + (timedOut ? " ✗ QUÁ THỜI GIAN " : " xong ") + "sau " + String(format: "%.1f", Date().timeIntervalSince(ts)) + "s, trả " + String(out.utf8.count / 1024) + " KB")
                    if !timedOut { cache[sig] = out }
                }
                results.append(AIToolResult(call: c, output: out))
            }
            msgs.append(.tools(results))
            msgs = trimOldToolOutputs(msgs)
        }
        AILog.add("✗ Hết " + String(maxRounds) + " vòng mà AI vẫn xin tra thêm")
        return "(Đã tra \(maxRounds) vòng mà chưa đủ dữ liệu để kết luận. Hãy hỏi cụ thể hơn, ví dụ nêu số kiện.)"
    }

    /// Chuỗi chuẩn hoá của tham số (khoá sắp xếp) để nhận ra lệnh gọi trùng.
    static func canonical(_ a: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(a),
              let d = try? JSONSerialization.data(withJSONObject: a, options: [.sortedKeys]) else { return String(describing: a.keys.sorted()) }
        return String(decoding: d, as: UTF8.self)
    }

    /// Tóm tắt tham số để ghi nhật ký: chỉ tên endpoint / tên khoá lọc / số, KHÔNG ghi giá trị lọc (có thể là dữ liệu công ty).
    static func argSummary(_ a: [String: Any]) -> String {
        var parts: [String] = []
        if let ep = a["endpoint"] as? String { parts.append(ep) }
        if let pj = a["params_json"] as? String,
           let o = (try? JSONSerialization.jsonObject(with: Data(pj.utf8))) as? [String: Any], !o.isEmpty {
            parts.append("lọc theo " + o.keys.sorted().joined(separator: ","))
        }
        if let n = a["max_rows"] as? NSNumber { parts.append("max_rows=" + n.stringValue) }
        if let n = a["limit"] as? NSNumber { parts.append("limit=" + n.stringValue) }
        return parts.joined(separator: " · ")
    }

    /// Khi tổng dữ liệu tra vượt ngân sách: rút gọn các kết quả công cụ CŨ (giữ nguyên lượt tra mới nhất).
    static func trimOldToolOutputs(_ msgs: [AIMsg]) -> [AIMsg] {
        var total = 0
        var lastIdx = -1
        for (i, m) in msgs.enumerated() {
            if case .tools(let rs) = m {
                lastIdx = i
                for r in rs { total += r.output.utf8.count }
            }
        }
        if total <= toolBudgetChars { return msgs }
        var out: [AIMsg] = []
        for (i, m) in msgs.enumerated() {
            if case .tools(let rs) = m, i != lastIdx {
                let shorter: [AIToolResult] = rs.map { (r: AIToolResult) -> AIToolResult in
                    if r.output.utf8.count <= keepOldChars { return r }
                    return AIToolResult(call: r.call, output: String(r.output.prefix(keepOldChars)) + "\n…(đã rút gọn dữ liệu cũ)")
                }
                out.append(.tools(shorter))
            } else {
                out.append(m)
            }
        }
        AILog.add("Rút gọn dữ liệu tra cũ (tổng " + String(total / 1024) + " KB vượt ngân sách)")
        return out
    }
}
