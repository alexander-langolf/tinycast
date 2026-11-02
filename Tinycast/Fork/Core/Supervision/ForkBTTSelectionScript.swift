import Foundation

enum ForkBTTSelectionScript {
    static let browsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev",
        "com.google.Chrome.canary", "com.microsoft.edgemac", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "com.operasoftware.Opera",
        "org.chromium.Chromium", "com.apple.Safari",
    ]

    static let script = """
        (() => {
          const e = document.activeElement;
          if (e && (e.tagName === 'TEXTAREA' || e.tagName === 'INPUT')) {
            try {
              if (typeof e.selectionStart === 'number' && e.selectionEnd > e.selectionStart) {
                return e.value.slice(e.selectionStart, e.selectionEnd);
              }
            } catch (_) {}
          }
          return String(window.getSelection() || '');
        })()
        """

    @MainActor
    static func readySource(target: String, ensureReady: @MainActor () async -> Bool) async -> String? {
        guard let source = source(target: target) else { return nil }
        guard await ensureReady(), !Task.isCancelled else { return nil }
        return source
    }

    static func source(target: String) -> String? {
        guard browsers.contains(target) else { return nil }
        let action: [String: Any] = [
            "BTTPredefinedActionType": 600, "BTTLaunchPath": script,
            "BTTAdditionalActionData": ["BTTActionRunJavaScriptInBrowserTarget": target],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: action),
            let json = String(data: data, encoding: .utf8)
        else { return nil }
        let literal = json.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
            with timeout of 2 seconds
              tell application id "com.hegenberg.BetterTouchTool" to trigger_action "\(literal)"
            end timeout
            """
    }
}
