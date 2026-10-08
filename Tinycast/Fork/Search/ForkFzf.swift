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
        let chars = Array(raw)
        var text: [Character] = []
        var sources: [Int] = []
        var bonuses: [Int] = []
        let humpStarts = Set(humps)
        var prev = CharClass.white
        for j in chars.indices {
            let cur = charClass(chars[j])
            let folded = Array(FuzzyMatch.normalized(String(chars[j])))
            let expanded = folded.isEmpty ? [chars[j]] : folded
            var firstBonus = bonus(after: prev, at: cur)
            if humpStarts.contains(j) { firstBonus = max(firstBonus, bonusCamel) }
            for (offset, char) in expanded.enumerated() {
                text.append(char)
                sources.append(j)
                bonuses.append(offset == 0 ? firstBonus : bonusConsecutive)
            }
            prev = cur
        }
        guard !term.isEmpty, term.count <= text.count else { return nil }
        guard let hit = exact ? exactMatch(term, text, bonuses) : align(term, text, bonuses) else {
            return nil
        }
        return Hit(score: hit.score, positions: Set(hit.positions.map { sources[$0] }).sorted())
    }

    /// The bonus a character earns inside a consecutive run, as fzf carries the run's first bonus.
    private static func runBonus(_ bonus: Int, carried: inout Int) -> Int {
        if bonus >= bonusBoundary, bonus > carried { carried = bonus }
        return max(bonus, carried, bonusConsecutive)
    }

    private static func exactMatch(_ term: [Character], _ text: [Character], _ bonuses: [Int]) -> Hit? {
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

    private static func align(_ term: [Character], _ text: [Character], _ bonuses: [Int]) -> Hit? {
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
