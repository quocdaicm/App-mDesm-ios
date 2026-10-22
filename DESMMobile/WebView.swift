import SwiftUI
import WebKit

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
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        model.webView = webView
        model.contentController = content
        model.installUserScript()

        if let url = URL(string: model.address) {
            webView.load(URLRequest(url: url, timeoutInterval: 45))
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
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
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
                self.model.evaluateNow()
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

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
