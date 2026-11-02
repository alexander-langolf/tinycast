import AppKit

@MainActor
final class ForkAccessibilitySelectionSource: ForkSelectionSource {
    let kind = ForkSelection.Kind.accessibility
    private(set) var lastReadWasEmpty = false

    func read(from app: NSRunningApplication) async -> ForkSelection? {
        let result = ForkSelectionDiagnostics.read(in: app)
        lastReadWasEmpty = result == .empty
        guard case .text(let text) = result else { return nil }
        return ForkSelection(text: text, source: kind)
    }
}
