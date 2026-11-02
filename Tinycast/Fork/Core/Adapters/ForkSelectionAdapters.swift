import AppKit

@MainActor
enum ForkSelectionAdapters {
    struct Read {
        let selection: ForkSelection?
        let accessibilityWasEmpty: Bool
    }

    static func read(
        from app: NSRunningApplication, acceptingEmptyText: Bool = true,
        borrow: @escaping @MainActor (NSRunningApplication) async -> String?
    ) async -> Read {
        let accessibility = ForkAccessibilitySelectionSource()
        let reader = ForkSelectionReader(sources: [
            accessibility, ForkBTTSelectionSource(), ForkClipboardSelectionSource(borrow: borrow)
        ])
        let selection = await reader.read(from: app, acceptingEmptyText: acceptingEmptyText)
        return Read(selection: selection, accessibilityWasEmpty: accessibility.lastReadWasEmpty)
    }
}
