import Foundation
import Synchronization

/// fzf extended search for every Tinycast input. Off until `ForkAppearance.start()`, so upstream harnesses keep upstream behaviour.
enum ForkSearch {
    enum Profile: Sendable { case fuzzy, accurate }

    struct Term: Sendable, Equatable {
        let text: [Character]
        let exact: Bool
        let prefix: Bool
        let suffix: Bool
        let negated: Bool
    }

    struct Result: Sendable, Equatable {
        let score: Int
        /// One array of character offsets per field.
        let positions: [[Int]]
    }

    private static let enabled = Mutex(false)
    static var isEnabled: Bool { enabled.withLock { $0 } }
    static func setEnabled(_ value: Bool) { enabled.withLock { $0 = value } }

    /// 1–2 typed letters match nearly everything, so callers keep recency or use order.
    static func isShort(_ query: String) -> Bool { query.filter { !$0.isWhitespace }.count <= 2 }

    static func terms(_ query: String, profile: Profile) -> [Term] {
        query.split(whereSeparator: \.isWhitespace).compactMap { token in
            var t = Substring(token)
            var exact = profile == .accurate, prefix = false, suffix = false, negated = false
            if t.hasPrefix("!") { negated = true; exact = true; t = t.dropFirst() }
            if t.hasPrefix("'") { exact = true; t = t.dropFirst() }
            if t.hasPrefix("^") { prefix = true; exact = true; t = t.dropFirst() }
            if t.count > 1, t.hasSuffix("$") { suffix = true; exact = true; t = t.dropLast() }
            let folded = Array(FuzzyMatch.normalized(String(t)))
            return folded.isEmpty
                ? nil : Term(text: folded, exact: exact, prefix: prefix, suffix: suffix, negated: negated)
        }
    }

    static func hit(_ term: Term, in field: String, humps: [Int] = []) -> ForkFzf.Hit? {
        if term.prefix {
            guard let h = ForkFzf.match(term.text, in: String(field.prefix(term.text.count)), exact: true)
            else { return nil }
            return h
        }
        if term.suffix {
            let start = max(0, field.count - term.text.count)
            guard let h = ForkFzf.match(term.text, in: String(field.suffix(term.text.count)), exact: true)
            else { return nil }
            return ForkFzf.Hit(score: h.score, positions: h.positions.map { $0 + start })
        }
        return ForkFzf.match(term.text, in: field, exact: term.exact, humps: humps)
    }

    /// Every positive word must hit some field (the best one wins); any negated word that hits rejects the item.
    static func match(
        _ query: String, fields: [String], weights: [Double]? = nil, profile: Profile, humps: [Int] = []
    ) -> Result? {
        let terms = terms(query, profile: profile)
        guard terms.contains(where: { !$0.negated }) else { return nil }
        var total = 0
        var positions = Array(repeating: [Int](), count: fields.count)
        for term in terms {
            var best: (score: Int, field: Int, hit: ForkFzf.Hit)?
            for (index, field) in fields.enumerated() {
                guard let h = hit(term, in: field, humps: index == 0 ? humps : []) else { continue }
                let weighted = Int(Double(h.score) * (weights?[index] ?? 1))
                if weighted > (best?.score ?? Int.min) { best = (weighted, index, h) }
            }
            if term.negated {
                if best != nil { return nil }
                continue
            }
            guard let best else { return nil }
            total += best.score
            positions[best.field] += best.hit.positions
        }
        return Result(score: total, positions: positions)
    }

    /// For filters with no ranking of their own (Snippets, Quicklinks): upstream's substring test when off.
    static func contains(_ query: String, in text: String?, profile: Profile = .fuzzy) -> Bool {
        guard let text else { return false }
        guard isEnabled else { return text.localizedCaseInsensitiveContains(query) }
        return match(query, fields: [text], profile: profile) != nil
    }
}
