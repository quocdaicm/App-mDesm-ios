import SwiftUI
import WebKit

final class BrowserModel: ObservableObject {
    @Published var address = "https://desm.doosanenerbility.com/main.do?lang=en"
    @Published var pageTitle = "DESM Mobile"
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var showSettings = false
    @Published var errorMessage: String?
    @AppStorage("desmMobileMode") var mobileMode = true
    @AppStorage("desmScopeOnly") var scopeOnly = true
    @AppStorage("desmCustomCSS") var customCSS = ""

    weak var webView: WKWebView?
    weak var contentController: WKUserContentController?

    /// Chỉ áp dụng CSS cho các domain này khi bật "Chỉ áp dụng cho DESM".
    static let allowedHosts = ["doosanenerbility.com"]

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
    func goBack() { if webView?.canGoBack == true { webView?.goBack() } }
    func goForward() { if webView?.canGoForward == true { webView?.goForward() } }
    func home() {
        address = "https://desm.doosanenerbility.com/main.do?lang=en"
        loadAddress()
    }
    func toggleMobileMode() {
        mobileMode.toggle()
        applyStyles()
    }

    /// Sinh đoạn JS (idempotent) áp/gỡ CSS cho tài liệu hiện tại, iframe cùng origin,
    /// và tự áp lại nếu trang xóa style/class/viewport.
    private func makeScript() -> String {
        let config: [String: Any] = [
            "enabled": mobileMode,
            "scope": scopeOnly,
            "hosts": BrowserModel.allowedHosts,
            "css": MobileStyles.css + "\n" + customCSS
        ]
        let json = (try? JSONSerialization.data(withJSONObject: config, options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"enabled\":false}"
        return """
        (function() {
          var w = window;
          w.__desmCfg = \(json);
          var ID = 'desm-mobile-custom-style', CLS = 'desm-mobile-mode';
          var VP = 'width=device-width, initial-scale=1, viewport-fit=cover';

          function allowed(doc) {
            var c = w.__desmCfg;
            if (!c.scope) return true;
            var h = '';
            try {
              h = (doc.location.hostname || '').toLowerCase();
              if (!h && w.parent !== w) h = (w.parent.location.hostname || '').toLowerCase();
            } catch (e) {}
            return c.hosts.some(function(s) { return h === s || h.endsWith('.' + s); });
          }
          function setViewport(doc, on) {
            var head = doc.head; if (!head) return;
            var m = doc.querySelector('meta[name="viewport"]');
            if (on) {
              if (!m) {
                m = doc.createElement('meta'); m.name = 'viewport';
                m.setAttribute('data-desm', '1'); m.content = VP; head.appendChild(m);
              } else if (m.content !== VP) {
                if (!m.hasAttribute('data-desm-orig')) m.setAttribute('data-desm-orig', m.content);
                m.content = VP;
              }
            } else if (m) {
              if (m.getAttribute('data-desm') === '1') { m.remove(); }
              else if (m.hasAttribute('data-desm-orig')) {
                m.content = m.getAttribute('data-desm-orig'); m.removeAttribute('data-desm-orig');
              }
            }
          }
          function apply(doc) {
            var root = doc.documentElement; if (!root) return;
            var c = w.__desmCfg;
            var on = c.enabled && allowed(doc);
            var style = doc.getElementById(ID);
            if (on) {
              if (!style) {
                style = doc.createElement('style'); style.id = ID; style.textContent = c.css;
                root.appendChild(style);
              } else if (style.textContent !== c.css) { style.textContent = c.css; }
              if (!root.classList.contains(CLS)) root.classList.add(CLS);
            } else {
              if (style) style.remove();
              if (root.classList.contains(CLS)) root.classList.remove(CLS);
            }
            if (doc === document && w === w.top) setViewport(doc, on);
          }
          function applyAll(doc) {
            apply(doc);
            var fs = doc.querySelectorAll('iframe,frame');
            for (var i = 0; i < fs.length; i++) {
              try { var d = fs[i].contentDocument; if (d) applyAll(d); } catch (e) {}
            }
          }
          w.__desmApplyAll = function() { applyAll(document); };
          w.__desmApplyAll();

          if (!w.__desmInit) {
            w.__desmInit = true;
            var reapply = function() { apply(document); };
            try {
              new MutationObserver(reapply).observe(document.documentElement,
                { attributes: true, attributeFilter: ['class'], childList: true });
            } catch (e) {}
            // Tab/nội dung nạp động (iframe tạo sau khi trang tải xong): theo dõi và áp CSS khi iframe load.
            var watch = function(f) {
              if (f.__desmW) return; f.__desmW = 1;
              f.addEventListener('load', function() { try { if (f.contentDocument) applyAll(f.contentDocument); } catch (e) {} });
              try { if (f.contentDocument && f.contentDocument.readyState !== 'loading') applyAll(f.contentDocument); } catch (e) {}
            };
            var scan = function() {
              var fs = document.querySelectorAll('iframe,frame');
              for (var i = 0; i < fs.length; i++) watch(fs[i]);
            };
            var queued = false;
            var schedule = function() {
              if (queued) return; queued = true;
              (w.requestAnimationFrame || w.setTimeout)(function() { queued = false; scan(); });
            };
            try {
              new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
            } catch (e) {}
            document.addEventListener('DOMContentLoaded', scan);
            document.addEventListener('DOMContentLoaded', function() {
              applyAll(document);
              if (document.head) {
                try { new MutationObserver(function() { setViewport(document, w.__desmCfg.enabled && allowed(document)); })
                  .observe(document.head, { childList: true }); } catch (e) {}
              }
            });
          }
        })();
        """
    }

    /// Cài script chạy ở document start cho mọi frame của các lần tải trang sau (không bị nháy giao diện gốc).
    func installUserScript() {
        guard let controller = contentController else { return }
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: makeScript(),
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
    }

    /// Áp ngay lên trang đang mở.
    func evaluateNow() {
        webView?.evaluateJavaScript(makeScript(), completionHandler: nil)
    }

    func applyStyles() {
        installUserScript()
        evaluateNow()
    }
}

struct BrowserView: View {
    @StateObject private var model = BrowserModel()
    @State private var showAddressEntry = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.isLoading {
                ProgressView(value: model.progress).tint(.blue).frame(height: 3)
            } else {
                Rectangle().fill(Color(.separator).opacity(0.5)).frame(height: 0.5)
            }
            WebView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .background(Color(.systemGroupedBackground))
        .tint(.blue)
        .alert("Không mở được địa chỉ", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Đóng", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text("DESM Mobile").font(.system(size: 16, weight: .bold))
                    Text(model.pageTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 3)
                Button { model.toggleMobileMode() } label: {
                    Image(systemName: model.mobileMode ? "iphone.gen3" : "desktopcomputer")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(model.mobileMode ? Color.blue.opacity(0.12) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11))
                }
                .accessibilityLabel(model.mobileMode ? "Tắt CSS mobile" : "Bật CSS mobile")
                Button { model.showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11))
                }
                .accessibilityLabel("Cài đặt giao diện")
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                TextField("Nhập địa chỉ website…", text: $model.address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { model.loadAddress() }
                    .font(.system(size: 14))
                Button { model.loadAddress() } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel("Mở địa chỉ")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
        .background(Color(.systemBackground))
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            navButton("chevron.left", title: "Quay lại", enabled: model.canGoBack) { model.goBack() }
            navButton("chevron.right", title: "Tiến", enabled: model.canGoForward) { model.goForward() }
            navButton("house.fill", title: "DESM", enabled: true) { model.home() }
            navButton("arrow.clockwise", title: "Tải lại", enabled: true) { model.reload() }
            navButton("safari", title: "Safari", enabled: true) {
                if let url = model.webView?.url { UIApplication.shared.open(url) }
            }
        }
        .padding(.top, 9).padding(.bottom, 5)
        .background(.ultraThinMaterial)
    }

    private func navButton(_ symbol: String, title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(enabled ? Color.blue : Color.gray.opacity(0.4))
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .disabled(!enabled)
    }
}

struct SettingsView: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Giao diện") {
                    Toggle("Tự động tối ưu mobile", isOn: Binding(
                        get: { model.mobileMode },
                        set: { model.mobileMode = $0; model.applyStyles() }
                    ))
                    Toggle("Chỉ áp dụng cho DESM", isOn: Binding(
                        get: { model.scopeOnly },
                        set: { model.scopeOnly = $0; model.applyStyles() }
                    ))
                    Text("CSS được tiêm ngay khi trang bắt đầu tải (cả iframe) và áp lại sau mỗi lần điều hướng. Khi bật \"Chỉ áp dụng cho DESM\", các website khác giữ nguyên giao diện gốc.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("CSS bổ sung") {
                    TextEditor(text: $model.customCSS)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 160)
                    Button("Áp dụng CSS") { model.applyStyles(); dismiss() }
                    Button("Xóa CSS bổ sung", role: .destructive) {
                        model.customCSS = ""
                        model.applyStyles()
                    }
                }
                Section {
                    Text("CSS bổ sung lưu trên thiết bị. Chỉ thay đổi cách hiển thị, không sửa chức năng nghiệp vụ hoặc vượt qua đăng nhập.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cài đặt giao diện")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Xong") { model.applyStyles(); dismiss() } } }
        }
    }
}
