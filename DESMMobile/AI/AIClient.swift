// AIClient.swift — gọi API của từng nhà (Gemini / Claude / OpenAI-compatible), dò danh sách model, tự thử model.
// Chuyển từ LLMClient.swift của LiveTranslate (bỏ phần dịch hội thoại).

import Foundation

enum AIError: LocalizedError {
    case http(Int, String)
    case badResponse
    case empty(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            switch code {
            case 429: return "hết hạn mức tạm thời (429)"
            case 503: return "model đang quá tải (503)"
            case 401, 403: return "key không hợp lệ hoặc không có quyền (\(code))"
            case 413: return "dữ liệu gửi quá lớn (413) — giảm \"Lượng dữ liệu gửi\" trong Cài đặt"
            case 404: return "không tìm thấy model/địa chỉ (404): \(body)"
            default: return "lỗi \(code): \(body)"
            }
        case .badResponse:
            return "phản hồi không đọc được"
        case .empty(let why):
            return "AI trả về nội dung rỗng (\(why)). Thử hỏi ngắn gọn hơn, tắt bớt công tắc dữ liệu hoặc đổi model."
        }
    }
}

struct AIProviderError: LocalizedError {
    let provider: String
    let underlying: Error
    var errorDescription: String? { "\(provider): \(underlying.localizedDescription)" }
}

enum AIClient {
    typealias Msg = (role: String, text: String)   // role: "user" | "model"

    /// Ảnh (JPEG) đính kèm cho CÂU HỎI HIỆN TẠI. Chỉ gắn vào tin nhắn người dùng cuối cùng; các lượt trước chỉ còn chữ.
    /// Đặt trước khi gọi và xoá sau khi xong (xem AIChatView.send).
    static var currentImages: [Data] = []

    static func geminiAttach(_ contents: inout [[String: Any]]) {
        guard !currentImages.isEmpty, let i = contents.lastIndex(where: { ($0["role"] as? String) == "user" }) else { return }
        var parts = contents[i]["parts"] as? [[String: Any]] ?? []
        for d in currentImages { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": d.base64EncodedString()]]) }
        contents[i]["parts"] = parts
    }

    static func anthropicAttach(_ msgs: inout [[String: Any]]) {
        guard !currentImages.isEmpty, let i = msgs.lastIndex(where: { ($0["role"] as? String) == "user" }) else { return }
        let text = msgs[i]["content"] as? String ?? ""
        var blocks: [[String: Any]] = currentImages.map {
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0.base64EncodedString()]]
        }
        blocks.append(["type": "text", "text": text])
        msgs[i]["content"] = blocks
    }

    static func openAIAttach(_ msgs: inout [[String: Any]]) {
        guard !currentImages.isEmpty, let i = msgs.lastIndex(where: { ($0["role"] as? String) == "user" }) else { return }
        let text = msgs[i]["content"] as? String ?? ""
        var blocks: [[String: Any]] = [["type": "text", "text": text]]
        for d in currentImages {
            blocks.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + d.base64EncodedString()]])
        }
        msgs[i]["content"] = blocks
    }

    static func complete(_ c: AIConfig, system: String, messages: [Msg],
                         temperature: Double?, timeout: TimeInterval) async throws -> String {
        switch c.id.kind {
        case .gemini:    return try await gemini(c, system, messages, temperature, timeout)
        case .anthropic: return try await anthropic(c, system, messages, timeout)
        case .openAI:    return try await openAI(c, system, messages, temperature, timeout)
        }
    }

    static func post(_ url: URL, headers: [String: String], body: [String: Any],
                             timeout: TimeInterval) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.badResponse }
        guard http.statusCode == 200 else {
            let snippet = String((String(data: data, encoding: .utf8) ?? "").prefix(140))
            throw AIError.http(http.statusCode, snippet)
        }
        let any = try JSONSerialization.jsonObject(with: data)
        if let obj = any as? [String: Any] { return obj }
        if let arr = any as? [[String: Any]], let first = arr.first { return first }   // một số API trả mảng
        throw AIError.badResponse
    }

    private static func gemini(_ c: AIConfig, _ system: String, _ messages: [Msg],
                               _ temperature: Double?, _ timeout: TimeInterval) async throws -> String {
        var name = c.model
        if name.hasPrefix("models/") { name = String(name.dropFirst(7)) }
        guard let url = URL(string: "\(c.base)/models/\(name):generateContent") else { throw AIError.badResponse }

        var contents: [[String: Any]] = messages.map { ["role": $0.role, "parts": [["text": $0.text]]] }
        geminiAttach(&contents)
        var gen: [String: Any] = [:]
        if let t = temperature { gen["temperature"] = t }
        var body: [String: Any] = ["contents": contents, "generationConfig": gen]
        if !system.isEmpty { body["system_instruction"] = ["parts": [["text": system]]] }

        let root = try await post(url, headers: ["x-goog-api-key": c.key], body: body, timeout: timeout)
        guard let cands = root["candidates"] as? [[String: Any]],
              let content = cands.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AIError.empty(geminiWhy(root))
        }
        let text = parts.filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.badResponse }
        return text
    }

    /// Lý do Gemini không trả nội dung: finishReason / blockReason
    static func geminiWhy(_ root: [String: Any]) -> String {
        if let pf = root["promptFeedback"] as? [String: Any], let b = pf["blockReason"] as? String { return "bị chặn: \(b)" }
        if let c = (root["candidates"] as? [[String: Any]])?.first, let f = c["finishReason"] as? String { return "finishReason=\(f)" }
        return "không có candidates"
    }

    private static func anthropic(_ c: AIConfig, _ system: String, _ messages: [Msg],
                                  _ timeout: TimeInterval) async throws -> String {
        guard let url = URL(string: c.base) else { throw AIError.badResponse }
        var msgs: [[String: Any]] = messages.map {
            ["role": $0.role == "model" ? "assistant" : "user", "content": $0.text]
        }
        anthropicAttach(&msgs)
        var body: [String: Any] = ["model": c.model, "max_tokens": 2048, "messages": msgs]
        if !system.isEmpty { body["system"] = system }

        let root = try await post(url,
                                  headers: ["x-api-key": c.key, "anthropic-version": "2023-06-01"],
                                  body: body, timeout: timeout)
        guard let content = root["content"] as? [[String: Any]] else { throw AIError.badResponse }
        let text = content.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.badResponse }
        return text
    }

    private static func openAI(_ c: AIConfig, _ system: String, _ messages: [Msg],
                               _ temperature: Double?, _ timeout: TimeInterval) async throws -> String {
        var base = c.base
        while base.hasSuffix("/") { base.removeLast() }
        let full = base.hasSuffix("/chat/completions") ? base : base + "/chat/completions"
        guard let url = URL(string: full) else { throw AIError.badResponse }

        var msgs: [[String: Any]] = []
        if !system.isEmpty { msgs.append(["role": "system", "content": system]) }
        msgs += messages.map { ["role": $0.role == "model" ? "assistant" : "user", "content": $0.text] }
        openAIAttach(&msgs)

        var body: [String: Any] = ["model": c.model, "messages": msgs]
        // Một số model (vd. dòng reasoning của OpenAI) không cho đổi temperature
        if let t = temperature, c.id != .openai { body["temperature"] = t }

        var headers: [String: String] = [:]
        if !c.key.isEmpty { headers["Authorization"] = "Bearer \(c.key)" }

        let root = try await post(url, headers: headers, body: body, timeout: timeout)
        guard let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else { throw AIError.badResponse }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw AIError.badResponse }
        return t
    }
}

// MARK: - Dò danh sách model + tự chọn model chạy được
extension AIClient {
    /// Lấy danh sách model mà key này dùng được (chỉ model chat/văn bản).
    static func listModels(_ c: AIConfig, timeout: TimeInterval = 15) async throws -> [String] {
        var headers: [String: String] = [:]
        let url: URL?
        switch c.id.kind {
        case .gemini:
            url = URL(string: "\(c.base)/models?pageSize=1000")
            headers["x-goog-api-key"] = c.key
        case .anthropic:
            var b = c.base
            if b.hasSuffix("/messages") { b.removeLast(9) }
            url = URL(string: b + "/models?limit=1000")
            headers["x-api-key"] = c.key
            headers["anthropic-version"] = "2023-06-01"
        case .openAI:
            var b = c.base
            while b.hasSuffix("/") { b.removeLast() }
            if b.hasSuffix("/chat/completions") { b.removeLast(17) }
            url = URL(string: b + "/models")
            if !c.key.isEmpty { headers["Authorization"] = "Bearer \(c.key)" }
        }
        guard let url else { throw AIError.badResponse }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.badResponse }
        guard http.statusCode == 200 else {
            let snippet = String((String(data: data, encoding: .utf8) ?? "").prefix(140))
            throw AIError.http(http.statusCode, snippet)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse
        }

        var ids: [String] = []
        if c.id.kind == .gemini {
            for m in (root["models"] as? [[String: Any]]) ?? [] {
                let methods = m["supportedGenerationMethods"] as? [String] ?? []
                guard methods.contains("generateContent"), var n = m["name"] as? String else { continue }
                if n.hasPrefix("models/") { n.removeFirst(7) }
                ids.append(n)
            }
        } else {
            ids = ((root["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        }

        let skip = ["embed", "whisper", "tts", "moderation", "guard", "dall", "image", "imagen",
                    "audio", "transcribe", "realtime", "rerank", "veo", "video", "aqa", "speech"]
        let out = ids.filter { id in
            let l = id.lowercased()
            return !skip.contains { l.contains($0) }
        }
        guard !out.isEmpty else { throw AIError.badResponse }
        return Array(Set(out)).sorted()
    }

    /// Thử lần lượt tối đa `limit` model (ưu tiên model hiện tại, mặc định, rồi model nhanh) và trả về model đầu tiên chạy được.
    static func pickWorkingModel(_ c: AIConfig, limit: Int = 8,
                                 progress: ((String) -> Void)? = nil) async throws -> (picked: String?, all: [String]) {
        let all = try await listModels(c)
        let fast = ["flash", "mini", "haiku", "small", "instant", "lite", "8b", "sonnet"]
        var order: [String] = []
        for m in [c.model, c.id.defaultModel] where all.contains(m) && !order.contains(m) { order.append(m) }
        order += all.filter { id in fast.contains { id.lowercased().contains($0) } && !order.contains(id) }
        order += all.filter { !order.contains($0) }

        for m in order.prefix(limit) {
            progress?(m)
            let cfg = AIConfig(id: c.id, key: c.key, model: m, base: c.base)
            if (try? await complete(cfg, system: "Reply with one short word.",
                                    messages: [(role: "user", text: "Say hello")],
                                    temperature: nil, timeout: 12)) != nil {
                return (m, all)
            }
        }
        return (nil, all)
    }

    // MARK: Thử lần lượt nhiều nhà
    /// Nhà đứng đầu dùng trước; lỗi thì sang nhà kế tiếp. Trả về (câu trả lời, nhà đã trả lời).
    static func run(_ providers: [AIConfig], system: String, messages: [Msg],
                    temperature: Double? = 0.3, timeout: TimeInterval = 60) async throws -> (text: String, by: AIConfig) {
        var last: Error?
        for c in providers {
            var attempts = 0
            while true {
                do {
                    let t = try await complete(c, system: system, messages: messages,
                                               temperature: temperature, timeout: timeout)
                    return (t, c)
                } catch {
                    if Task.isCancelled { throw error }
                    last = AIProviderError(provider: c.id.shortName, underlying: error)
                    attempts += 1
                    if providers.count == 1, attempts < 2, isTransient(error) {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        continue
                    }
                    break
                }
            }
        }
        throw last ?? AIError.badResponse
    }

    private static func isTransient(_ e: Error) -> Bool {
        if let g = e as? AIError, case .http(let code, _) = g { return [429, 500, 502, 503, 504].contains(code) }
        return e is URLError
    }
}
