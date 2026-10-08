import Foundation

/// fzf v2: the best alignment of one folded term in a text, scored with fzf's bonuses and gaps.
enum ForkFzf {
    struct Hit: Sendable, Equatable {
        let score: Int
        /// Unique character offsets into the source text, in ascending order.
        let positions: [Int]
    }

    static let scoreMatch = 16
    static let gapStart = -3
    static let gapExtension = -1
    static let bonusWhite = 10
    static let bonusDelimiter = 9
    static let bonusBoundary = 8
    static let bonusCamel = 7
    static let bonusConsecutive = -(gapStart + gapExtension)
    static let firstCharMultiplier = 2

    enum CharClass: Equatable { case white, delimiter, nonWord, lower, upper, digit }

    static func charClass(_ c: Character?) -> CharClass {
        guard let c else { return .white }
        if c.isWhitespace { return .white }
        if "/,:;|".contains(c) { return .delimiter }
        if c.isNumber { return .digit }
        if c.isUppercase { return .upper }
        if c.isLetter { return .lower }
        return .nonWord
    }

    static func bonus(after prev: CharClass, at cur: CharClass) -> Int {
        guard cur == .lower || cur == .upper || cur == .digit else {
            return cur == .white ? 0 : bonusBoundary
        }
        switch prev {
        case .white: return bonusWhite
        case .delimiter: return bonusDelimiter
        case .nonWord: return bonusBoundary
        default: break
        }
        if prev == .lower, cur == .upper { return bonusCamel }
        if prev != .digit, cur == .digit { return bonusCamel }
        return 0
    }

    /// `humps` are extra word starts a folded text no longer shows (the launcher's camel humps).
    static func match(_ term: [Character], in raw: String, exact: Bool, humps: [Int] = []) -> Hit? {
        guard !term.isEmpty else { return nil }
        let bytes = Array(raw.utf8)
        // Byte offsets equal Character offsets only for ASCII without CR: Swift folds "\r\n" into one Character.
        if bytes.allSatisfy({ $0 < 128 && $0 != 13 }), term.allSatisfy({ $0.asciiValue != nil }) {
            let needle = term.map { $0.asciiValue! }
            let text = bytes.map { (65...90).contains($0) ? $0 + 32 : $0 }
            guard containsSubsequence(needle, in: text) else { return nil }
            let humpStarts = Set(humps)
            var previous = CharClass.white
            let bonuses = bytes.enumerated().map { index, byte in
                let current = asciiClass(byte)
                var value = bonus(after: previous, at: current)
                if humpStarts.contains(index) { value = max(value, bonusCamel) }
                previous = current
                return value
            }
            return exact ? exactMatch(needle, text, bonuses) : align(needle, text, bonuses)
        }
        let chars = Array(raw)
        var text: [Character] = []
        var sources: [Int] = []
        for j in chars.indices {
            let folded: [Character]
            if let ascii = chars[j].asciiValue {
                folded = [Character(UnicodeScalar((65...90).contains(ascii) ? ascii + 32 : ascii))]
            } else {
                folded = Array(FuzzyMatch.normalized(String(chars[j])))
            }
            let expanded = folded.isEmpty ? [chars[j]] : folded
            text.append(contentsOf: expanded)
            sources.append(contentsOf: repeatElement(j, count: expanded.count))
        }
        guard containsSubsequence(term, in: text) else { return nil }
        let humpStarts = Set(humps)
        var previous = CharClass.white
        var sourceBonuses: [Int] = []
        for j in chars.indices {
            let current = charClass(chars[j])
            var value = bonus(after: previous, at: current)
            if humpStarts.contains(j) { value = max(value, bonusCamel) }
            sourceBonuses.append(value)
            previous = current
        }
        let bonuses = sources.indices.map { index in
            index > 0 && sources[index] == sources[index - 1]
                ? bonusConsecutive : sourceBonuses[sources[index]]
        }
        guard let hit = exact ? exactMatch(term, text, bonuses) : align(term, text, bonuses) else {
            return nil
        }
        return Hit(score: hit.score, positions: Set(hit.positions.map { sources[$0] }).sorted())
    }

    private static func asciiClass(_ byte: UInt8) -> CharClass {
        switch byte {
        case 9...13, 32: return .white
        case 47, 44, 58, 59, 124: return .delimiter
        case 48...57: return .digit
        case 65...90: return .upper
        case 97...122: return .lower
        default: return .nonWord
        }
    }

    private static func containsSubsequence<C: Equatable>(_ term: [C], in text: [C]) -> Bool {
        guard !term.isEmpty, term.count <= text.count else { return false }
        var next = 0
        for character in text where character == term[next] {
            next += 1
            if next == term.count { return true }
        }
        return false
    }

    /// The bonus a character earns inside a consecutive run, as fzf carries the run's first bonus.
    private static func runBonus(_ bonus: Int, carried: inout Int) -> Int {
        if bonus >= bonusBoundary, bonus > carried { carried = bonus }
        return max(bonus, carried, bonusConsecutive)
    }

    private static func exactMatch<C: Equatable>(_ term: [C], _ text: [C], _ bonuses: [Int]) -> Hit? {
        let m = term.count
        var best: Hit?
        for start in 0...(text.count - m)
        where text[start] == term[0] && Array(text[start..<start + m]) == term {
            var carried = bonuses[start]
            var score = scoreMatch + bonuses[start] * firstCharMultiplier
            for k in 1..<max(m, 1) where k < m {
                score += scoreMatch + runBonus(bonuses[start + k], carried: &carried)
            }
            if score > (best?.score ?? Int.min) {
                best = Hit(score: score, positions: Array(start..<start + m))
            }
        }
        return best
    }

    private static func align<C: Equatable>(_ term: [C], _ text: [C], _ bonuses: [Int]) -> Hit? {
        let m = term.count, n = text.count
        let none = Int.min / 2
        var score = [Int](repeating: none, count: n)
        var carried = [Int](repeating: 0, count: n)
        var back: [[Int]] = [[Int](repeating: -1, count: n)]
        for j in 0..<n where text[j] == term[0] {
            score[j] = scoreMatch + bonuses[j] * firstCharMultiplier
            carried[j] = bonuses[j]
        }
        for i in 1..<max(m, 1) where i < m {
            var next = [Int](repeating: none, count: n)
            var nextCarried = [Int](repeating: 0, count: n)
            var from = [Int](repeating: -1, count: n)
            // max over k <= j-2 of score[k] + k: a gap of g letters costs gapStart + (g-1)*gapExtension = -2-g.
            var gapBest = none, gapAt = -1
            for j in 1..<n {
                if j >= 2, score[j - 2] > none, score[j - 2] + (j - 2) > gapBest {
                    gapBest = score[j - 2] + (j - 2)
                    gapAt = j - 2
                }
                guard text[j] == term[i] else { continue }
                var viaRun = none, runCarry = 0
                if score[j - 1] > none {
                    runCarry = carried[j - 1]
                    viaRun = score[j - 1] + scoreMatch + runBonus(bonuses[j], carried: &runCarry)
                }
                let viaGap = gapBest > none ? gapBest - j - 1 + scoreMatch + bonuses[j] : none
                if viaRun == none, viaGap == none { continue }
                if viaRun >= viaGap {
                    next[j] = viaRun; nextCarried[j] = runCarry; from[j] = j - 1
                } else {
                    next[j] = viaGap; nextCarried[j] = bonuses[j]; from[j] = gapAt
                }
            }
            score = next
            carried = nextCarried
            back.append(from)
        }
        guard let end = score.indices.max(by: { score[$0] < score[$1] }), score[end] > none else {
            return nil
        }
        var positions = [Int](repeating: 0, count: m)
        var j = end
        for i in stride(from: m - 1, through: 0, by: -1) {
            positions[i] = j
            j = back[i][j]
        }
        return Hit(score: score[end], positions: positions)
    }
}
