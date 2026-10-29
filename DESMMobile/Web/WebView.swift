// WebView.swift — WKWebView bọc trang DESM.
//  - SessionStore: lưu/khôi phục cookie phiên vào Keychain để mở app vẫn còn đăng nhập.
//  - CredStore: tài khoản tự điền ở trang đăng nhập (Keychain, chỉ lưu khi người dùng đồng ý).
//  - WebView + Coordinator: điều hướng, alert/confirm/prompt thật (WKWebView mặc định không hiện), nhận message từ JS
//    (desmCred, desmLang, desmScanResult), tự điền tài khoản. Chỉ cho phép http/https/about.
// Xem DEV_NOTES.md.
import SwiftUI
import WebKit
import Security

// MARK: - Lưu/khôi phục phiên đăng nhập

/// Cookie phiên (session cookie) của WKWebView bị xóa khi app bị tắt hẳn. Lớp này lưu cookie của DESM vào Keychain
/// và nạp lại trước khi tải trang, để lần sau mở app vẫn còn đăng nhập (miễn là phiên phía máy chủ chưa hết hạn).
enum SessionStore {
    private static let account = "desm.session.cookies"
    private static let service = "DESMMobile"
    private static let domainKey = "doosanenerbility.com"
    private static let sessionLifetime: TimeInterval = 30 * 24 * 3600

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "desmRememberLogin") as? Bool ?? true
    }

    static func save(from store: WKHTTPCookieStore) {
        guard enabled else { return }
        store.getAllCookies { cookies in
            let mine = cookies.filter { $0.domain.lowercased().contains(domainKey) }
            if mine.isEmpty { clear(); return }   // đã đăng xuất -> xóa bản lưu cũ
            let list: [[String: Any]] = mine.map { c in
                var d: [String: Any] = [
                    "name": c.name, "value": c.value, "domain": c.domain, "path": c.path,
                    "secure": c.isSecure, "httpOnly": c.isHTTPOnly
                ]
                if let e = c.expiresDate { d["expires"] = e }
                if let s = c.sameSitePolicy?.rawValue { d["sameSite"] = s }
                return d
            }
            guard let data = try? PropertyListSerialization.data(fromPropertyList: list, format: .binary, options: 0) else { return }
            keychainSet(data)
        }
    }

    /// Cookie DESM đã lưu trong Keychain, dạng HTTPCookie (bỏ cookie đã hết hạn). Không cần WebView -> dùng được cho việc chạy nền.
    static func storedCookies() -> [HTTPCookie] {
        guard enabled, let data = keychainGet(),
              let any = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let list = any as? [[String: Any]], !list.isEmpty else { return [] }
        let now = Date()
        var out: [HTTPCookie] = []
        for d in list {
            guard let name = d["name"] as? String, let value = d["value"] as? String,
                  let domain = d["domain"] as? String else { continue }
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain,
                .path: (d["path"] as? String) ?? "/"
            ]
            if let e = d["expires"] as? Date {
                if e < now { continue }          // cookie đã hết hạn thật
                props[.expires] = e
            } else {
                props[.expires] = now.addingTimeInterval(sessionLifetime)   // cookie phiên -> giữ qua lần mở sau
            }
            if (d["secure"] as? Bool) == true { props[.secure] = "TRUE" }
            if (d["httpOnly"] as? Bool) == true { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let s = d["sameSite"] as? String { props[HTTPCookiePropertyKey("SameSite")] = s }
            if let cookie = HTTPCookie(properties: props) { out.append(cookie) }
        }
        return out
    }

    static func restore(into store: WKHTTPCookieStore, completion: @escaping () -> Void) {
        let cookies = storedCookies()
        if cookies.isEmpty { completion(); return }
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            DispatchQueue.main.async { store.setCookie(cookie) { group.leave() } }
        }
        group.notify(queue: .main) { completion() }
    }

    static func clear() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }

    private static func keychainSet(_ data: Data) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(q as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = q; attrs.forEach { add[$0.key] = $0.value }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func keychainGet() -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
}


// MARK: - Tài khoản tự điền (lưu trong Keychain, chỉ lưu khi người dùng đồng ý)

enum CredStore {
    private static let account = "desm.login.credentials"
    private static let service = "DESMMobile"

    static var enabled: Bool { UserDefaults.standard.object(forKey: "desmAutofill") as? Bool ?? true }

    static func load() -> (user: String, pass: String)? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let u = d["u"], let p = d["p"], !u.isEmpty, !p.isEmpty else { return nil }
        return (u, p)
    }

    static func save(user: String, pass: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["u": user, "p": pass]) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        if SecItemUpdate(q as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = q; attrs.forEach { add[$0.key] = $0.value }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func clear() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

extension BrowserModel {
    func saveSession() {
        guard let wv = webView else { return }
        SessionStore.save(from: wv.configuration.websiteDataStore.httpCookieStore)
    }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var model: BrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // Vuốt từ mép trái = quay lại, từ mép phải = tiến (tự xử lý để chạy ổn định cả với trang nhiều khung/iframe của DESM).
        // Tắt cử chỉ có sẵn của WKWebView để không bị chuyển trang hai lần. Bật/tắt: Cài đặt > Hiển thị (desmEdgeSwipe).
        webView.allowsBackForwardNavigationGestures = false
        for edge in [UIRectEdge.left, UIRectEdge.right] {
            let g = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.edgeSwipe(_:)))
            g.edges = edge
            webView.addGestureRecognizer(g)
            webView.scrollView.panGestureRecognizer.require(toFail: g)
        }
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        content.add(context.coordinator, name: "desmCred")
        content.add(context.coordinator, name: "desmLang")
        content.add(context.coordinator, name: "desmScanResult")
        content.add(context.coordinator, name: "desmSession")
        content.add(context.coordinator, name: "desmNet")
        content.add(context.coordinator, name: "desmSnap")
        content.add(context.coordinator, name: "desmAudit")
        model.webView = webView
        model.contentController = content
        model.installUserScript()

        // Nạp lại cookie đăng nhập đã lưu rồi mới tải trang (còn phiên -> vào thẳng, hết phiên -> trang đăng nhập)
        // Sau đó kiểm tra phiên còn dùng được không; hết phiên thì mở login.do và tự đăng nhập lại (BrowserModel.startLoad)
        SessionStore.restore(into: config.websiteDataStore.httpCookieStore) {
            model.startLoad(webView)
        }
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoForward), options: .new, context: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.removeObserver(coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress))
        uiView.removeObserver(coordinator, forKeyPath: #keyPath(WKWebView.canGoBack))
        uiView.removeObserver(coordinator, forKeyPath: #keyPath(WKWebView.canGoForward))
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "desmCred")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "desmLang")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "desmScanResult")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "desmSession")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "desmNet")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "desmSnap")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "desmAudit")
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        @objc func edgeSwipe(_ g: UIScreenEdgePanGestureRecognizer) {
            guard g.state == .ended, BrowserModel.edgeSwipe, let wv = model.webView else { return }
            let dx = g.translation(in: wv).x, vx = g.velocity(in: wv).x
            if g.edges == .left, dx > 60 || vx > 500 {
                // Đang mở màn hình chi tiết kiện / cập nhật vị trí / ngăn kéo menu (lớp phủ trong trang): vuốt = đóng lớp phủ trước
                wv.evaluateJavaScript("window.__desmBack ? window.__desmBack() : 0;") { [weak self] r, _ in
                    guard let self = self else { return }
                    if (r as? Int ?? 0) == 1 { return }
                    if wv.canGoBack { wv.goBack() } else if !self.model.inDesm { self.model.showToast("Không còn trang trước") }
                }
            } else if g.edges == .right, dx < -60 || vx < -500 {
                if wv.canGoForward { wv.goForward() } else { model.showToast("Không còn trang sau") }
            }
        }

        private let model: BrowserModel
        init(model: BrowserModel) { self.model = model }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            guard let webView = object as? WKWebView else { return }
            DispatchQueue.main.async {
                self.model.progress = webView.estimatedProgress
                self.model.isLoading = webView.isLoading
                self.model.canGoBack = webView.canGoBack
                self.model.canGoForward = webView.canGoForward
            }
        }


        // Nhận tài khoản từ trang đăng nhập (khi bấm Login) và hỏi người dùng có muốn lưu để tự điền không.
        private var askedKeys = Set<String>()
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "desmScanResult" {
                guard let host = message.frameInfo.request.url?.host?.lowercased(),
                      host == "doosanenerbility.com" || host.hasSuffix(".doosanenerbility.com"),
                      let d = message.body as? [String: Any], let st = d["status"] as? String else { return }
                let term = (d["term"] as? String) ?? ""
                let n = (d["n"] as? Int) ?? 0
                DispatchQueue.main.async {
                    switch st {
                    case "nopage": self.model.showToast("Không mở được màn hình Package, hãy vào Kiện hàng rồi quét lại")
                    case "notfound": self.model.showToast("Không tìm thấy kiện \(term)")
                    case "multi": self.model.showToast("\(n) kiện khớp, chạm để chọn kiện")
                    case "ok": self.model.showToast("Đã chọn kiện \(term)")
                    case "plsearch": self.model.showToast(n > 0 ? "\(n) kiện thuộc \(term), chạm để chọn" : "Các kiện của \(term)")
                    case "plempty": self.model.showToast("Không có kiện nào thuộc \(term)")
                    case "dfound": self.model.showToast("Hạng mục thuộc kiện \(term)")
                    case "dnotfound": self.model.showToast("Không tìm thấy hạng mục \(term)")
                    case "dmulti": self.model.showToast("Mã \(term) có \(n) kiện khớp, hãy tra tay ở Hạng mục chi tiết")
                    default: break
                    }
                }
                return
            }
            if message.name == "desmNet" {
                // Nhật ký API: trang gửi từng request/phản hồi, app ghi vào file trong máy (chỉ khi người dùng bật ghi)
                guard let host = message.frameInfo.request.url?.host?.lowercased(),
                      host == "doosanenerbility.com" || host.hasSuffix(".doosanenerbility.com"),
                      let d = message.body as? [String: Any] else { return }
                NetLogStore.append(d)
                return
            }
            if message.name == "desmAudit" {
                // Nhật ký thao tác ghi: JS trong trang báo trước/sau khi gửi lệnh lưu (xem WriteAudit.swift)
                guard let host = message.frameInfo.request.url?.host?.lowercased(),
                      host == "doosanenerbility.com" || host.hasSuffix(".doosanenerbility.com"),
                      let d = message.body as? [String: Any] else { return }
                WriteAuditStore.handle(d)
                return
            }
            if message.name == "desmSnap" {
                // Lưu cấu trúc/HTML/CSS từng màn hình (chỉ khi người dùng bật "Tự lưu từng màn hình")
                guard let host = message.frameInfo.request.url?.host?.lowercased(),
                      host == "doosanenerbility.com" || host.hasSuffix(".doosanenerbility.com"),
                      let d = message.body as? [String: Any] else { return }
                SnapStore.save(d)
                return
            }
            if message.name == "desmSession" {
                // Trang báo phiên đã hết hạn (XHR bị đẩy về login / 401 / HTML đăng nhập)
                guard let host = message.frameInfo.request.url?.host?.lowercased(),
                      host == "doosanenerbility.com" || host.hasSuffix(".doosanenerbility.com") else { return }
                DispatchQueue.main.async { if !self.model.reconnecting { self.model.reconnectSession(reason: "page") } }
                return
            }
            if message.name == "desmLang" {
                guard let host = message.frameInfo.request.url?.host?.lowercased(),
                      host == "doosanenerbility.com" || host.hasSuffix(".doosanenerbility.com"),
                      let d = message.body as? [String: Any], let lang = d["lang"] as? String else { return }
                DispatchQueue.main.async { self.model.setVietnamese(lang == "vi", fromPage: true) }
                return
            }
            guard message.name == "desmCred", CredStore.enabled,
                  let host = message.frameInfo.request.url?.host?.lowercased(),
                  host == "doosanenerbility.com" || host.hasSuffix(".doosanenerbility.com"),
                  let d = message.body as? [String: Any],
                  let u = d["u"] as? String, let p = d["p"] as? String, !u.isEmpty, !p.isEmpty else { return }
            if let old = CredStore.load(), old.user == u, old.pass == p { return }
            let key = u + "\u{1}" + p
            if askedKeys.contains(key) { return }
            askedKeys.insert(key)
            DispatchQueue.main.async {
                if self.useOverlayDialog() {
                    self.model.presentDialog(DesmDialogState(
                        icon: "key.fill", title: "Lưu tài khoản?",
                        message: "Lưu tài khoản \"\(u)\" trên máy này (Keychain) để tự điền ở lần đăng nhập sau?",
                        actions: [DesmDialogAction(title: "Lưu", kind: .primary) { CredStore.save(user: u, pass: p) },
                                  DesmDialogAction(title: "Không", kind: .cancel)]))
                    return
                }
                guard let vc = self.topController() else { return }
                let a = UIAlertController(title: "Lưu tài khoản?",
                                          message: "Lưu tài khoản \"\(u)\" trên máy này (Keychain) để tự điền ở lần đăng nhập sau?",
                                          preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "Không", style: .cancel))
                a.addAction(UIAlertAction(title: "Lưu", style: .default) { _ in CredStore.save(user: u, pass: p) })
                vc.present(a, animated: true)
            }
        }

        /// Trang không phải login.do nhưng lại hiện ô mật khẩu (máy chủ trả trang đăng nhập thay vì quay về login.do) = hết phiên.
        private func checkLoginForm(_ webView: WKWebView) {
            guard BrowserModel.autoReconnect, !model.reconnecting, let url = webView.url, let host = url.host?.lowercased(),
                  host == "doosanenerbility.com" || host.hasSuffix(".doosanenerbility.com"),
                  !url.path.lowercased().contains("login") else { return }
            // Chỉ coi là trang đăng nhập khi có ĐÚNG MỘT ô mật khẩu đang hiển thị. main.do của DESM có sẵn ô mật khẩu ẩn / form đổi
            // mật khẩu (tài khoản ngoài @doosan.com) nên trước đây bị nhận nhầm là "hết phiên" ngay sau khi đăng nhập xong.
            let js = """
            (function(){
              var els = document.querySelectorAll('input[type=password]'), vis = 0;
              for (var i = 0; i < els.length; i++) {
                var e = els[i], r = e.getBoundingClientRect(), s = window.getComputedStyle(e);
                if (r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && e.offsetParent !== null) vis++;
              }
              return vis === 1;
            })()
            """
            webView.evaluateJavaScript(js) { r, _ in
                if (r as? Bool) == true { DispatchQueue.main.async { self.model.reconnectSession(reason: "loginform") } }
            }
        }

        private func autofillIfLogin(_ webView: WKWebView) {
            guard CredStore.enabled, let url = webView.url, let host = url.host?.lowercased(),
                  host == "doosanenerbility.com" || host.hasSuffix(".doosanenerbility.com"),
                  url.path.lowercased().contains("login"),
                  let c = CredStore.load(),
                  let ju = try? JSONSerialization.data(withJSONObject: [c.user], options: []),
                  let jp = try? JSONSerialization.data(withJSONObject: [c.pass], options: []),
                  let su = String(data: ju, encoding: .utf8), let sp = String(data: jp, encoding: .utf8) else { return }
            let js = "window.__desmFill && window.__desmFill(\(su)[0], \(sp)[0]);"
            for delay in [0.0, 0.7, 1.8] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { webView.evaluateJavaScript(js, completionHandler: nil) }
            }
            // Đang kết nối lại sau khi hết phiên: tự bấm Login (tối đa 2 lần mỗi lần kết nối lại để không lặp khi sai mật khẩu)
            if model.reconnecting, model.autoSubmitCount < 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    guard self.model.reconnecting else { return }
                    self.model.autoSubmitCount += 1
                    webView.evaluateJavaScript("window.__desmSubmitLogin && window.__desmSubmitLogin();", completionHandler: nil)
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.model.isLoading = true }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.model.isLoading = false
                self.model.canGoBack = webView.canGoBack
                self.model.canGoForward = webView.canGoForward
                self.model.address = webView.url?.absoluteString ?? self.model.address
                self.model.pageTitle = webView.title ?? "DESM Mobile"
                self.model.updateBars(for: webView.url)
                self.model.evaluateNow()
                self.model.saveSession()
                self.model.sessionDidLoad(webView.url)
                self.autofillIfLogin(webView)
                self.checkLoginForm(webView)
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.model.isLoading = false }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.model.isLoading = false }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased(),
                  ["https", "http", "about"].contains(scheme) else {
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }


        // WKWebView mặc định KHÔNG hiện alert/confirm/prompt của trang (confirm luôn trả về false,
        // làm các nút Lưu/Cập nhật vị trí âm thầm không chạy). Hiện hộp thoại thật để trang chạy đúng.
        private func topController() -> UIViewController? {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            var vc = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            while let p = vc?.presentedViewController { vc = p }
            return vc
        }
        /// Hộp thoại tự vẽ chỉ thấy được khi không có sheet/camera nào đang phủ lên; nếu có thì dùng alert hệ thống để trang không bị treo.
        func useOverlayDialog() -> Bool {
            let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            guard let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return false }
            return topController() === root
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            if useOverlayDialog() {
                model.presentDialog(DesmDialogState(icon: "info.circle.fill", title: "Thông báo", message: message,
                                                    actions: [DesmDialogAction(title: "OK", kind: .primary) { completionHandler() }]))
                return
            }
            guard let vc = topController() else { completionHandler(); return }
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            vc.present(a, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            if useOverlayDialog() {
                model.presentDialog(DesmDialogState(icon: "questionmark.circle.fill", title: "Xác nhận", message: message,
                                                    actions: [DesmDialogAction(title: "OK", kind: .primary) { completionHandler(true) },
                                                              DesmDialogAction(title: "Hủy", kind: .cancel) { completionHandler(false) }]))
                return
            }
            guard let vc = topController() else { completionHandler(false); return }
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Hủy", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            vc.present(a, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard let vc = topController() else { completionHandler(nil); return }
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: "Hủy", style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
            vc.present(a, animated: true)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
