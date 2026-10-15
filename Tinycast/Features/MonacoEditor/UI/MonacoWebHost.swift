import AppKit
import SwiftUI
import WebKit

/// The locked-down web view: bundled page only, no network, no navigation, no new windows.
@MainActor
final class MonacoWebHost: NSObject, WKNavigationDelegate, WKUIDelegate {
    struct Options {
        var text: String
        var language: String
        var isDark: Bool
        var fontFamily: String
        var fontSize: Double
    }

    struct Snapshot {
        let text: String
        let version: Int
    }

    let webView: WKWebView
    var onMessage: ((MonacoBridgeMessage) -> Void)?
    private var pageURL: URL?
    private var pending: Options?

    /// Hands the message handler a weak reference, since the user content controller retains it.
    private final class Proxy: NSObject, WKScriptMessageHandler {
        weak var host: MonacoWebHost?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage)
        {
            let body = message.body
            MainActor.assumeIsolated { host?.receive(body) }
        }
    }

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let proxy = Proxy()
        configuration.userContentController.add(proxy, name: "tinycast")
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        proxy.host = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
    }

    isolated deinit {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    /// The editor opens once the bundled page has loaded, so options can arrive before the page is ready.
    func open(_ options: Options) {
        pending = options
        guard pageURL == nil else { return }
        guard
            let page = Bundle.main.url(
                forResource: "index", withExtension: "html", subdirectory: "MonacoEditor")
        else {
            onMessage?(.close)
            return
        }
        pageURL = page
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func snapshot() async -> Snapshot? {
        let result = try? await webView.callAsyncJavaScript(
            "return window.tinycastEditor.snapshot()", contentWorld: .page)
        guard let object = result as? [String: Any], let text = object["text"] as? String,
            let version = (object["version"] as? NSNumber)?.intValue
        else { return nil }
        return Snapshot(text: text, version: version)
    }

    func markSaved(version: Int) {
        call("window.tinycastEditor.markSaved(version)", ["version": version])
    }

    func setTheme(isDark: Bool) {
        call("window.tinycastEditor.setTheme(theme)", ["theme": Self.theme(isDark: isDark)])
    }

    func setFont(family: String, size: Double) {
        call("window.tinycastEditor.setFont(family, size)", ["family": family, "size": size])
    }

    func focus() {
        call("window.tinycastEditor.focus()", [:])
    }

    static func theme(isDark: Bool) -> String { isDark ? "vs-dark" : "vs" }

    private func call(_ script: String, _ arguments: [String: Any]) {
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { _ in }
    }

    fileprivate func receive(_ body: Any) {
        guard let message = MonacoBridgeMessage(body: body) else { return }
        onMessage?(message)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard let options = pending else { return }
        pending = nil
        let arguments: [String: Any] = [
            "options": [
                "text": options.text, "language": options.language,
                "theme": Self.theme(isDark: options.isDark),
                "fontFamily": options.fontFamily, "fontSize": options.fontSize
            ]
        ]
        call("window.tinycastEditor.open(options)", arguments)
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(navigationAction.request.url == pageURL ? .allow : .cancel)
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? { nil }
}

struct MonacoWebView: NSViewRepresentable {
    let host: MonacoWebHost

    func makeNSView(context: Context) -> WKWebView { host.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
