import AppKit

@MainActor
struct ForkSelectionReader {
    private let sources: [any ForkSelectionSource]

    init(sources: [any ForkSelectionSource]) {
        self.sources = ForkSelection.Kind.allCases.flatMap { kind in sources.filter { $0.kind == kind } }
    }

    func read(
        from app: NSRunningApplication, allowingBorrow: Bool = true,
        acceptingEmptyText: Bool = true
    ) async -> ForkSelection? {
        for source in sources {
            guard !Task.isCancelled, !app.isTerminated else { return nil }
            if source.kind == .clipboardBorrow, !allowingBorrow { continue }
            let span = ForkTrace.begin(.selectedText, category: .selection, step: source.kind.step)
            let selection = await source.read(from: app)
            guard !Task.isCancelled, !app.isTerminated else {
                span.end(.cancelled)
                return nil
            }
            let accepted = selection.flatMap { acceptingEmptyText || !$0.text.isEmpty ? $0 : nil }
            span.end(accepted == nil ? .empty : .success, fields: .init(length: selection?.text.count))
            if let accepted { return accepted }
        }
        return nil
    }
}
