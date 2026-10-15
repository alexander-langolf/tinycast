import Foundation

protocol GoogleSuggesting: Sendable {
    /// Empty on any failure: suggestions fail quietly.
    func suggestions(for query: String) async -> [GoogleSuggestion]
}

/// The Search Google screen's state: the typed query, Google's suggestions and Chrome's matching pages.
@MainActor
@Observable
final class ChromeSearchSession {
    private(set) var query = ""
    private(set) var suggestions: [GoogleSuggestion] = []
    private(set) var pages: [ChromeHistoryEntry] = []

    @ObservationIgnored private let suggester: any GoogleSuggesting
    @ObservationIgnored private let chromeHistory: any ChromeHistoryReading
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    @ObservationIgnored private var pageTask: Task<Void, Never>?

    init(
        suggester: any GoogleSuggesting, chromeHistory: any ChromeHistoryReading,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.suggester = suggester
        self.chromeHistory = chromeHistory
        self.now = now
    }

    /// Every edit asks at once and drops the earlier ask; the old rows stay until new ones land.
    func queryChanged(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != query else { return }
        cancelWork()
        query = trimmed
        guard !trimmed.isEmpty else {
            suggestions = []
            pages = []
            return
        }
        suggestionTask = Task { [weak self, suggester] in
            let found = await suggester.suggestions(for: trimmed)
            guard !Task.isCancelled else { return }
            self?.applySuggestions(found, for: trimmed)
        }
        pageTask = Task { [weak self, chromeHistory, now] in
            let found = await chromeHistory.candidates(for: trimmed)
            guard !Task.isCancelled else { return }
            self?.applyPages(ChromeHistoryRanking.rank(found, query: trimmed, now: now()), for: trimmed)
        }
    }

    func reset() {
        cancelWork()
        query = ""
        suggestions = []
        pages = []
        chromeHistory.discardCopy()
    }

    private func cancelWork() {
        suggestionTask?.cancel()
        suggestionTask = nil
        pageTask?.cancel()
        pageTask = nil
    }

    private func applySuggestions(_ found: [GoogleSuggestion], for query: String) {
        guard self.query == query else { return }
        suggestions = found
    }

    private func applyPages(_ found: [ChromeHistoryEntry], for query: String) {
        guard self.query == query else { return }
        pages = found
    }
}
