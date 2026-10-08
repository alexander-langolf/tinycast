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
        query.split(whereSeparator: \.isWhitespace).map { token in
            var t = Substring(token)
            var exact = profile == .accurate, prefix = false, suffix = false, negated = false
            if t.hasPrefix("!") { negated = true; exact = true; t = t.dropFirst() }
            if t.hasPrefix("'") { exact = true; t = t.dropFirst() }
            if t.hasPrefix("^") { prefix = true; exact = true; t = t.dropFirst() }
            if t.hasSuffix("$") { suffix = true; exact = true; t = t.dropLast() }
            let folded = Array(FuzzyMatch.normalized(String(t)))
            if folded.isEmpty {
                return Term(text: Array(token), exact: true, prefix: false, suffix: false, negated: false)
            }
            return Term(text: folded, exact: exact, prefix: prefix, suffix: suffix, negated: negated)
        }
    }

    static func hit(_ term: Term, in field: String, humps: [Int] = []) -> ForkFzf.Hit? {
        // Anchors are judged on the folded text: a fold can expand (ß → ss), so source windows alone misfire.
        if term.prefix || term.suffix {
            let folded = FuzzyMatch.normalized(field)
            let word = String(term.text)
            if term.prefix && term.suffix, folded != word { return nil }
            guard (!term.prefix || folded.hasPrefix(word)) && (!term.suffix || folded.hasSuffix(word))
            else { return nil }
        }
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

    /// FTS retrieves literal long words; the resident window supplies skipped-letter matches.
    static func clipboardFTS(_ query: String) -> String? {
        let quote = { (s: Substring) in "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        guard isEnabled else { return query.count >= 3 ? quote(Substring(query)) : nil }
        var positive: [String] = [], negative: [String] = []
        for token in query.split(whereSeparator: \.isWhitespace) {
            let negated = token.hasPrefix("!")
            if negated {
                let word = token.dropFirst()
                if word.count >= 3, !word.hasPrefix("!"), !word.hasPrefix("^"),
                    !word.hasPrefix("'"), !word.hasSuffix("$")
                {
                    negative.append(quote(word))
                }
                continue
            }
            var t = token.drop { "!'^".contains($0) }
            if t.count > 1, t.hasSuffix("$") { t = t.dropLast() }
            guard t.count >= 3 else { continue }
            positive.append(quote(t))
        }
        guard !positive.isEmpty else { return nil }
        return positive.joined(separator: " AND ") + negative.map { " NOT " + $0 }.joined()
    }

    static func clipboardScore(_ query: String, _ text: String?) -> Int? {
        guard let text else { return nil }
        guard isEnabled else { return text.localizedCaseInsensitiveContains(query) ? 0 : nil }
        let words = terms(query, profile: .fuzzy)
        guard words.contains(where: { !$0.negated }) else { return nil }
        var score = 0
        for word in words {
            let result = hit(word, in: text)
            if word.negated {
                if result != nil { return nil }
                continue
            }
            guard let result, accepts(score: result.score, letters: word.text.count, level: "medium")
            else { return nil }
            score += result.score
        }
        return score
    }

    static func clipboardUnion<T, ID: Hashable>(
        _ hits: [T], resident: [T], id: (T) -> ID, createdAt: (T) -> Date
    ) -> [T] {
        guard isEnabled else { return hits }
        var seen = Set<ID>()
        return (hits + resident).enumerated().filter { seen.insert(id($0.element)).inserted }
            .sorted {
                let left = createdAt($0.element), right = createdAt($1.element)
                return left != right ? left > right : $0.offset < $1.offset
            }.map(\.element)
    }

    static func mergePaths<T, ID: Hashable>(_ first: [T], _ additional: [T], id: (T) -> ID) -> [T] {
        var seen = Set<ID>()
        return (first + additional).filter { seen.insert(id($0)).inserted }
    }

    static func fileNeedsGlob(_ query: String) -> Bool {
        terms(query, profile: .fuzzy).filter { !$0.negated }.reduce(0) { $0 + $1.text.count } >= 3
    }

    static func spotlightNameClause(_ token: String) -> String {
        let term = terms(token, profile: .fuzzy)[0]
        let escaped = term.text.map { "*?\\\"".contains($0) ? "\\" + String($0) : String($0) }
        let body = escaped.joined(separator: term.exact ? "" : "*")
        let pattern = (term.prefix ? "" : "*") + body + (term.suffix ? "" : "*")
        return "kMDItemFSName \(term.negated ? "!=" : "==") \"\(pattern)\"cd"
    }

    static func rankPaths(_ items: [(name: String, folder: String)], query: String) -> [Int] {
        let scored = items.enumerated().compactMap { index, item -> (score: Int, length: Int, index: Int)? in
            guard
                let result = match(
                    query, fields: [item.name, item.folder], weights: [1, 0.6], profile: .fuzzy)
            else { return nil }
            return (result.score, item.name.count, index)
        }
        guard !isShort(query) else { return scored.map(\.index) }
        return scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.length != $1.length { return $0.length < $1.length }
            return $0.index < $1.index
        }.map(\.index)
    }

    /// Clipboard order: input arrives newest first; ties keep it. Off: unchanged.
    static func rankClipboard<T>(_ items: [T], query: String, text: (T) -> String?) -> [T] {
        guard isEnabled else { return items }
        let scored = items.enumerated().compactMap { offset, item -> (score: Int, offset: Int, item: T)? in
            guard let s = text(item), let score = clipboardScore(query, s) else {
                return nil
            }
            return (score, offset, item)
        }
        guard !isShort(query) else { return scored.map(\.item) }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }.map(
            \.item)
    }

    /// The tiered matcher's answer computed by fzf, with tiers kept so `SearchRelevance` weights still apply.
    static func tiered(_ q: String, _ c: String) -> FuzzyMatch.Match? {
        let length = c.count
        guard !q.isEmpty else {
            return FuzzyMatch.Match(
                tier: .exact, offset: 0, queryLength: 0, candidateLength: length, spread: 0)
        }
        guard let r = match(q, fields: [c], profile: .fuzzy) else { return nil }
        // fzf's best alignment can skip a contiguous run that exists; tiers rank contiguous runs higher.
        let positive = terms(q, profile: .fuzzy).filter { !$0.negated }
        // Plain positive words are also tried as the typed phrase (exclusions are applied by `match`), so `bar baz` in "foo bar baz" stays a run.
        let plain = !positive.isEmpty && positive.allSatisfy { !$0.prefix && !$0.suffix && !$0.exact }
        let phrase = Array(positive.map { String($0.text) }.joined(separator: " "))
        let run = plain ? ForkFzf.match(phrase, in: c, exact: true) : nil
        let p = (run?.positions ?? r.positions[0]).sorted()
        let contiguous = !p.isEmpty && p.last! - p.first! + 1 == p.count
        let tier: FuzzyMatch.Tier =
            c == q
            ? .exact
            : contiguous && p.first == 0
                ? .prefix
                : contiguous
                    && ForkFzf.bonus(
                        after: ForkFzf.charClass(p.first! > 0 ? Array(c)[p.first! - 1] : nil),
                        at: ForkFzf.charClass(Array(c)[p.first!])) >= ForkFzf.bonusBoundary
                    ? .wordStart
                    : contiguous ? .substring : .subsequence
        var spread = 0
        if tier == .subsequence {
            // What the positive words would score as contiguous runs: `!words` and anchors never self-match.
            let reference = positive.reduce(0) {
                $0 + (ForkFzf.match($1.text, in: String($1.text), exact: true)?.score ?? 0)
            }
            guard reference > 0 else { return nil }
            spread = r.score * FuzzyMatch.referenceSpread(q.count) / reference
        }
        return FuzzyMatch.Match(
            tier: tier, offset: p.first ?? 0, queryLength: q.count, candidateLength: length,
            spread: spread)
    }

    /// The launcher's texts are folded or transliterated already; `humps` restore the camel starts folding lost.
    /// `SearchSensitivity` judges the score against the whole typed length, syntax and `!words` included, so the
    /// score is rescaled from the letters that can score to that length.
    static func launcherScore(_ query: String, in target: String, humps: [Int] = []) -> Int? {
        if FuzzyMatch.normalized(query) == FuzzyMatch.normalized(target) { return .max }
        guard let score = match(query, fields: [target], profile: .fuzzy, humps: humps)?.score else {
            return nil
        }
        let scoring = terms(query, profile: .fuzzy).filter { !$0.negated }.reduce(0) { $0 + $1.text.count }
        return scoring > 0 ? min(score * query.utf16.count / scoring, .max - 1) : score
    }

    /// fzf scores about 16 per letter plus bonuses, so thresholds are per-letter averages (`level` = `SearchSensitivity.rawValue`).
    static func accepts(score: Int, letters: Int, level: String) -> Bool {
        switch level {
        case "low": return true
        case "high": return score >= 24 * letters
        default: return score >= 20 * letters - 4
        }
    }
}
