import Foundation

/// The search history on disk: a small JSON array, loaded once and rewritten atomically per change.
@MainActor
@Observable
final class GoogleSearchHistoryStore {
    private(set) var history: GoogleSearchHistory
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        let entries =
            (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        history = GoogleSearchHistory(entries: entries ?? [])
    }

    func record(_ query: String) { change { $0.record(query) } }

    func remove(_ query: String) { change { $0.remove(query) } }

    func clear() { change { $0.clear() } }

    private func change(_ edit: (inout GoogleSearchHistory) -> Void) {
        let before = history
        edit(&history)
        guard history != before, let data = try? JSONEncoder().encode(history.entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
