// AIProviders.swift — danh sách nhà AI, khoá API (Keychain) và cấu hình (UserDefaults) của "AI riêng".
// Khoá API chỉ lưu trong Keychain của máy này (service "DESMMobile.AI"). Chưa build/chưa thử trên máy thật.

import Foundation
import Security

enum AIKind { case openai, claude, gemini }

struct AIProvider: Identifiable {
    let id: String
    let name: String
    let kind: AIKind
    let baseURL: String        // "custom" để trống: người dùng tự nhập
    let defaultModel: String
    let keyHelp: String

    static let all: [AIProvider] = [
        AIProvider(id: "gemini", name: "Google Gemini", kind: .gemini,
                   baseURL: "https://generativelanguage.googleapis.com/v1beta", defaultModel: "gemini-2.5-flash",
                   keyHelp: "Lấy khoá tại aistudio.google.com/apikey"),
        AIProvider(id: "claude", name: "Anthropic Claude", kind: .claude,
                   baseURL: "https://api.anthropic.com/v1", defaultModel: "claude-haiku-5-5",
                   keyHelp: "Lấy khoá tại console.anthropic.com"),
        AIProvider(id: "openai", name: "OpenAI", kind: .openai,
                   baseURL: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini",
                   keyHelp: "Lấy khoá tại platform.openai.com/api-keys"),
        AIProvider(id: "groq", name: "Groq", kind: .openai,
                   baseURL: "https://api.groq.com/openai/v1", defaultModel: "llama-3.3-70b-versatile",
                   keyHelp: "Lấy khoá tại console.groq.com/keys"),
        AIProvider(id: "deepseek", name: "DeepSeek", kind: .openai,
                   baseURL: "https://api.deepseek.com/v1", defaultModel: "deepseek-chat",
                   keyHelp: "Lấy khoá tại platform.deepseek.com"),
        AIProvider(id: "mistral", name: "Mistral", kind: .openai,
                   baseURL: "https://api.mistral.ai/v1", defaultModel: "mistral-small-latest",
                   keyHelp: "Lấy khoá tại console.mistral.ai"),
        AIProvider(id: "openrouter", name: "OpenRouter", kind: .openai,
                   baseURL: "https://openrouter.ai/api/v1", defaultModel: "openai/gpt-4o-mini",
                   keyHelp: "Lấy khoá tại openrouter.ai/keys"),
        AIProvider(id: "custom", name: "Tùy chỉnh (OpenAI-compatible)", kind: .openai,
                   baseURL: "", defaultModel: "",
                   keyHelp: "Nhập địa chỉ API dạng https://máy-chủ/v1 và khoá của nhà đó"),
    ]
}

enum AIStore {
    static let service = "DESMMobile.AI"

    // MARK: Keychain
    private static func baseQuery(_ account: String) -> [String: Any] {
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account]
    }

    // Keychain là IPC sang tiến trình khác, có lúc chậm hàng chục ms (thậm chí treo lúc máy vừa mở khoá) mà `key()` từng bị gọi 8 lần
    // mỗi lần khung chat vẽ lại ở luồng chính → giữ bản sao trong bộ nhớ, chỉ đọc Keychain lần đầu của mỗi nhà.
    private static let cacheLock = NSLock()
    private static var keyCache: [String: String] = [:]

    static func key(_ id: String) -> String {
        cacheLock.lock()
        if let c = keyCache[id] { cacheLock.unlock(); return c }
        cacheLock.unlock()
        let t0 = Date()
        var q = baseQuery(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        var v = ""
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data {
            v = String(data: d, encoding: .utf8) ?? ""
        }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if ms >= 50 { AILog.add("⚠️ Keychain đọc khoá " + id + " mất " + String(ms) + "ms") }
        cacheLock.lock(); keyCache[id] = v; cacheLock.unlock()
        return v
    }

    static func setKey(_ k: String, for id: String) {
        let t = k.trimmingCharacters(in: .whitespacesAndNewlines)
        cacheLock.lock(); keyCache[id] = t; cacheLock.unlock()
        SecItemDelete(baseQuery(id) as CFDictionary)
        guard !t.isEmpty, let d = t.data(using: .utf8) else { return }
        var q = baseQuery(id)
        q[kSecValueData as String] = d
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    // MARK: Cấu hình
    static var activeID: String {
        get { UserDefaults.standard.string(forKey: "desmAIActive") ?? "gemini" }
        set { UserDefaults.standard.set(newValue, forKey: "desmAIActive") }
    }

    static var active: AIProvider {
        return AIProvider.all.first(where: { $0.id == activeID }) ?? AIProvider.all[0]
    }

    /// Cho AI tự gọi API DESM (chỉ đọc). Mặc định bật khi đã chọn dùng AI riêng.
    static var toolsOn: Bool {
        get { UserDefaults.standard.object(forKey: "desmAITools") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "desmAITools") }
    }

    // MARK: Tự chuyển nhà AI khi lỗi
    /// Bật: nhà đang chọn lỗi/quá hạn thì tự thử nhà kế tiếp có khoá (mặc định bật).
    static var autoSwitch: Bool {
        get { UserDefaults.standard.object(forKey: "desmAIAutoSwitch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "desmAIAutoSwitch") }
    }

    private static let failLock = NSLock()
    private static var failedAt: [String: Date] = [:]
    static let cooldownSeconds: TimeInterval = 300

    /// Nhà vừa lỗi được cho "nghỉ" 5 phút: các câu hỏi sau không phải chờ nó hết hạn (60 giây) rồi mới sang nhà khác.
    static func markFailed(_ id: String) { failLock.lock(); failedAt[id] = Date(); failLock.unlock() }
    static func clearFailed(_ id: String) { failLock.lock(); failedAt[id] = nil; failLock.unlock() }
    static func isCoolingDown(_ id: String) -> Bool {
        failLock.lock(); defer { failLock.unlock() }
        if let t = failedAt[id] { return Date().timeIntervalSince(t) < cooldownSeconds }
        return false
    }

    /// Nhà dùng được: có khoá và có model (nhà "Tuỳ chỉnh" còn cần địa chỉ API).
    static func usable(_ p: AIProvider) -> Bool {
        if key(p.id).isEmpty || model(p).isEmpty { return false }
        if p.id == "custom" && baseURL(p).isEmpty { return false }
        return true
    }

    /// Thứ tự thử cho một câu hỏi: nhà đang chọn trước, rồi các nhà còn lại theo thứ tự trong danh sách; nhà đang "nghỉ" xếp cuối; tối đa 4 nhà.
    static func candidates() -> [AIProvider] {
        let act = active
        if !autoSwitch { return usable(act) ? [act] : [] }
        let all = [act] + AIProvider.all.filter { $0.id != act.id }
        let ok = all.filter { usable($0) }
        let ready = ok.filter { !isCoolingDown($0.id) }
        let cooling = ok.filter { isCoolingDown($0.id) }
        return Array((ready + cooling).prefix(4))
    }

    static func model(_ p: AIProvider) -> String {
        let m = (UserDefaults.standard.string(forKey: "desmAIModel." + p.id) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? p.defaultModel : m
    }

    static func setModel(_ m: String, for id: String) {
        UserDefaults.standard.set(m.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "desmAIModel." + id)
    }

    static func baseURL(_ p: AIProvider) -> String {
        var b = p.id == "custom" ? (UserDefaults.standard.string(forKey: "desmAIBase.custom") ?? "") : p.baseURL
        b = b.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }

    static func setCustomBase(_ b: String) {
        UserDefaults.standard.set(b.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "desmAIBase.custom")
    }
}
