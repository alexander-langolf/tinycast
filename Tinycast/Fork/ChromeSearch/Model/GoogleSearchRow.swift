import Foundation

enum GoogleSearchRow: Identifiable, Equatable, Sendable {
    case typed(String)
    case history(String)
    case suggestion(String)
    case page(title: String, url: URL, detail: String)
    case website(title: String, url: URL, detail: String)

    var id: String {
        switch self {
        case .typed: return "typed"
        case .history(let text): return "h:" + text
        case .suggestion(let text): return "s:" + text
        case .page(_, let url, _): return "p:" + url.absoluteString
        case .website(_, let url, _): return "w:" + url.absoluteString
        }
    }

    /// The screen's rows for the field's text: typed, query history, Chrome pages, then Google's suggestions.
    static func rows(
        suggestions: [GoogleSuggestion], pages: [ChromeHistoryEntry] = [], typed: String,
        history: GoogleSearchHistory
    ) -> [GoogleSearchRow] {
        let recent = history.matches(for: typed)
        guard !typed.isEmpty else { return recent.map(GoogleSearchRow.history) }
        var seen = Set(recent.map { $0.lowercased() })
        seen.insert(typed.lowercased())
        var rows: [GoogleSearchRow] = [.typed(typed)] + recent.map(GoogleSearchRow.history)
        rows += pages.map(page)
        let pageURLs = Set(pages.map(\.url))
        for suggestion in suggestions {
            switch suggestion.kind {
            case .query:
                if seen.insert(suggestion.text.lowercased()).inserted {
                    rows.append(.suggestion(suggestion.text))
                }
            case .website(let url):
                guard !pageURLs.contains(url) else { continue }
                rows.append(.website(title: suggestion.text, url: url, detail: suggestion.detail))
            }
        }
        return rows
    }

    private static func page(_ entry: ChromeHistoryEntry) -> GoogleSearchRow {
        let host = entry.url.host() ?? entry.url.absoluteString
        guard !entry.title.isEmpty else { return .page(title: host, url: entry.url, detail: "") }
        return .page(title: entry.title, url: entry.url, detail: host)
    }
}
