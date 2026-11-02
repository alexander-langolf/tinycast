import AppKit

@MainActor
struct ForkClipboardSelectionSource: ForkSelectionSource {
    let kind = ForkSelection.Kind.clipboardBorrow
    let borrow: @MainActor (NSRunningApplication) async -> String?

    func read(from app: NSRunningApplication) async -> ForkSelection? {
        guard let text = await borrow(app) else { return nil }
        return ForkSelection(text: text, source: kind)
    }
}
