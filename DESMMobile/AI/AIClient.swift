// AIClient.swift — gọi 3 kiểu API (OpenAI-compatible, Claude, Gemini) có hỗ trợ công cụ (function calling) + dò danh sách model.
// Chưa build/chưa thử trên máy thật.

import Foundation

struct AIError: LocalizedError {
    let message: String
    var status: Int = 0
    var network: Bool = false      // lỗi đường truyền (mất mạng, đứt kết nối…) → đáng thử lại một lần
    var errorDescription: String? { return message }
}

struct AIToolDef {
    let name: String
    let description: String
    let schema: [String: Any]      // JSON schema, kiểu viết thường (Gemini được đổi sang chữ hoa)
}

struct AIToolCall {
    let id: String
    let name: String
    let args: [String: Any]
}

struct AITurn {
    var text: String
    var calls: [AIToolCall]
    var raw: Any                   // nội dung gốc của lượt trả lời để gửi lại đúng nguyên văn trong các vòng tra cứu

    /// Lượt trả lời chỉ có chữ (dùng lưu lịch sử hội thoại gọn, không kèm dữ liệu tra cứu).
    static func plain(_ text: String, kind: AIKind) -> AITurn {
        switch kind {
        case .openai: return AITurn(text: text, calls: [], raw: ["role": "assistant", "content": text] as [String: Any])
        case .claude: return AITurn(text: text, calls: [], raw: [["type": "text", "text": text]] as [[String: Any]])
        case .gemini: return AITurn(text: text, calls: [], raw: [["text": text]] as [[String: Any]])
        }
    }
}

struct AIToolResult {
    let call: AIToolCall
    let output: String
}

enum AIMsg {
    case user(String)
    case userImages(String, [Data])    // câu hỏi kèm ảnh (JPEG) đính kèm
    case assistant(AITurn)
    case tools([AIToolResult])
}

enum AIClient {
    // MARK: HTTP
    /// Phiên riêng cho AI: có giới hạn tổng thời gian (không chỉ thời gian im lặng) để không bao giờ chờ vô hạn.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 100
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    static func request(_ url: String, method: String = "POST", headers: [String: String], body: [String: Any]?, timeout: TimeInterval = 60) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw AIError(message: "Địa chỉ API không hợp lệ.") }
        var r = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        r.httpMethod = method
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        var sent = 0
        if let b = body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let d = try JSONSerialization.data(withJSONObject: b)
            r.httpBody = d
            sent = d.count
        }
        let label = method + " " + (u.host ?? "?") + u.path
        let t0 = Date()
        AILog.add("→ " + label + " gửi " + String(sent / 1024) + " KB (chờ tối đa " + String(Int(timeout)) + "s)")
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: r)
        } catch {
            let secs = String(format: "%.1f", Date().timeIntervalSince(t0))
            let code = (error as? URLError)?.code
            if code == .cancelled || Task.isCancelled {
                AILog.add("✋ " + label + " bị huỷ sau " + secs + "s")
                throw CancellationError()
            }
            if code == .timedOut {
                AILog.add("✗ " + label + " QUÁ THỜI GIAN sau " + secs + "s")
                throw AIError(message: "Nhà AI không trả lời trong " + String(Int(timeout)) + " giây (quá thời gian chờ). Thử lại hoặc chọn model nhanh hơn.")
            }
            AILog.add("✗ " + label + " lỗi mạng sau " + secs + "s: " + error.localizedDescription)
            throw AIError(message: "Lỗi mạng: \(error.localizedDescription)", network: true)
        }
        let data = result.0
        let resp = result.1
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        AILog.add("← " + label + " HTTP " + String(code) + ", nhận " + String(data.count / 1024) + " KB sau " + String(format: "%.1f", Date().timeIntervalSince(t0)) + "s")
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if code < 200 || code >= 300 {
            throw AIError(message: "HTTP \(code): " + shortError(obj, data), status: code)
        }
        guard let o = obj else { throw AIError(message: "Phản hồi không phải JSON.") }
        return o
    }

    private static func shortError(_ obj: [String: Any]?, _ data: Data) -> String {
        if let e = obj?["error"] as? [String: Any], let m = e["message"] as? String { return String(m.prefix(300)) }
        if let m = obj?["error"] as? String { return String(m.prefix(300)) }
        if let m = obj?["message"] as? String { return String(m.prefix(300)) }
        return String((String(data: data, encoding: .utf8) ?? "").prefix(300))
    }

    // MARK: Chat
    static func chat(_ p: AIProvider, key: String, model: String, system: String, msgs: [AIMsg], tools: [AIToolDef], timeout: TimeInterval = 60) async throws -> AITurn {
        switch p.kind {
        case .openai: return try await chatOpenAI(p, key: key, model: model, system: system, msgs: msgs, tools: tools, timeout: timeout)
        case .claude: return try await chatClaude(p, key: key, model: model, system: system, msgs: msgs, tools: tools, timeout: timeout)
        case .gemini: return try await chatGemini(p, key: key, model: model, system: system, msgs: msgs, tools: tools, timeout: timeout)
        }
    }

    private static func chatOpenAI(_ p: AIProvider, key: String, model: String, system: String, msgs: [AIMsg], tools: [AIToolDef], timeout: TimeInterval) async throws -> AITurn {
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for m in msgs {
            switch m {
            case .user(let t):
                messages.append(["role": "user", "content": t])
            case .userImages(let t, let imgs):
                var parts: [[String: Any]] = [["type": "text", "text": t]]
                for d in imgs {
                    parts.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + d.base64EncodedString()] as [String: Any]])
                }
                messages.append(["role": "user", "content": parts])
            case .assistant(let a):
                if let raw = a.raw as? [String: Any] { messages.append(raw) }
            case .tools(let rs):
                for r in rs { messages.append(["role": "tool", "tool_call_id": r.call.id, "content": r.output]) }
            }
        }
        var body: [String: Any] = ["model": model, "messages": messages]
        if !tools.isEmpty {
            body["tools"] = tools.map { (t: AIToolDef) -> [String: Any] in
                return ["type": "function", "function": ["name": t.name, "description": t.description, "parameters": t.schema] as [String: Any]]
            }
        }
        let o = try await request(AIStore.baseURL(p) + "/chat/completions", headers: ["Authorization": "Bearer " + key], body: body, timeout: timeout)
        guard let choice = (o["choices"] as? [[String: Any]])?.first, let msg = choice["message"] as? [String: Any] else {
            throw AIError(message: "Phản hồi không có nội dung.")
        }
        let text = (msg["content"] as? String) ?? ""
        var calls: [AIToolCall] = []
        var rawCalls: [[String: Any]] = []
        let tcs = (msg["tool_calls"] as? [[String: Any]]) ?? []
        for (i, tc) in tcs.enumerated() {
            let fn = (tc["function"] as? [String: Any]) ?? [:]
            let name = (fn["name"] as? String) ?? ""
            let argStr = (fn["arguments"] as? String) ?? "{}"
            let id = (tc["id"] as? String) ?? "call_\(i)"
            let args = (try? JSONSerialization.jsonObject(with: Data(argStr.utf8))) as? [String: Any] ?? [:]
            calls.append(AIToolCall(id: id, name: name, args: args))
            rawCalls.append(["id": id, "type": "function", "function": ["name": name, "arguments": argStr] as [String: Any]])
        }
        var raw: [String: Any] = ["role": "assistant"]
        if !text.isEmpty { raw["content"] = text }
        else if rawCalls.isEmpty { raw["content"] = "" }
        else { raw["content"] = NSNull() }
        if !rawCalls.isEmpty { raw["tool_calls"] = rawCalls }
        return AITurn(text: text, calls: calls, raw: raw)
    }

    private static func chatClaude(_ p: AIProvider, key: String, model: String, system: String, msgs: [AIMsg], tools: [AIToolDef], timeout: TimeInterval) async throws -> AITurn {
        var messages: [[String: Any]] = []
        for m in msgs {
            switch m {
            case .user(let t):
                messages.append(["role": "user", "content": t])
            case .userImages(let t, let imgs):
                var blocks: [[String: Any]] = imgs.map { (d: Data) -> [String: Any] in
                    return ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": d.base64EncodedString()] as [String: Any]]
                }
                blocks.append(["type": "text", "text": t])
                messages.append(["role": "user", "content": blocks])
            case .assistant(let a):
                messages.append(["role": "assistant", "content": a.raw])
            case .tools(let rs):
                let blocks: [[String: Any]] = rs.map { (r: AIToolResult) -> [String: Any] in
                    return ["type": "tool_result", "tool_use_id": r.call.id, "content": r.output]
                }
                messages.append(["role": "user", "content": blocks])
            }
        }
        var body: [String: Any] = ["model": model, "max_tokens": 4096, "system": system, "messages": messages]
        if !tools.isEmpty {
            body["tools"] = tools.map { (t: AIToolDef) -> [String: Any] in
                return ["name": t.name, "description": t.description, "input_schema": t.schema]
            }
        }
        let o = try await request(AIStore.baseURL(p) + "/messages",
                                  headers: ["x-api-key": key, "anthropic-version": "2023-06-01"], body: body, timeout: timeout)
        let blocks = (o["content"] as? [[String: Any]]) ?? []
        var text = ""
        var calls: [AIToolCall] = []
        for b in blocks {
            let type = (b["type"] as? String) ?? ""
            if type == "text" {
                text += (b["text"] as? String) ?? ""
            } else if type == "tool_use" {
                calls.append(AIToolCall(id: (b["id"] as? String) ?? UUID().uuidString,
                                        name: (b["name"] as? String) ?? "",
                                        args: (b["input"] as? [String: Any]) ?? [:]))
            }
        }
        if blocks.isEmpty { throw AIError(message: "Phản hồi không có nội dung.") }
        return AITurn(text: text, calls: calls, raw: blocks)
    }

    private static func chatGemini(_ p: AIProvider, key: String, model: String, system: String, msgs: [AIMsg], tools: [AIToolDef], timeout: TimeInterval) async throws -> AITurn {
        var contents: [[String: Any]] = []
        for m in msgs {
            switch m {
            case .user(let t):
                contents.append(["role": "user", "parts": [["text": t]]])
            case .userImages(let t, let imgs):
                var parts: [[String: Any]] = imgs.map { (d: Data) -> [String: Any] in
                    return ["inlineData": ["mimeType": "image/jpeg", "data": d.base64EncodedString()] as [String: Any]]
                }
                parts.append(["text": t])
                contents.append(["role": "user", "parts": parts])
            case .assistant(let a):
                contents.append(["role": "model", "parts": a.raw])
            case .tools(let rs):
                let parts: [[String: Any]] = rs.map { (r: AIToolResult) -> [String: Any] in
                    return ["functionResponse": ["name": r.call.name, "response": ["result": r.output] as [String: Any]] as [String: Any]]
                }
                contents.append(["role": "user", "parts": parts])
            }
        }
        var body: [String: Any] = ["systemInstruction": ["parts": [["text": system]]] as [String: Any], "contents": contents]
        if !tools.isEmpty {
            let decls: [[String: Any]] = tools.map { (t: AIToolDef) -> [String: Any] in
                return ["name": t.name, "description": t.description, "parameters": geminiSchema(t.schema)]
            }
            body["tools"] = [["functionDeclarations": decls]]
        }
        let name = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
        let o = try await request(AIStore.baseURL(p) + "/models/" + name + ":generateContent",
                                  headers: ["x-goog-api-key": key], body: body, timeout: timeout)
        guard let cand = (o["candidates"] as? [[String: Any]])?.first else {
            throw AIError(message: "Gemini không trả kết quả (có thể câu hỏi bị chặn).")
        }
        let parts = ((cand["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        if parts.isEmpty { throw AIError(message: "Gemini không trả nội dung (có thể bị chặn hoặc hết hạn mức).") }
        var text = ""
        var calls: [AIToolCall] = []
        for (i, part) in parts.enumerated() {
            if let fc = part["functionCall"] as? [String: Any] {
                calls.append(AIToolCall(id: "g\(i)", name: (fc["name"] as? String) ?? "", args: (fc["args"] as? [String: Any]) ?? [:]))
            } else if let t = part["text"] as? String, (part["thought"] as? Bool) != true {
                text += t
            }
        }
        return AITurn(text: text, calls: calls, raw: parts)
    }

    /// Gemini yêu cầu kiểu schema viết hoa (OBJECT, STRING, INTEGER).
    static func geminiSchema(_ v: Any) -> Any {
        if let d = v as? [String: Any] {
            var o: [String: Any] = [:]
            for (k, x) in d {
                if k == "type", let s = x as? String { o[k] = s.uppercased() } else { o[k] = geminiSchema(x) }
            }
            return o
        }
        if let a = v as? [Any] { return a.map { geminiSchema($0) } }
        return v
    }

    // MARK: Dò model
    static func listModels(_ p: AIProvider, key: String) async throws -> [String] {
        switch p.kind {
        case .gemini:
            let o = try await request(AIStore.baseURL(p) + "/models?pageSize=200", method: "GET", headers: ["x-goog-api-key": key], body: nil)
            let ms = (o["models"] as? [[String: Any]]) ?? []
            let names: [String] = ms.compactMap { (m: [String: Any]) -> String? in
                let methods = (m["supportedGenerationMethods"] as? [String]) ?? []
                guard methods.contains("generateContent"), let n = m["name"] as? String else { return nil }
                return n.hasPrefix("models/") ? String(n.dropFirst(7)) : n
            }
            return names.sorted()
        case .claude:
            let o = try await request(AIStore.baseURL(p) + "/models?limit=100", method: "GET",
                                      headers: ["x-api-key": key, "anthropic-version": "2023-06-01"], body: nil)
            let ms = (o["data"] as? [[String: Any]]) ?? []
            return ms.compactMap { (m: [String: Any]) -> String? in return m["id"] as? String }.sorted()
        case .openai:
            let o = try await request(AIStore.baseURL(p) + "/models", method: "GET", headers: ["Authorization": "Bearer " + key], body: nil)
            let ms = (o["data"] as? [[String: Any]]) ?? []
            return ms.compactMap { (m: [String: Any]) -> String? in return m["id"] as? String }.sorted()
        }
    }

    /// Thử một câu ngắn để biết khoá + model dùng được không.
    static func test(_ p: AIProvider, key: String, model: String) async -> String {
        do {
            let t = try await chat(p, key: key, model: model, system: "Trả lời cực ngắn.", msgs: [.user("Trả lời đúng một từ: OK")], tools: [])
            let s = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Kết nối được. Model trả lời: " + (s.isEmpty ? "(trống)" : String(s.prefix(60)))
        } catch {
            return "Lỗi: " + error.localizedDescription + "\n\n" + diag(p, key: key, model: model)
        }
    }

    /// Thông tin chẩn đoán (không lộ khoá): địa chỉ đang gọi, model, khoá rút gọn + độ dài.
    static func diag(_ p: AIProvider, key: String, model: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let kp = k.count > 10 ? String(k.prefix(6)) + "…" + String(k.suffix(4)) : "(quá ngắn)"
        let m = model.isEmpty ? "(TRỐNG — hãy nhập tên model)" : model
        let path = p.kind == .claude ? "/messages" : (p.kind == .gemini ? "/models/…:generateContent" : "/chat/completions")
        return "Đang gọi: " + AIStore.baseURL(p) + path + "\nModel: " + m + "\nKhoá: " + kp + " (" + String(k.count) + " ký tự)"
    }
}

// MARK: - Tự dò model dùng được
struct AIModelCheck {
    enum State { case ok, okNoTools, limited, failed }
    var model: String
    var state: State
    var ms: Int
    var note: String
    var usable: Bool { return state == .ok || state == .okNoTools }
}

extension AIClient {
    /// Bỏ model không phải chat văn bản (embedding, ảnh, tiếng nói, video…) và xếp model nhanh/"latest" lên trước.
    static func rankChatModels(_ p: AIProvider, _ models: [String]) -> [String] {
        let bad = ["embed", "tts", "image", "imagen", "veo", "audio", "aqa", "whisper", "moderation", "dall", "transcribe",
                   "realtime", "robotics", "computer-use", "live", "guard", "rerank", "search", "diffusion", "lyria", "gemma-3n"]
        let good = models.filter { (m: String) -> Bool in
            let l = m.lowercased()
            return !bad.contains(where: { l.contains($0) })
        }
        // Bậc ưu tiên (nhỏ = thử trước): 0 chat nhanh bản "latest" · 1 chat nhanh ổn định · 2 chat lớn ổn định · 3 bản lite · 4 preview/thử nghiệm/suy luận
        func tier(_ m: String) -> Int {
            let l = m.lowercased()
            if l.contains("preview") || l.contains("exp") || l.contains("thinking") || l.contains("reason") || l.contains("-r1") { return 4 }
            if l.contains("lite") || l.contains("nano") { return 3 }
            let fast = ["flash", "mini", "haiku", "small", "versatile", "instant", "chat"].contains(where: { l.contains($0) })
            if fast && l.contains("latest") { return 0 }
            if fast { return 1 }
            return 2
        }
        // Cùng bậc: số phiên bản cao hơn trước (2.5 trước 2.0), so số tự nhiên chứ không so chữ
        return good.sorted { (a: String, b: String) -> Bool in
            let ta = tier(a), tb = tier(b)
            if ta != tb { return ta < tb }
            return a.compare(b, options: [.numeric, .caseInsensitive]) == .orderedDescending
        }
    }

    /// Thử một model bằng một câu ngắn (có kèm công cụ giả; nếu bị từ chối thì thử lại không công cụ).
    static func checkModel(_ p: AIProvider, key: String, model m: String) async -> AIModelCheck {
        let t0 = Date()
        func ms() -> Int { return Int(Date().timeIntervalSince(t0) * 1000) }
        let tool = AIToolDef(name: "ping", description: "Kiểm tra kết nối",
                             schema: ["type": "object", "properties": ["q": ["type": "string"] as [String: Any]] as [String: Any]])
        let msgs: [AIMsg] = [.user("Trả lời đúng một từ: OK")]
        do {
            _ = try await chat(p, key: key, model: m, system: "Trả lời cực ngắn.", msgs: msgs, tools: [tool], timeout: 25)
            return AIModelCheck(model: m, state: .ok, ms: ms(), note: "")
        } catch let e as AIError {
            if e.status == 429 { return AIModelCheck(model: m, state: .limited, ms: ms(), note: "hết hạn mức / quá nhiều yêu cầu") }
            if e.status == 400 || e.status == 404 || e.status == 422 {
                do {
                    _ = try await chat(p, key: key, model: m, system: "Trả lời cực ngắn.", msgs: msgs, tools: [], timeout: 25)
                    return AIModelCheck(model: m, state: .okNoTools, ms: ms(), note: "chạy được nhưng không gọi công cụ")
                } catch let e2 as AIError {
                    return AIModelCheck(model: m, state: e2.status == 429 ? .limited : .failed, ms: ms(), note: String(e2.message.prefix(80)))
                } catch {
                    return AIModelCheck(model: m, state: .failed, ms: ms(), note: "lỗi")
                }
            }
            return AIModelCheck(model: m, state: .failed, ms: ms(), note: String(e.message.prefix(80)))
        } catch {
            return AIModelCheck(model: m, state: .failed, ms: ms(), note: "lỗi")
        }
    }

    /// Thử tối đa `limit` model (ưu tiên `first` rồi model nhanh), 3 model cùng lúc để không vượt hạn mức. Gọi `progress` sau mỗi kết quả.
    static func probe(_ p: AIProvider, key: String, models: [String], first: [String] = [], limit: Int = 10,
                      progress: @escaping @MainActor (AIModelCheck, Int, Int) -> Void) async -> [AIModelCheck] {
        var cands: [String] = []
        for m in first + rankChatModels(p, models) where !m.isEmpty && !cands.contains(m) { cands.append(m) }
        cands = Array(cands.prefix(limit))
        var results: [AIModelCheck] = []
        await withTaskGroup(of: AIModelCheck.self) { (g: inout TaskGroup<AIModelCheck>) in
            var next = 0
            while next < min(3, cands.count) {
                let m = cands[next]; next += 1
                g.addTask { await AIClient.checkModel(p, key: key, model: m) }
            }
            while let r = await g.next() {
                results.append(r)
                await progress(r, results.count, cands.count)
                if Task.isCancelled { g.cancelAll(); break }
                if next < cands.count {
                    let m = cands[next]; next += 1
                    g.addTask { await AIClient.checkModel(p, key: key, model: m) }
                }
            }
        }
        return results
    }
}
