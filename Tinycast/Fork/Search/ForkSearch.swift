import Foundation
import Synchronization

/// fzf extended search for every Tinycast input, off until `ForkAppearance.start()` turns it on.
enum ForkSearch {
    enum Profile: Sendable { case fuzzy, accurate }

    struct Term: Sendable, Equatable {
        let text: [Character]
        /// `text` as scorer units; see `unitCode`.
        let units: [UInt32]
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

    /// Short clipboard queries keep recency.
    static func isShort(_ query: String) -> Bool { query.filter { !$0.isWhitespace }.count <= 2 }

    /// `FuzzyMatch.normalized` minus skin-tone modifiers and emoji variation selectors.
    static func fold(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { $0.value >= 0xAD }) else { return FuzzyMatch.normalized(s) }
        let scalars = FuzzyMatch.normalized(s).unicodeScalars.filter { !isFoldIgnored($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func isFoldIgnored(_ scalar: Unicode.Scalar) -> Bool {
        (0x1F3FB...0x1F3FF).contains(scalar.value) || scalar.value == 0xFE0E || scalar.value == 0xFE0F
    }

    static func terms(_ query: String, profile: Profile) -> [Term] {
        query.split(whereSeparator: \.isWhitespace).map { token in
            var t = Substring(token)
            var exact = profile == .accurate, prefix = false, suffix = false, negated = false
            if t.hasPrefix("!") { negated = true; exact = true; t = t.dropFirst() }
            if t.hasPrefix("'") { exact = true; t = t.dropFirst() }
            if t.hasPrefix("^") { prefix = true; exact = true; t = t.dropFirst() }
            if t.hasSuffix("$") { suffix = true; exact = true; t = t.dropLast() }
            let folded = Array(fold(String(t)))
            if folded.isEmpty {
                let literal = Array(token)
                return Term(
                    text: literal, units: literal.map { unitCode($0) }, exact: true, prefix: false,
                    suffix: false, negated: false)
            }
            return Term(
                text: folded, units: folded.map { unitCode($0) }, exact: exact, prefix: prefix,
                suffix: suffix, negated: negated)
        }
    }

    /// A parsed query, compiled once per search and reused for every candidate.
    struct Query: Sendable {
        let string: String
        /// `string` folded once, for `launcherScore`'s whole-text equality.  // FORK: search
        let normalized: String
        let terms: [Term]
        let positive: [Term]
        /// The positive words' folded length: what `launcherScore` rescales from.
        let letters: Int

        init(_ query: String, profile: Profile) {
            string = query
            normalized = fold(query)
            terms = ForkSearch.terms(query, profile: profile)
            positive = terms.filter { !$0.negated }
            letters = positive.reduce(0) { $0 + $1.text.count }
        }
    }

    /// Anchors read prepared units, so no keystroke refolds the field.
    private static func anchoredHit(
        _ term: Term, in field: String, scheme: ForkFzf.Scheme, text: Text
    ) -> ForkFzf.Hit? {
        let length: Int
        if text.isASCII {
            let units = text.units, need = term.units
            if term.prefix && term.suffix, units != need { return nil }
            guard
                (!term.prefix || units.starts(with: need))
                    && (!term.suffix || units.count >= need.count && units.suffix(need.count).elementsEqual(need))
            else { return nil }
            length = text.length
        } else {
            // A fold can expand (ß → ss), so anchors cannot trust source windows.
            let folded = text.folded ?? fold(field)
            let word = String(term.text)
            if term.prefix && term.suffix, folded != word { return nil }
            guard (!term.prefix || folded.hasPrefix(word)) && (!term.suffix || folded.hasSuffix(word))
            else { return nil }
            length = text.length
        }
        if term.prefix {
            guard
                let h = ForkFzf.match(
                    term.text, in: String(field.prefix(term.text.count)), exact: true, scheme: scheme)
            else { return nil }
            return h
        }
        if term.suffix {
            let start = max(0, length - term.text.count)
            guard
                let h = ForkFzf.match(
                    term.text, in: String(field.suffix(term.text.count)), exact: true, scheme: scheme)
            else { return nil }
            return ForkFzf.Hit(score: h.score, positions: h.positions.map { $0 + start })
        }
        return nil
    }

    static func hit(
        _ term: Term, in field: String, humps: [Int] = [], scheme: ForkFzf.Scheme = .standard
    ) -> ForkFzf.Hit? {
        hit(term, in: Text(field, scheme: scheme, humps: humps), raw: field, scheme: scheme)
    }

    /// `raw` is the String `text` was prepared from; prefix and suffix anchors read it.
    static func hit(
        _ term: Term, in text: Text, raw: String, scheme: ForkFzf.Scheme = .standard
    ) -> ForkFzf.Hit? {
        if term.prefix || term.suffix { return anchoredHit(term, in: raw, scheme: scheme, text: text) }
        return ForkFzf.match(term.units, in: text, exact: term.exact)
    }

    /// Fields prepared for `match`. Humps belong to the first field only, as the launcher's do.
    static func prepared(_ fields: [String], humps: [Int] = []) -> [(text: Text, raw: String)] {
        fields.enumerated().map { index, field in
            (Text(field, humps: index == 0 ? humps : []), field)
        }
    }

    /// Every positive word must hit some field (the best one wins); a negated hit rejects the item.
    static func match(
        _ query: String, fields: [String], weights: [Double]? = nil, profile: Profile, humps: [Int] = [],
        negatedFields: [String]? = nil
    ) -> Result? {
        match(
            Query(query, profile: profile), fields: prepared(fields, humps: humps), weights: weights,
            negatedFields: negatedFields.map { prepared($0, humps: humps) })
    }

    /// `match` over fields prepared once; see `prepared`.
    static func match(
        _ query: Query, fields: [(text: Text, raw: String)], weights: [Double]? = nil,
        negatedFields: [(text: Text, raw: String)]? = nil
    ) -> Result? {
        guard !query.positive.isEmpty else { return nil }
        var total = 0
        var positions = Array(repeating: [Int](), count: fields.count)
        for term in query.terms {
            var best: (score: Int, field: Int, hit: ForkFzf.Hit)?
            let candidates = term.negated ? (negatedFields ?? fields) : fields
            for (index, field) in candidates.enumerated() {
                guard let h = hit(term, in: field.text, raw: field.raw) else { continue }
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

    /// Snippets and Quicklinks have no ranking; when off, they keep upstream's substring test.
    static func contains(_ query: String, in text: String?, profile: Profile = .fuzzy) -> Bool {
        contains(Query(query, profile: profile), in: text)
    }

    /// `contains` for a query compiled once per filter pass.
    static func contains(_ query: Query, in text: String?) -> Bool {
        guard let text else { return false }
        guard isEnabled else { return text.localizedCaseInsensitiveContains(query.string) }
        return match(query, fields: prepared([text])) != nil
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

    static let clipboardScanLimit = 4096

    static func score(_ query: String, _ text: String, profile: Profile) -> Int? {
        score(Query(query, profile: profile).terms, in: Text(text), raw: text)
    }

    /// `literal` is the whole text behind a capped head, so a word the head misses can still count.
    private static func score(
        _ words: [Term], in text: Text, raw: String, literal: ClipboardText? = nil
    ) -> Int? {
        guard words.contains(where: { !$0.negated }) else { return nil }
        func literalHit(_ word: Term) -> ForkFzf.Hit? {
            guard let literal, !word.prefix else { return nil }
            if word.suffix { return anchoredHit(word, in: literal.raw, scheme: .standard, text: literal.whole) }
            guard containsLiteral(word, in: literal) else { return nil }
            return ForkFzf.match(word.units, in: Text(String(word.text)), exact: word.exact)
        }
        var total = 0
        for word in words {
            let result = hit(word, in: text, raw: raw)
            if word.negated {
                if result != nil || literalHit(word) != nil { return nil }
                continue
            }
            if let result, accepts(score: result.score, letters: word.text.count, level: "medium") {
                total += result.score
            } else if let found = literalHit(word) {
                total += found.score
            } else {
                return nil
            }
        }
        return total
    }

    /// ASCII words scan raw bytes, since folding a 100 KB text for every word is too slow.
    static func containsLiteral(_ word: Term, in item: ClipboardText) -> Bool {
        guard word.text.allSatisfy({ $0.asciiValue != nil }) else {
            return containsRun(word.units, in: item.whole.units)
        }
        let needle = word.text.map { $0.asciiValue! }
        let lower = { (b: UInt8) in (65...90).contains(b) ? b + 32 : b }
        return item.raw.utf8.withContiguousStorageIfAvailable { bytes -> Bool in
            guard bytes.count >= needle.count else { return false }
            outer: for start in 0...(bytes.count - needle.count) where lower(bytes[start]) == needle[0] {
                for k in 1..<needle.count where lower(bytes[start + k]) != needle[k] { continue outer }
                return true
            }
            return false
        } ?? (item.raw.range(of: String(word.text), options: [.caseInsensitive, .diacriticInsensitive]) != nil)
    }

    private static func containsRun<C: Equatable>(_ needle: [C], in haystack: [C]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) where haystack[start] == needle[0] {
            if haystack[start..<start + needle.count].elementsEqual(needle) { return true }
        }
        return false
    }

    static func clipboardScore(_ query: String, _ text: String?) -> Int? {
        guard let text else { return nil }
        guard isEnabled else { return text.localizedCaseInsensitiveContains(query) ? 0 : nil }
        return clipboardScore(Query(query, profile: .fuzzy), ClipboardText(text))
    }

    /// Scores a prepared clipboard text; a capped item's literal words also match the whole text.
    static func clipboardScore(_ query: Query, _ item: ClipboardText) -> Int? {
        guard isEnabled else { return item.raw.localizedCaseInsensitiveContains(query.string) ? 0 : nil }
        return clipboardScore(query, item, literal: item.capped)
    }

    private static func clipboardScore(_ query: Query, _ item: ClipboardText, literal: Bool) -> Int? {
        let anchored = query.terms.contains { $0.prefix || $0.suffix }
        return score(
            query.terms, in: item.head,
            raw: item.capped && anchored ? String(item.raw.prefix(clipboardScanLimit)) : item.raw,
            literal: literal ? item : nil)
    }

    static func clipboardResults<T, ID: Hashable>(
        _ hits: [T], resident: [T], query: String, id: (T) -> ID, prepared: (T) -> ClipboardText?,
        createdAt: (T) -> Date, pinnedAt: (T) -> Date?
    ) -> [T] {
        let compiled = Query(query, profile: .fuzzy)
        let literalIDs = Set(hits.map(id))
        let union = clipboardUnion(hits, resident: resident, id: id, createdAt: createdAt)
        let scored = union.enumerated().compactMap { offset, item -> (T, Int, Int)? in
            guard let prepared = prepared(item) else { return nil }
            let literal = literalIDs.contains(id(item)) || prepared.capped
            guard let value = clipboardScore(compiled, prepared, literal: literal) else { return nil }
            return (item, value, offset)
        }
        let pins = scored.filter { pinnedAt($0.0) != nil }.sorted {
            pinnedAt($0.0)! < pinnedAt($1.0)!
        }
        let short = isShort(query)
        let ordinary = scored.filter { pinnedAt($0.0) == nil }.sorted {
            !short && $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2
        }
        return (pins + ordinary).map(\.0)
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

    /// The tiered matcher's answer from fzf, with tiers kept so `SearchRelevance` weights apply.
    static func tiered(_ q: String, _ c: String) -> FuzzyMatch.Match? {
        tiered(Query(q, profile: .fuzzy), c)
    }

    /// `c` is folded once into `Text` and shared by the best alignment and the phrase run.
    static func tiered(_ query: Query, _ c: String) -> FuzzyMatch.Match? {
        let length = c.count
        guard !query.string.isEmpty else {
            return FuzzyMatch.Match(
                tier: .exact, offset: 0, queryLength: 0, candidateLength: length, spread: 0)
        }
        let text = Text(c)
        guard let r = match(query, fields: [(text, c)]) else { return nil }
        // fzf's best alignment can skip a contiguous run; tiers rank contiguous runs higher.
        let positive = query.positive
        // Plain words are also tried as one phrase, so "bar baz" in "foo bar baz" stays a run.
        let plain = !positive.isEmpty && positive.allSatisfy { !$0.prefix && !$0.suffix && !$0.exact }
        let run = plain
            ? ForkFzf.match(
                Array(positive.map { String($0.text) }.joined(separator: " ")).map(unitCode), in: text,
                exact: true)
            : nil
        let p = (run?.positions ?? r.positions[0]).sorted()
        let chars = Array(c)
        let contiguous = !p.isEmpty && p.last! - p.first! + 1 == p.count
        let tier: FuzzyMatch.Tier =
            c == query.string
            ? .exact
            : contiguous && p.first == 0
                ? .prefix
                : contiguous
                    && ForkFzf.bonus(
                        after: ForkFzf.charClass(p.first! > 0 ? chars[p.first! - 1] : nil),
                        at: ForkFzf.charClass(chars[p.first!])) >= ForkFzf.bonusBoundary
                    ? .wordStart
                    : contiguous ? .substring : .subsequence
        var spread = 0
        if tier == .subsequence {
            // Positive words as contiguous runs; `!words` and anchors never self-match.
            let reference = positive.reduce(0) {
                $0 + (ForkFzf.match($1.units, in: Text(String($1.text)), exact: true)?.score ?? 0)
            }
            guard reference > 0 else { return nil }
            spread = r.score * FuzzyMatch.referenceSpread(query.string.count) / reference
        }
        return FuzzyMatch.Match(
            tier: tier, offset: p.first ?? 0, queryLength: query.string.count, candidateLength: length,
            spread: spread)
    }

    /// Launcher texts are already folded or transliterated; `humps` restore the camel starts lost.
    static func launcherScore(_ query: String, in target: String, humps: [Int] = []) -> Int? {
        launcherScore(Query(query, profile: .fuzzy), in: Text(target, humps: humps), raw: target)
    }

    /// An ASCII target's units are its fold, so the query's bytes compare with them directly.
    private static func foldsEqual(_ query: Query, _ target: Text) -> Bool {
        guard target.isASCII else { return target.folded == query.normalized }
        let bytes = query.normalized.utf8
        return bytes.count == target.units.count
            && zip(bytes, target.units).allSatisfy { UInt32($0) == $1 }
    }

    /// Scores are rescaled from the scoring letters to the whole typed length, syntax included.
    static func launcherScore(_ query: Query, in target: Text, raw: String) -> Int? {
        if foldsEqual(query, target) { return .max }  // FORK: search
        guard let score = match(query, fields: [(target, raw)])?.score else { return nil }
        return query.letters > 0
            ? min(score * query.string.utf16.count / query.letters, .max - 1) : score
    }

    /// Thresholds are per-letter averages, since fzf scores about 16 per letter plus bonuses.
    static func accepts(score: Int, letters: Int, level: String) -> Bool {
        switch level {
        case "low": return true
        case "high": return score >= 24 * letters
        default: return score >= 20 * letters - 4
        }
    }
}
