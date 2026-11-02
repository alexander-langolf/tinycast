import AppKit

@MainActor
enum ForkSelectionDiagnostics {
    static func read(in app: NSRunningApplication) -> AccessibilityText.Selection {
        let span = ForkTrace.begin(.selectedText, category: .selection, step: .accessibility)
        let result = AccessibilityText.read(in: app)
        if case .text(let text) = result {
            span.end(.success, fields: .init(length: text.count, bundleID: app.bundleIdentifier))
        } else {
            span.end(result == .empty ? .empty : .unavailable, fields: .init(bundleID: app.bundleIdentifier))
        }
        return result
    }

    static func selection(in app: NSRunningApplication) -> String? {
        if case .text(let text) = read(in: app) { return text }
        return nil
    }
}
