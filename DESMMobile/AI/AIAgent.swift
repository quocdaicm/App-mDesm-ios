// AIAgent.swift — vòng "AI gọi công cụ" (function calling) cho cả 3 kiểu API: Gemini, Claude, OpenAI-compatible.
// AI hỏi công cụ → app chạy (chỉ đọc) → trả kết quả → AI trả lời. Tối đa 6 vòng.

import Foundation

extension AIClient {
    typealias ToolExec = (String, [String: Any]) async -> String

    /// Như `run` nhưng cho phép AI gọi công cụ. Nhà nào không hỗ trợ công cụ thì tự lùi về hỏi đáp thường.
    static func runAgent(_ providers: [AIConfig], system: String, messages: [Msg], tools: [AITool],
                         exec: @escaping ToolExec, status: @escaping (String) -> Void,
                         timeout: TimeInterval = 90) async throws -> (text: String, by: AIConfig) {
        var last: Error?
        for c in providers {
            do {
                let t = try await agent(c, system, messages, tools, exec, status, timeout)
                return (t, c)
            } catch {
                if Task.isCancelled { throw error }
                // Nhà/model không hỗ trợ công cụ → thử hỏi đáp thường với cùng nhà
                if case AIError.http(let code, _)? = error as? AIError, [400, 404, 422].contains(code) {
                    status("Model này không hỗ trợ công cụ, trả lời không tra DESM…")
                    if let t = try? await complete(c, system: system, messages: messages, temperature: 0.3, timeout: 60) {
                        return (t + "\n\n(Model này không hỗ trợ gọi công cụ nên chưa tra dữ liệu DESM. Hãy chọn model khác, ví dụ Gemini/Claude/GPT.)", c)
                    }
                }
                last = AIProviderError(provider: c.id.shortName, underlying: error)
            }
        }
        throw last ?? AIError.badResponse
    }

    private static func agent(_ c: AIConfig, _ system: String, _ messages: [Msg], _ tools: [AITool],
                              _ exec: @escaping ToolExec, _ status: @escaping (String) -> Void,
                              _ timeout: TimeInterval) async throws -> String {
        switch c.id.kind {
        case .gemini:    return try await geminiAgent(c, system, messages, tools, exec, status, timeout)
        case .anthropic: return try await anthropicAgent(c, system, messages, tools, exec, status, timeout)
        case .openAI:    return try await openAIAgent(c, system, messages, tools, exec, status, timeout)
        }
    }

    private static let maxSteps = 6

    private static func argsDict(_ any: Any?) -> [String: Any] {
        if let d = any as? [String: Any] { return d }
        if let s = any as? String, let d = s.data(using: .utf8),
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { return o }
        return [:]
    }

    // MARK: OpenAI-compatible
    private static func openAIAgent(_ c: AIConfig, _ system: String, _ messages: [Msg], _ tools: [AITool],
                                    _ exec: @escaping ToolExec, _ status: @escaping (String) -> Void,
                                    _ timeout: TimeInterval) async throws -> String {
        var base = c.base
        while base.hasSuffix("/") { base.removeLast() }
        let full = base.hasSuffix("/chat/completions") ? base : base + "/chat/completions"
        guard let url = URL(string: full) else { throw AIError.badResponse }
        var headers: [String: String] = [:]
        if !c.key.isEmpty { headers["Authorization"] = "Bearer \(c.key)" }

        var msgs: [[String: Any]] = []
        if !system.isEmpty { msgs.append(["role": "system", "content": system]) }
        msgs += messages.map { ["role": $0.role == "model" ? "assistant" : "user", "content": $0.text] }
        let defs: [[String: Any]] = tools.map {
            ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]]
        }

        for step in 0..<maxSteps {
            var body: [String: Any] = ["model": c.model, "messages": msgs]
            if step < maxSteps - 1 { body["tools"] = defs }
            let root = try await post(url, headers: headers, body: body, timeout: timeout)
            guard let choices = root["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else { throw AIError.badResponse }
            if let calls = message["tool_calls"] as? [[String: Any]], !calls.isEmpty {
                var a: [String: Any] = ["role": "assistant", "tool_calls": calls]
                if let t = message["content"] as? String, !t.isEmpty { a["content"] = t }
                msgs.append(a)
                for call in calls {
                    let fn = call["function"] as? [String: Any] ?? [:]
                    let name = fn["name"] as? String ?? ""
                    status("Đang tra DESM: \(name)…")
                    let result = await exec(name, argsDict(fn["arguments"]))
                    msgs.append(["role": "tool", "tool_call_id": call["id"] as? String ?? "", "content": result])
                }
                continue
            }
            let t = ((message["content"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { throw AIError.badResponse }
            return t
        }
        throw AIError.badResponse
    }

    // MARK: Anthropic
    private static func anthropicAgent(_ c: AIConfig, _ system: String, _ messages: [Msg], _ tools: [AITool],
                                       _ exec: @escaping ToolExec, _ status: @escaping (String) -> Void,
                                       _ timeout: TimeInterval) async throws -> String {
        guard let url = URL(string: c.base) else { throw AIError.badResponse }
        let headers = ["x-api-key": c.key, "anthropic-version": "2023-06-01"]
        var msgs: [[String: Any]] = messages.map {
            ["role": $0.role == "model" ? "assistant" : "user", "content": $0.text]
        }
        let defs: [[String: Any]] = tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] }

        for step in 0..<maxSteps {
            var body: [String: Any] = ["model": c.model, "max_tokens": 4096, "messages": msgs]
            if !system.isEmpty { body["system"] = system }
            if step < maxSteps - 1 { body["tools"] = defs }
            let root = try await post(url, headers: headers, body: body, timeout: timeout)
            guard let content = root["content"] as? [[String: Any]] else { throw AIError.badResponse }
            let uses = content.filter { ($0["type"] as? String) == "tool_use" }
            if !uses.isEmpty {
                msgs.append(["role": "assistant", "content": content])
                var results: [[String: Any]] = []
                for u in uses {
                    let name = u["name"] as? String ?? ""
                    status("Đang tra DESM: \(name)…")
                    let r = await exec(name, argsDict(u["input"]))
                    results.append(["type": "tool_result", "tool_use_id": u["id"] as? String ?? "", "content": r])
                }
                msgs.append(["role": "user", "content": results])
                continue
            }
            let t = content.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { throw AIError.badResponse }
            return t
        }
        throw AIError.badResponse
    }

    // MARK: Gemini
    private static func geminiAgent(_ c: AIConfig, _ system: String, _ messages: [Msg], _ tools: [AITool],
                                    _ exec: @escaping ToolExec, _ status: @escaping (String) -> Void,
                                    _ timeout: TimeInterval) async throws -> String {
        var name = c.model
        if name.hasPrefix("models/") { name = String(name.dropFirst(7)) }
        guard let url = URL(string: "\(c.base)/models/\(name):generateContent") else { throw AIError.badResponse }
        var contents: [[String: Any]] = messages.map { ["role": $0.role, "parts": [["text": $0.text]]] }
        let decls: [[String: Any]] = tools.map { t in
            var d: [String: Any] = ["name": t.name, "description": t.description]
            // Gemini không nhận object rỗng không có properties
            if let props = t.parameters["properties"] as? [String: Any], !props.isEmpty { d["parameters"] = t.parameters }
            return d
        }

        for step in 0..<maxSteps {
            var body: [String: Any] = ["contents": contents, "generationConfig": ["temperature": 0.3]]
            if !system.isEmpty { body["system_instruction"] = ["parts": [["text": system]]] }
            if step < maxSteps - 1 { body["tools"] = [["functionDeclarations": decls]] }
            let root = try await post(url, headers: ["x-goog-api-key": c.key], body: body, timeout: timeout)
            guard let cands = root["candidates"] as? [[String: Any]],
                  let content = cands.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { throw AIError.badResponse }
            let calls = parts.filter { $0["functionCall"] != nil }
            if !calls.isEmpty {
                contents.append(["role": "model", "parts": parts])   // giữ nguyên (kể cả thoughtSignature)
                var resp: [[String: Any]] = []
                for p in calls {
                    let fc = p["functionCall"] as? [String: Any] ?? [:]
                    let n = fc["name"] as? String ?? ""
                    status("Đang tra DESM: \(n)…")
                    let r = await exec(n, argsDict(fc["args"]))
                    resp.append(["functionResponse": ["name": n, "response": ["result": r]]])
                }
                contents.append(["role": "user", "parts": resp])
                continue
            }
            let t = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }
                .joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { throw AIError.badResponse }
            return t
        }
        throw AIError.badResponse
    }
}
