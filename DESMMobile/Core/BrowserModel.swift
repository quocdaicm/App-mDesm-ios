// BrowserModel.swift — trạng thái trung tâm của app (địa chỉ, cài đặt @AppStorage, tham chiếu WKWebView). Script tiêm: Scripts/; phiên: Session/.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

/// Trạng thái trung tâm: địa chỉ, tiến trình, chế độ hiển thị, cài đặt (CSS bổ sung, từ điển, Việt hoá), tham chiếu tới
/// WKWebView/WKUserContentController. Tạo script tiêm (makeScript) và cài vào trang (installUserScript/evaluateNow).
final class BrowserModel: ObservableObject {
    static let homeURL = "https://desm.doosanenerbility.com/main.do?lang=en"
    /// Chỉ áp dụng giao diện cho các domain này khi bật "Chỉ áp dụng cho DESM".
    static let allowedHosts = ["doosanenerbility.com"]

    @Published var address = BrowserModel.homeURL
    @Published var pageTitle = "DESM Mobile"
    @Published var isLoading = false
    /// Màn khởi động (LaunchSplash): trang DESM đã dựng xong màn Package (tín hiệu `desmReady` từ JS) / đã tải xong lần đầu
    @Published var splashReady = false
    @Published var firstLoadDone = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var showSettings = false
    @Published var shotItem: ShareItem?      // ảnh chụp toàn trang chờ chia sẻ/lưu
    @Published var errorMessage: String?
    @Published var toast: String?
    /// Phiếu RSI vừa quét (QR/chữ) đang chờ tab Xuất kho mở đúng phiếu đó
    @Published var pendingRsiScan: QRRsi?
    /// Hàng đợi hộp thoại tự vẽ (alert/confirm của trang, hỏi lưu tài khoản...): hiện cái đầu tiên ở đáy màn hình.
    @Published var dialogQueue: [DesmDialogState] = []
    func presentDialog(_ s: DesmDialogState) { dialogQueue.append(s) }
    func finishDialog() { if !dialogQueue.isEmpty { dialogQueue.removeFirst() } }
    /// Ẩn thanh trên + thanh dưới (tự ẩn khi vào được trang DESM, bấm nút nổi để hiện lại)
    @Published var barsHidden = false
    var wasInDesm = false
    // Tự kết nối lại khi hết phiên đăng nhập (xem extension "Tự kết nối lại" bên dưới)
    var reconnecting = false          // đang trong quá trình đăng nhập lại tự động
    var autoSubmitCount = 0           // số lần tự bấm Login trong lần kết nối lại này
    var reconnectTimes: [Date] = []   // các lần kết nối lại gần đây (chặn lặp vô hạn)
    var lastReconnectAt: Date?
    var backgroundedAt: Date?         // lúc app xuống nền
    /// Đang ở trong DESM (không phải trang đăng nhập): dùng để hiện nút quét camera
    @Published var inDesm = false
    /// Số thông báo DESM chưa mở (hiện chấm đỏ trên nút "Thêm" và số trên icon app).
    @Published var unreadNotices = 0

    /// Gọi sau mỗi lần tải xong trang: vừa vào được DESM (không phải trang đăng nhập) thì tự ẩn thanh; rời DESM thì hiện lại.
    func updateBars(for url: URL?) {
        let host = url?.host?.lowercased() ?? ""
        let path = url?.path.lowercased() ?? ""
        let inDesm = BrowserModel.allowedHosts.contains { host == $0 || host.hasSuffix("." + $0) } && !path.contains("login")
        if inDesm && !wasInDesm { withAnimation(.easeInOut(duration: 0.2)) { barsHidden = true } }
        if !inDesm && barsHidden { withAnimation(.easeInOut(duration: 0.2)) { barsHidden = false } }
        if self.inDesm != inDesm { self.inDesm = inDesm }
        wasInDesm = inDesm
    }

    @Published var layoutMode: LayoutMode {
        didSet { UserDefaults.standard.set(layoutMode.rawValue, forKey: "desmLayoutMode") }
    }
    @Published var fitWidth: Int {
        didSet { UserDefaults.standard.set(fitWidth, forKey: "desmFitWidth") }
    }
    @Published var scopeOnly: Bool {
        didSet { UserDefaults.standard.set(scopeOnly, forKey: "desmScopeOnly") }
    }
    @Published var compactHeader: Bool {
        didSet { UserDefaults.standard.set(compactHeader, forKey: "desmCompactHeader") }
    }
    @AppStorage("desmCustomCSS") var customCSS = ""
    @AppStorage("desmCustomDict") var customDict = ""
    /// Nút bong bóng chat Dodo (trợ lý AI của DESM) — xem Scripts/DodoBubble.swift
    @AppStorage("desmDodoBubble") var dodoBubble = true
    /// Gắn thêm yêu cầu "trả lời bằng tiếng Việt" vào câu hỏi gửi Dodo
    @AppStorage("desmDodoVi") var dodoVi = true
    @AppStorage("desmDodoSlow") var dodoSlow = false
    /// Gửi kèm dữ liệu kiện đang hiển thị (màn Package) trong câu hỏi gửi Dodo
    @AppStorage("desmDodoData") var dodoData = true
    /// Tự tra dữ liệu DESM (chỉ đọc) theo số kiện trong câu hỏi rồi gửi kèm Dodo
    @AppStorage("desmDodoAuto") var dodoAuto = true
    /// Chạm bong bóng mở: "ai" (AI riêng, xem AI/ — MẶC ĐỊNH từ 2026-10-31) hoặc "dodo" (Dodo của DESM)
    @AppStorage("desmAIEngine") var aiEngine = "ai"
    @Published var showAIChat = false
    /// Vào app / đăng nhập xong thì tự mở màn Package (Kiện hàng) làm màn hình chính
    @AppStorage("desmOpenPackage") var openPackageOnStart = true
    var pendingHomeTab = true
    /// Dịch giao diện web DESM sang tiếng Việt (lớp dịch phía app, không đổi ngôn ngữ phía máy chủ)
    @Published var viLang: Bool {
        didSet { UserDefaults.standard.set(viLang, forKey: "desmViLang") }
    }

    weak var webView: WKWebView?
    weak var contentController: WKUserContentController?

    init() {
        let ud = UserDefaults.standard
        layoutMode = LayoutMode(rawValue: ud.string(forKey: "desmLayoutMode") ?? "") ?? .mobile
        let w = ud.integer(forKey: "desmFitWidth")
        fitWidth = w == 0 ? 1280 : w
        scopeOnly = ud.object(forKey: "desmScopeOnly") as? Bool ?? true
        compactHeader = ud.object(forKey: "desmCompactHeader") as? Bool ?? true
        viLang = ud.object(forKey: "desmViLang") as? Bool ?? false
    }

    /// Bật/tắt tiếng Việt. fromPage = true khi người dùng chọn trong ô Language của trang (trang tự tải lại theo ngôn ngữ máy chủ).
    func setVietnamese(_ on: Bool, fromPage: Bool = false) {
        guard viLang != on else { return }
        viLang = on
        applyStyles()
        if !on && !fromPage { webView?.reload() }   // tắt dịch: tải lại để trả về chữ gốc
    }

    var customPairs: [[String]] {
        customDict.split(whereSeparator: \.isNewline).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { return nil }
            guard let i = t.firstIndex(of: "=") else { return nil }
            let k = t[..<i].trimmingCharacters(in: .whitespaces)
            let v = t[t.index(after: i)...].trimmingCharacters(in: .whitespaces)
            return (k.isEmpty || v.isEmpty) ? nil : [k, v]
        }
    }

    func loadAddress() {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { errorMessage = "Vui lòng nhập địa chỉ website."; return }
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = url.host, host.contains(".") else {
            errorMessage = "Địa chỉ không hợp lệ. Hãy nhập URL dạng https://example.com"
            return
        }
        address = url.absoluteString
        webView?.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45))
    }

    func navigate(_ url: URL) {
        address = url.absoluteString
        webView?.load(URLRequest(url: url, timeoutInterval: 45))
    }
    func reload() { webView?.reload() }
    func goBack() {
        webView?.evaluateJavaScript("window.__desmBack ? window.__desmBack() : 0;") { [weak self] r, _ in
            if (r as? Int ?? 0) == 1 { return }
            if self?.webView?.canGoBack == true { self?.webView?.goBack() }
        }
    }
    func goForward() { if webView?.canGoForward == true { webView?.goForward() } }
    func home() {
        address = BrowserModel.homeURL
        loadAddress()
    }

    func setMode(_ mode: LayoutMode) {
        let old = layoutMode
        layoutMode = mode
        applyStyles()
        if old == .mobile && mode != .mobile {
            webView?.evaluateJavaScript("window.__desmRevert && window.__desmRevert();", completionHandler: nil)
        }
    }

    func cycleMode() {
        setMode(layoutMode.next)
        showToast(layoutMode.title)
    }

    /// Footer 5 tab: mở mục menu DESM tương ứng; không tìm thấy thì mở ngăn kéo menu để người dùng tự chọn.
    func openDesmTab(_ tab: DesmTab) {
        func q(_ v: String?) -> String { v.map { "'\($0)'" } ?? "null" }
        let js = "window.__desmOpenMenu ? window.__desmOpenMenu(\(q(tab.menuId)), '\(tab.pattern)') : 0;"
        webView?.evaluateJavaScript(js) { [weak self] r, _ in
            if (r as? Int ?? 0) == 0 {
                self?.webView?.evaluateJavaScript("window.__desmToggleDrawer && window.__desmToggleDrawer();", completionHandler: nil)
                self?.showToast("Chọn mục “\(tab.title)” trong menu")
            }
        }
    }

    /// Mở một mục menu DESM theo tên (không có id đã biết). Không tìm thấy thì mở ngăn kéo menu để người dùng tự chọn.
    func openDesmMenu(id: String? = nil, title: String, pattern: String) {
        let idArg = id.map { "'\($0)'" } ?? "null"
        let js = "window.__desmOpenMenu ? window.__desmOpenMenu(\(idArg), '\(pattern)') : 0;"
        webView?.evaluateJavaScript(js) { [weak self] r, _ in
            if (r as? Int ?? 0) == 0 {
                self?.webView?.evaluateJavaScript("window.__desmToggleDrawer && window.__desmToggleDrawer();", completionHandler: nil)
                self?.showToast("Chọn mục “\(title)” trong menu")
            }
        }
    }

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }

    /// Cài script chạy ở document start cho mọi frame của các lần tải trang sau.
    func installUserScript() {
        guard let controller = contentController else { return }
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: makeScript(),
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: BrowserModel.netRecorderSource,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: BrowserModel.snapRecorderSource,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: makeDodoScript(),
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
    }

    /// Áp ngay lên trang đang mở.
    func evaluateNow() {
        webView?.evaluateJavaScript(makeScript(), completionHandler: nil)
        webView?.evaluateJavaScript(makeDodoScript(), completionHandler: nil)
    }

    func applyStyles() {
        installUserScript()
        evaluateNow()
    }

    /// Chép danh sách chuỗi tiếng Anh trên trang chưa có trong từ điển (dạng "English = ") để bổ sung bản dịch.
    func copyMissingStrings(_ done: @escaping (String) -> Void) {
        guard let webView = webView else { done("Chưa có trang để đọc."); return }
        let js = "(function(){var m=window.__desmMiss||{};return Object.keys(m).sort().map(function(k){return k+' = ';}).join('\\n');})();"
        webView.evaluateJavaScript(js) { result, _ in
            if let text = result as? String, !text.isEmpty {
                UIPasteboard.general.string = text
                done("Đã sao chép \(text.split(separator: "\n").count) chuỗi chưa dịch. Dán vào khung chat, hoặc điền bản dịch sau dấu = rồi dán vào ô \"Từ điển bổ sung\".")
            } else {
                done("Chưa phát hiện chuỗi nào cần dịch. Hãy bật tiếng Việt và mở màn hình cần kiểm tra trước.")
            }
        }
    }
}
