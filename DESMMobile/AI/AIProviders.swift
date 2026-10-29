// AIProviders.swift — các nhà cung cấp AI riêng (API key của chính bạn), chuyển từ app LiveTranslate.
// Dùng cho khung chat "AI riêng" thay cho Dodo của web DESM. Key lưu trong Keychain của máy.

import Foundation
import Security
import SwiftUI

// MARK: - Keychain riêng cho key AI
enum AIKeychain {
    private static let service = "DESMMobile.AI"

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Nhà cung cấp
enum AIProviderKind { case gemini, anthropic, openAI }

enum AIProvider: String, CaseIterable, Identifiable {
    case gemini, groq, anthropic, openai, deepseek, mistral, openrouter, custom
    var id: String { rawValue }

    var name: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .groq: return "Groq"
        case .anthropic: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .mistral: return "Mistral"
        case .openrouter: return "OpenRouter"
        case .custom: return "Tùy chỉnh (OpenAI-compatible)"
        }
    }
    var shortName: String {
        switch self {
        case .anthropic: return "Claude"
        case .custom: return "Tùy chỉnh"
        case .gemini: return "Gemini"
        default: return name
        }
    }
    var kind: AIProviderKind {
        switch self {
        case .gemini: return .gemini
        case .anthropic: return .anthropic
        default: return .openAI
        }
    }
    var defaultBase: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .openai: return "https://api.openai.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .mistral: return "https://api.mistral.ai/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .custom: return ""
        }
    }
    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-flash-latest"
        case .anthropic: return "claude-haiku-4-5-20251001"
        case .openai: return "gpt-4o-mini"
        case .groq: return "llama-3.3-70b-versatile"
        case .mistral: return "mistral-small-latest"
        case .deepseek: return "deepseek-chat"
        case .openrouter: return "meta-llama/llama-3.3-70b-instruct:free"
        case .custom: return ""
        }
    }
    var keyURL: URL? {
        switch self {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .deepseek: return URL(string: "https://platform.deepseek.com/api_keys")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        case .openrouter: return URL(string: "https://openrouter.ai/keys")
        case .custom: return nil
        }
    }
    var note: String {
        switch self {
        case .gemini: return "Có gói miễn phí (giới hạn theo phút/ngày), không cần thẻ."
        case .groq: return "Có gói miễn phí, không cần thẻ, tốc độ rất nhanh."
        case .anthropic: return "Trả phí theo lượng dùng, cần nạp tiền trước."
        case .openai: return "Trả phí theo lượng dùng."
        case .deepseek: return "Giá rẻ, trả phí theo lượng dùng."
        case .mistral: return "Có gói miễn phí (có thể cần xác minh số điện thoại)."
        case .openrouter: return "Có một số model miễn phí (tên kết thúc bằng :free), giới hạn số yêu cầu mỗi ngày."
        case .custom: return "Dùng dịch vụ tương thích OpenAI (Ollama/LM Studio trên máy tính, Together…). Nhập Base URL kết thúc bằng /v1."
        }
    }
    var icon: String {
        switch self {
        case .gemini: return "sparkles"
        case .groq: return "bolt.fill"
        case .anthropic: return "asterisk"
        case .openai: return "circle.hexagongrid.fill"
        case .deepseek: return "water.waves"
        case .mistral: return "wind"
        case .openrouter: return "arrow.triangle.branch"
        case .custom: return "server.rack"
        }
    }
    var color: Color {
        switch self {
        case .gemini: return Color(red: 0.35, green: 0.5, blue: 1.0)
        case .groq: return Color(red: 1.0, green: 0.45, blue: 0.2)
        case .anthropic: return Color(red: 0.85, green: 0.5, blue: 0.35)
        case .openai: return Color(red: 0.2, green: 0.75, blue: 0.6)
        case .deepseek: return Color(red: 0.3, green: 0.4, blue: 0.95)
        case .mistral: return Color(red: 1.0, green: 0.65, blue: 0.1)
        case .openrouter: return Color(red: 0.55, green: 0.4, blue: 0.95)
        case .custom: return Color(red: 0.55, green: 0.6, blue: 0.7)
        }
    }

    fileprivate var keyAccount: String { "key.\(rawValue)" }
    fileprivate var enabledKey: String { "desmAI.enabled.\(rawValue)" }
    fileprivate var modelKey: String { "desmAI.model.\(rawValue)" }
    fileprivate var baseKey: String { "desmAI.base.\(rawValue)" }
}

struct AIConfig {
    let id: AIProvider
    let key: String
    let model: String
    let base: String
}

enum AIStore {
    private static var d: UserDefaults { .standard }

    static func key(_ p: AIProvider) -> String { AIKeychain.get(p.keyAccount) ?? "" }
    static func setKey(_ p: AIProvider, _ v: String) {
        AIKeychain.set(v.trimmingCharacters(in: .whitespacesAndNewlines), for: p.keyAccount)
    }

    static func enabled(_ p: AIProvider) -> Bool { d.object(forKey: p.enabledKey) as? Bool ?? true }
    static func setEnabled(_ p: AIProvider, _ v: Bool) { d.set(v, forKey: p.enabledKey) }

    static func model(_ p: AIProvider) -> String {
        let m = (d.string(forKey: p.modelKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? p.defaultModel : m
    }
    static func setModel(_ p: AIProvider, _ v: String) {
        d.set(v.trimmingCharacters(in: .whitespacesAndNewlines), forKey: p.modelKey)
    }

    static func base(_ p: AIProvider) -> String {
        guard p == .custom else { return p.defaultBase }
        return (d.string(forKey: p.baseKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func setBase(_ p: AIProvider, _ v: String) {
        d.set(v.trimmingCharacters(in: .whitespacesAndNewlines), forKey: p.baseKey)
    }

    static func order() -> [AIProvider] {
        let saved = (d.stringArray(forKey: "desmAI.order") ?? []).compactMap { AIProvider(rawValue: $0) }
        return saved + AIProvider.allCases.filter { !saved.contains($0) }
    }
    static func saveOrder(_ o: [AIProvider]) { d.set(o.map { $0.rawValue }, forKey: "desmAI.order") }

    /// nil nếu nhà này đang tắt hoặc thiếu key/base.
    static func config(_ p: AIProvider) -> AIConfig? {
        guard enabled(p) else { return nil }
        let k = key(p)
        let b = base(p)
        if p == .custom {
            guard !b.isEmpty, !model(p).isEmpty else { return nil }
        } else {
            guard !k.isEmpty else { return nil }
        }
        return AIConfig(id: p, key: k, model: model(p), base: b)
    }

    /// Các nhà đã sẵn sàng, theo thứ tự ưu tiên (đầu danh sách dùng trước, lỗi thì chuyển sang nhà kế tiếp).
    static func active() -> [AIConfig] { order().compactMap { config($0) } }
}
