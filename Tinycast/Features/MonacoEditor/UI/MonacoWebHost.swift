import AppKit
import SwiftUI
import WebKit

/// The locked-down web view: bundled page only, no network, no navigation, no new windows.
@MainActor
final class MonacoWebHost: NSObject, WKNavigationDelegate, WKUIDelegate {
    typealias Options = MonacoEditorOptions

    struct Snapshot {
        let text: String
        let version: Int
    }

    let webView: WKWebView
    var onMessage: ((MonacoBridgeMessage) -> Void)?
    private var pageURL: URL?
    private var pending: Options?
    private var project: MonacoSettings.Profile?
    private var settingsTask: Task<Void, Never>?
    private var opening = UUID()
    private var isPageReady = false
    private var isSettingsReady = false

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
        settingsTask?.cancel()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    /// The editor opens once the bundled page has loaded, so options can arrive before the page is ready.
    func open(_ options: Options) {
        settingsTask?.cancel()
        let opening = UUID()
        self.opening = opening
        pending = options
        pending?.project = nil
        project = nil
        isSettingsReady = false
        guard let directory = ForkPolicyStore.current?.directory else {
            finishOpening(.failure(.unreadable))
            return
        }
        let folder = URL(filePath: (directory as NSString).expandingTildeInPath)
        settingsTask = Task { [weak self] in
            let result = await MonacoSettingsLoader.load(directory: folder)
            guard let self, self.opening == opening, !Task.isCancelled else { return }
            self.finishOpening(result)
        }
    }

    private func finishOpening(_ result: Result<MonacoSettings.Profile, MonacoSettings.Failure>) {
        guard var options = pending else { return }
        switch result {
        case .success(let profile):
            if let failure = options.apply(profile, fontAvailable: { family in
                NSFontManager.shared.availableFontFamilies.contains {
                    $0.caseInsensitiveCompare(family) == .orderedSame
                }
            }) {
                recordFailure(failure)
            }
            project = options.project
        case .failure(let failure): recordFailure(failure)
        }
        pending = options
        isSettingsReady = true
        if isPageReady {
            openPage()
            return
        }
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

    private func recordFailure(_ failure: MonacoSettings.Failure) {
        let reason: ForkEvent.PolicyFailure = switch failure {
        case .unreadable: .unreadable
        case .invalidJSON: .invalidJSON
        case .invalidValue, .missingFont: .invalidValue
        }
        ForkLog.record(ForkEvent(
            level: .warning, category: .supervision, operation: .health, correlationID: opening,
            step: .fallback, outcome: .failed, fields: .init(policyFailure: reason)))
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
        pending?.isDark = isDark
        call("window.tinycastEditor.setTheme(theme)", ["theme": Self.theme(isDark: isDark)])
    }

    func setFont(family: String, size: Double) {
        pending?.fontFamily = family
        pending?.fontSize = size
        call("window.tinycastEditor.setFont(family, size)", [
            "family": project?.fontFamily(fallback: family) ?? family,
            "size": project?.settings.fontSize ?? size
        ])
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
        isPageReady = true
        openPage()
    }

    private func openPage() {
        guard isSettingsReady, var options = pending else { return }
        pending = nil
        let pageOptions: [String: Any]
        do {
            pageOptions = try options.pageOptions()
        } catch {
            recordFailure(.invalidValue)
            options.project = nil
            project = nil
            guard let fallback = try? options.pageOptions() else { return }
            call("window.tinycastEditor.open(options)", ["options": fallback])
            return
        }
        let arguments: [String: Any] = [
            "options": pageOptions
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
