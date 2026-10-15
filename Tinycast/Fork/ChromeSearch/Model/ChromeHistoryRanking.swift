import Foundation

enum ChromeHistoryRanking {
    static let limit = 5
    static let candidateLimit = 200

    static func words(in query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every word must hit the title or URL; a title or host prefix outranks a substring, then visits and recency.
    static func rank(_ entries: [ChromeHistoryEntry], query: String, now: Date) -> [ChromeHistoryEntry] {
        let words = words(in: query)
        guard !words.isEmpty else { return [] }
        let scored: [(entry: ChromeHistoryEntry, score: Double)] = entries.compactMap { entry in
            guard let match = matchScore(entry, words: words) else { return nil }
            let days = max(now.timeIntervalSince(entry.lastVisit), 0) / 86_400
            let recency = 1 / (1 + days / 30)
            return (entry, match * 1000 + log(Double(max(entry.visitCount, 1)) + 1) * 10 + recency * 10)
        }
        return
            scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.entry.url.absoluteString < $1.entry.url.absoluteString
            }
            .prefix(limit)
            .map(\.entry)
    }

    private static func matchScore(_ entry: ChromeHistoryEntry, words: [String]) -> Double? {
        let title = entry.title.lowercased()
        let url = entry.url.absoluteString.lowercased()
        let host = (entry.url.host() ?? "").lowercased()
        var total = 0.0
        for word in words {
            if title.hasPrefix(word) || host.hasPrefix(word) || host.hasPrefix("www." + word) {
                total += 2
            } else if title.contains(word) || url.contains(word) {
                total += 1
            } else {
                return nil
            }
        }
        return total / Double(words.count)
    }
}
