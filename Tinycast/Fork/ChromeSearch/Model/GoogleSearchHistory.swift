import Foundation

/// The queries sent to Google, most recent first, case-insensitively unique and capped.
struct GoogleSearchHistory: Sendable, Equatable {
    static let capacity = 50
    static let matchLimit = 5

    private(set) var entries: [String]

    init(entries: [String] = []) {
        self.entries = []
        for entry in entries.reversed() { record(entry) }
    }

    mutating func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.removeAll { Self.same($0, trimmed) }
        entries.insert(trimmed, at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
    }

    mutating func remove(_ query: String) {
        entries.removeAll { Self.same($0, query) }
    }

    mutating func clear() { entries = [] }

    /// An empty `typed` lists the most recent; otherwise entries containing it, minus `typed` itself.
    func matches(for typed: String) -> [String] {
        let needle = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return Array(entries.prefix(Self.matchLimit)) }
        return entries.lazy
            .filter { !Self.same($0, needle) && $0.localizedCaseInsensitiveContains(needle) }
            .prefix(Self.matchLimit).map { $0 }
    }

    private static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(
            rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}
