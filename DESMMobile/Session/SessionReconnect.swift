// SessionReconnect.swift — tự kết nối lại khi hết phiên đăng nhập (probeSession, openLogin, appBecameActive).

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Tự kết nối lại khi hết phiên đăng nhập
//
// Vấn đề: sau một thời gian (hoặc qua đêm) phiên DESM phía máy chủ hết hạn, nhưng app vẫn nạp lại địa chỉ cũ với cookie cũ
// nên trang trống/không chạy thay vì quay về trang đăng nhập. Cách xử lý:
//  1) Khi mở app: khôi phục cookie rồi "thăm dò" main.do bằng URLSession; hết phiên (chuyển về login, 401, có ô mật khẩu, hoặc
//     lần dùng cuối quá lâu và đã lưu tài khoản) thì xoá cookie cũ và mở https://desm.doosanenerbility.com/login.do.
//  2) Khi app quay lại từ nền sau > 10 phút: thăm dò tương tự.
//  3) Khi đang dùng: JS (netRecorderSource) phát hiện XHR bị đẩy về login/401/HTML đăng nhập -> message "desmSession".
//  4) Ở trang đăng nhập: app tự điền tài khoản đã lưu (CredStore) và, nếu đang kết nối lại, tự bấm Login (__desmSubmitLogin).
// Chống lặp: tối đa 3 lần kết nối lại / 5 phút và 2 lần tự bấm Login mỗi lần; sau đó chuyển sang đăng nhập thủ công.
// Bật/tắt: Cài đặt > "Tự đăng nhập lại khi hết phiên" (khoá desmAutoReconnect, mặc định bật).
extension BrowserModel {
    static let loginURL = "https://desm.doosanenerbility.com/login.do"
    /// Lần dùng cuối quá ngưỡng này thì coi như phiên đã hết, khỏi thăm dò.
    static let staleSessionAge: TimeInterval = 6 * 3600

    static var edgeSwipe: Bool { UserDefaults.standard.object(forKey: "desmEdgeSwipe") as? Bool ?? true }

    static var autoReconnect: Bool { UserDefaults.standard.object(forKey: "desmAutoReconnect") as? Bool ?? true }

    func markActive() { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "desmLastActive") }

    var lastActiveAge: TimeInterval? {
        let t = UserDefaults.standard.double(forKey: "desmLastActive")
        return t > 0 ? Date().timeIntervalSince1970 - t : nil
    }

    enum SessionProbe { case none, valid, expired, unknown }

    /// Gọi sau mỗi lần tải xong một trang: vào được DESM (không phải trang đăng nhập) = kết nối lại thành công.
    func sessionDidLoad(_ url: URL?) {
        let host = url?.host?.lowercased() ?? ""
        let path = url?.path.lowercased() ?? ""
        guard host == "doosanenerbility.com" || host.hasSuffix(".doosanenerbility.com"), !path.contains("login") else { return }
        markActive()
        if reconnecting { reconnecting = false; autoSubmitCount = 0; pendingHomeTab = true }
        if openPackageOnStart, pendingHomeTab, path.contains("main.do") {
            pendingHomeTab = false
            openHomeTab(attempt: 0)
        }
    }

    /// Mở màn Package ngay sau khi vào main.do. Menu trái nạp chậm nên thử lại tối đa ~12 giây; không mở ngăn kéo menu nếu thất bại.
    func openHomeTab(attempt: Int) {
        let tab = DesmTab.package
        let id = tab.menuId.map { "'\($0)'" } ?? "null"
        let js = "window.__desmOpenMenu ? window.__desmOpenMenu(\(id), '\(tab.pattern)') : 0;"
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.8 : 0.7)) { [weak self] in
            guard let self = self, self.inDesm, attempt < 18 else { return }
            self.webView?.evaluateJavaScript(js) { [weak self] r, _ in
                if (r as? Int ?? 0) == 0 { self?.openHomeTab(attempt: attempt + 1) }
            }
        }
    }

    /// Xoá cookie DESM trong WKWebView (chỉ cookie; giữ localStorage/bộ nhớ đệm khác).
    func clearDesmCookies(_ done: @escaping () -> Void) {
        guard let store = webView?.configuration.websiteDataStore else { done(); return }
        let types: Set<String> = [WKWebsiteDataTypeCookies]
        store.fetchDataRecords(ofTypes: types) { records in
            let mine = records.filter { $0.displayName.lowercased().contains("doosanenerbility") }
            if mine.isEmpty { done(); return }
            store.removeData(ofTypes: types, for: mine) { done() }
        }
    }

    /// Thăm dò xem phiên còn dùng được không (không đụng tới WKWebView). Lỗi mạng -> .unknown (cứ nạp trang như thường).
    func probeSession(_ completion: @escaping (SessionProbe) -> Void) {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { completion(.unknown); return }
        store.getAllCookies { cookies in
            let mine = cookies.filter { $0.domain.lowercased().contains("doosanenerbility") }
            if mine.isEmpty { completion(.none); return }
            guard let url = URL(string: BrowserModel.homeURL) else { completion(.unknown); return }
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            req.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: mine)
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            cfg.timeoutIntervalForRequest = 8
            URLSession(configuration: cfg).dataTask(with: req) { data, resp, err in
                guard err == nil, let http = resp as? HTTPURLResponse else { completion(.unknown); return }
                if http.statusCode == 401 { completion(.expired); return }
                if http.statusCode >= 500 || http.statusCode == 0 { completion(.unknown); return }
                let path = http.url?.path.lowercased() ?? ""
                if path.contains("login") { completion(.expired); return }
                // Không dò "ô mật khẩu" trong HTML nữa: main.do có sẵn form đổi mật khẩu nên luôn bị nhận nhầm là hết phiên.
                // Trường hợp máy chủ trả trang đăng nhập mà không redirect đã có checkLoginForm (ô mật khẩu hiển thị) lo.
                _ = data
                completion(.valid)
            }.resume()
        }
    }

    /// Mở trang đăng nhập (sau khi xoá cookie cũ). `auto` = true: tự điền + tự bấm Login nếu có tài khoản lưu.
    func openLogin(auto: Bool) {
        guard let wv = webView, let url = URL(string: BrowserModel.loginURL) else { return }
        reconnecting = auto
        autoSubmitCount = 0
        SessionStore.clear()
        clearDesmCookies {
            DispatchQueue.main.async { wv.load(URLRequest(url: url, timeoutInterval: 45)) }
        }
    }

    /// Phiên đã hết: xoá phiên cũ và đăng nhập lại. Có giới hạn số lần để không lặp vô hạn.
    func reconnectSession(reason: String) {
        guard BrowserModel.autoReconnect else { return }
        let now = Date()
        if let last = lastReconnectAt, now.timeIntervalSince(last) < 10 { return }
        reconnectTimes = reconnectTimes.filter { now.timeIntervalSince($0) < 300 }
        if reconnectTimes.count >= 3 {
            reconnecting = false
            showToast("Không tự đăng nhập lại được, hãy đăng nhập thủ công")
            return
        }
        reconnectTimes.append(now); lastReconnectAt = now
        showToast(CredStore.load() != nil && CredStore.enabled ? "Phiên đã hết hạn, đang đăng nhập lại…" : "Phiên đã hết hạn, hãy đăng nhập lại")
        openLogin(auto: true)
    }

    /// Mở app: khôi phục cookie xong thì kiểm tra phiên rồi mới nạp trang (đăng nhập lại nếu cần).
    func startLoad(_ webView: WKWebView) {
        let start = URL(string: address) ?? URL(string: BrowserModel.homeURL)!
        guard BrowserModel.autoReconnect else { webView.load(URLRequest(url: start, timeoutInterval: 45)); return }
        // Lâu không dùng + đã lưu tài khoản (đăng nhập lại êm) -> khỏi thăm dò, đăng nhập lại luôn.
        // Chưa lưu tài khoản thì chỉ dựa vào thăm dò để không bắt người dùng gõ lại khi phiên vẫn còn.
        if let age = lastActiveAge, age > BrowserModel.staleSessionAge, CredStore.enabled, CredStore.load() != nil {
            DispatchQueue.main.async { self.openLogin(auto: true) }
            return
        }
        probeSession { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .none: self.openLogin(auto: true)          // chưa có phiên: vào thẳng trang đăng nhập (tự điền nếu có tài khoản)
                case .expired: self.reconnecting = true; self.reconnectTimes.append(Date()); self.lastReconnectAt = Date(); self.showToast("Phiên đã hết hạn, đang đăng nhập lại…"); self.openLogin(auto: true)
                case .valid, .unknown: webView.load(URLRequest(url: start, timeoutInterval: 45))
                }
            }
        }
    }

    /// App quay lại từ nền: nếu đã nằm nền lâu thì kiểm tra phiên (không làm gì khi đang ở trang đăng nhập).
    func appBecameActive() {
        guard BrowserModel.autoReconnect, let t = backgroundedAt else { return }
        backgroundedAt = nil
        guard Date().timeIntervalSince(t) > 600, inDesm else { return }
        probeSession { [weak self] result in
            DispatchQueue.main.async { if result == .expired || result == .none { self?.reconnectSession(reason: "foreground") } }
        }
    }
}
