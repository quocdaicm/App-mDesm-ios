// DesmAPI.swift — gọi API .do của DESM bằng URLSession + cookie phiên (không phụ thuộc trang đang mở).
//
// Trước đây desmQuery chạy fetch bên trong WKWebView nên lỗi khi trang đang ở login hoặc hết phiên, và không chạy được khi app ở nền.
// Giờ: lấy cookie từ kho cookie của WebView (nếu còn) hoặc từ bản lưu Keychain (SessionStore.storedCookies), rồi POST bằng URLSession.
// Nếu URLSession lỗi (không phải hết phiên) và vẫn còn WebView thì lùi về cách cũ (desmQueryViaWebView).
// CHƯA kiểm chứng trên máy thật: máy chủ có đòi thêm header (Referer/Origin đã gửi) hay khác biệt User-Agent không.

import Foundation
import WebKit

enum DesmAPIError: LocalizedError {
    case noSession
    case expired
    case notJSON(Int)
    case server
    case unreadable
    case noProject
    case network(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .noSession: return "Chưa có phiên đăng nhập DESM. Hãy mở DESM và đăng nhập trước."
        case .expired: return "Phiên DESM đã hết hạn. Hãy đăng nhập lại."
        case .notJSON(let code): return "HTTP \(code): phản hồi không phải JSON (có thể đã hết phiên)"
        case .server: return "Máy chủ trả về lỗi."
        case .unreadable: return "Không đọc được phản hồi."
        case .noProject: return "Chưa có dự án mặc định trong DESM."
        case .network(let m): return "Không tải được: \(m)"
        case .message(let m): return m
        }
    }
}

/// Kết quả đã phân tích JSON (làm ở luồng nền: phản hồi vài MB mà parse trên luồng chính sẽ làm giao diện đứng).
struct DesmRowsBox: @unchecked Sendable {
    let isJSON: Bool
    let rows: [[String: Any]]?

    static func parse(_ data: Data) -> DesmRowsBox {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return DesmRowsBox(isJSON: false, rows: nil) }
        let x = obj["results"]
        if let list = x as? [[String: Any]] { return DesmRowsBox(isJSON: true, rows: list) }
        if let d = x as? [String: Any], let list = d["list"] as? [[String: Any]] { return DesmRowsBox(isJSON: true, rows: list) }
        return DesmRowsBox(isJSON: true, rows: nil)
    }
}

extension BrowserModel {
    static let apiOrigin = "https://desm.doosanenerbility.com"

    /// Phiên dùng chung (trước đây mỗi lần gọi tạo một URLSession mới mà không huỷ → rò rỉ). Có giới hạn TỔNG thời gian.
    private static let httpSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    /// Cookie DESM: ưu tiên kho cookie của WebView (mới nhất); không có thì dùng bản lưu trong Keychain (chạy được khi không có WebView).
    @MainActor
    func desmCookies() async -> [HTTPCookie] {
        if let store = webView?.configuration.websiteDataStore.httpCookieStore {
            let all: [HTTPCookie] = await withCheckedContinuation { cont in
                store.getAllCookies { cont.resume(returning: $0) }
            }
            let mine = all.filter { $0.domain.lowercased().contains("doosanenerbility") }
            if !mine.isEmpty { return mine }
        }
        return SessionStore.storedCookies()
    }

    /// POST một endpoint .do bằng phiên đăng nhập hiện có; trả mảng dòng (results hoặc results.list).
    @MainActor
    func desmQueryAsync(_ path: String, body: String) async throws -> [[String: Any]] {
        do {
            return try await desmQueryHTTP(path, body: body)
        } catch DesmAPIError.expired {
            throw DesmAPIError.expired
        } catch DesmAPIError.noSession {
            throw DesmAPIError.noSession
        } catch {
            guard webView != nil else { throw error }
            AILog.add("↩︎ " + path + " URLSession lỗi (" + error.localizedDescription + ") → thử qua trang web")
            return try await desmQueryViaWebView(path, body: body)   // đường lui
        }
    }

    @MainActor
    private func desmQueryHTTP(_ path: String, body: String) async throws -> [[String: Any]] {
        guard let base = URL(string: Self.apiOrigin), let url = URL(string: path, relativeTo: base)?.absoluteURL,
              url.host?.lowercased().hasSuffix("doosanenerbility.com") == true else { throw DesmAPIError.message("Địa chỉ không hợp lệ.") }
        let cookies = await desmCookies()
        guard !cookies.isEmpty else { throw DesmAPIError.noSession }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        req.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies)
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue(Self.apiOrigin, forHTTPHeaderField: "Origin")
        req.setValue(Self.homeURL, forHTTPHeaderField: "Referer")
        let t0 = Date()
        let result: (Data, URLResponse)
        do { result = try await Self.httpSession.data(for: req) }
        catch {
            AILog.add("✗ HTTP " + path + " lỗi sau " + String(format: "%.1f", Date().timeIntervalSince(t0)) + "s: " + error.localizedDescription)
            throw DesmAPIError.network(error.localizedDescription)
        }
        let data = result.0
        guard let http = result.1 as? HTTPURLResponse else { throw DesmAPIError.unreadable }
        if http.statusCode == 401 { throw DesmAPIError.expired }
        if http.url?.path.lowercased().contains("login") == true { throw DesmAPIError.expired }   // bị chuyển về trang đăng nhập
        let t1 = Date()
        // Phân tích JSON ở luồng nền rồi mới quay lại luồng chính
        let box = await Task.detached(priority: .userInitiated) { () -> DesmRowsBox in return DesmRowsBox.parse(data) }.value
        AILog.add("← " + path + " HTTP " + String(http.statusCode) + ", " + String(data.count / 1024) + " KB, mạng " + String(format: "%.1f", t1.timeIntervalSince(t0)) + "s, phân tích " + String(format: "%.2f", Date().timeIntervalSince(t1)) + "s")
        if !box.isJSON { throw DesmAPIError.notJSON(http.statusCode) }
        guard let rows = box.rows else { throw DesmAPIError.server }
        return rows
    }

    /// Đường lui: chạy fetch ngay trong trang DESM đang mở (cách cũ). Chỉ dùng khi URLSession gặp lỗi không phải hết phiên.
    @MainActor
    func desmQueryViaWebView(_ path: String, body: String) async throws -> [[String: Any]] {
        guard let webView = webView else { throw DesmAPIError.noSession }
        let js = #"""
        if (!/(^|\.)doosanenerbility\.com$/i.test(location.hostname)) return JSON.stringify({ err: 'Hãy mở DESM và đăng nhập trước.' });
        const ac = new AbortController();
        const tm = setTimeout(function() { try { ac.abort(); } catch (e) {} }, 20000);
        try {
          const r = await fetch(path, { method: 'POST', credentials: 'include', cache: 'no-store', signal: ac.signal,
            headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With': 'XMLHttpRequest' }, body: body });
          const t = await r.text(); clearTimeout(tm); let s;
          try { s = JSON.parse(t); } catch (e) { return JSON.stringify({ err: 'HTTP ' + r.status + ': phản hồi không phải JSON (có thể đã hết phiên)' }); }
          const x = s && s.results;
          const list = Array.isArray(x) ? x : (x && Array.isArray(x.list) ? x.list : null);
          if (!list) return JSON.stringify({ err: 'Máy chủ trả về lỗi.' });
          return JSON.stringify({ list: list });
        } catch (e) {
          clearTimeout(tm);
          if (e && e.name === 'AbortError') return JSON.stringify({ err: 'Quá thời gian chờ (20 giây) khi tải dữ liệu từ trang.' });
          return JSON.stringify({ err: String(e && e.message || e) });
        }
        """#
        let t0 = Date()
        let result: Any?
        do {
            // callAsyncJavaScript không tự hết hạn (trang bận/đang chuyển trang thì chờ mãi) → đua với đồng hồ 25 giây
            result = try await aiRaceThrowing(25, timeoutError: DesmAPIError.network("trang web không phản hồi sau 25 giây")) {
                return try await webView.callAsyncJavaScript(js, arguments: ["path": path, "body": body], in: nil, in: .page)
            }
        } catch {
            AILog.add("✗ WebView " + path + " lỗi sau " + String(format: "%.1f", Date().timeIntervalSince(t0)) + "s: " + error.localizedDescription)
            if error is DesmAPIError { throw error }
            throw DesmAPIError.network(error.localizedDescription)
        }
        AILog.add("← WebView " + path + " xong sau " + String(format: "%.1f", Date().timeIntervalSince(t0)) + "s")
        guard let text = result as? String, let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DesmAPIError.unreadable }
        if let err = obj["err"] as? String { throw DesmAPIError.message(err) }
        return obj["list"] as? [[String: Any]] ?? []
    }

    /// Số dự án mặc định (SEGMENT1 của getInitDefailProject.do) — hầu hết màn hình cần nó trước.
    /// Có nhớ đệm 30 phút: trước đây MỖI lần tìm đều gọi thêm một request này trước request chính (hai lượt mạng nối tiếp).
    @MainActor
    func desmProjectNo() async throws -> String {
        if let c = DesmProjectCache.value, Date().timeIntervalSince(c.at) < 1800 { return c.no }
        do {
            let rows = try await desmQueryAsync("/getInitDefailProject.do", body: "")
            guard let no = rows.first?["SEGMENT1"] as? String, !no.isEmpty else { throw DesmAPIError.noProject }
            DesmProjectCache.value = (no, Date())
            return no
        } catch {
            DesmProjectCache.value = nil   // lỗi/hết phiên: lần sau hỏi lại
            throw error
        }
    }

    /// Bản callback cũ (giữ để các màn hình chưa chuyển sang async vẫn chạy). `done` luôn được gọi trên main.
    func desmQuery(_ path: String, body: String, done: @escaping ([[String: Any]]?, String) -> Void) {
        Task { @MainActor in
            do { done(try await self.desmQueryAsync(path, body: body), "") }
            catch { done(nil, error.localizedDescription) }
        }
    }
}

/// Nhớ số dự án mặc định để các màn hình không phải hỏi máy chủ lại ở mỗi lần tìm.
enum DesmProjectCache { @MainActor static var value: (no: String, at: Date)? = nil }
