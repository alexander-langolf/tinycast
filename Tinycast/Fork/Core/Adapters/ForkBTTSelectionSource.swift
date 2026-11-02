import AppKit

@MainActor
struct ForkBTTSelectionSource: ForkSelectionSource {
    let kind = ForkSelection.Kind.betterTouchTool

    func read(from app: NSRunningApplication) async -> ForkSelection? {
        guard let text = await ForkBTTBrowserSelection.read(from: app) else { return nil }
        return ForkSelection(text: text, source: kind)
    }
}
