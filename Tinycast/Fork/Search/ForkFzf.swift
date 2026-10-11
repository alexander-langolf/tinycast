import Foundation

/// fzf v2: the best alignment of one folded term in a text, scored with fzf's bonuses and gaps.
enum ForkFzf {
    enum Scheme: Sendable { case standard, path }
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

    static func charClass(_ c: Character?, scheme: Scheme = .standard) -> CharClass {
        guard let c else { return .white }
        if c.isWhitespace { return .white }
        if (scheme == .path ? "/" : "/,:;|").contains(c) { return .delimiter }
        if c.isNumber { return .digit }
        if c.isUppercase { return .upper }
        if c.isLetter { return .lower }
        return .nonWord
    }

    static func bonus(after prev: CharClass, at cur: CharClass, scheme: Scheme = .standard) -> Int {
        if scheme == .path { return pathBonus(after: prev, at: cur) }
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

    private static func pathBonus(after previous: CharClass, at current: CharClass) -> Int {
        if current != .white {
            switch previous {
            case .white, .nonWord: return bonusBoundary
            case .delimiter: return bonusDelimiter
            default: break
            }
        }
        if previous == .lower && current == .upper { return bonusCamel }
        if previous != .digit && current == .digit { return bonusCamel }
        switch current {
        case .white, .delimiter, .nonWord: return bonusBoundary
        default: return 0
        }
    }

    /// `humps` are extra word starts a folded text no longer shows (the launcher's camel humps).
    static func match(
        _ term: [Character], in raw: String, exact: Bool, humps: [Int] = [],
        scheme: Scheme = .standard
    ) -> Hit? {
        guard !term.isEmpty else { return nil }
        let bytes = Array(raw.utf8)
        // Byte offsets equal Character offsets only for ASCII without CR: Swift folds "\r\n" into one Character.
        if bytes.allSatisfy({ $0 < 128 && $0 != 13 }), term.allSatisfy({ $0.asciiValue != nil }) {
            let needle = term.map { $0.asciiValue! }
            let text = bytes.map { (65...90).contains($0) ? $0 + 32 : $0 }
            guard containsSubsequence(needle, in: text) else { return nil }
            let humpStarts = Set(humps)
            var previous: CharClass = scheme == .path ? .delimiter : .white
            let bonuses = bytes.enumerated().map { index, byte in
                let current = asciiClass(byte, scheme: scheme)
                var value = bonus(after: previous, at: current, scheme: scheme)
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
        var previous: CharClass = scheme == .path ? .delimiter : .white
        var sourceBonuses: [Int] = []
        for j in chars.indices {
            let current = charClass(chars[j], scheme: scheme)
            var value = bonus(after: previous, at: current, scheme: scheme)
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

    struct PathHit {
        let score: Int
        let start: Int
    }

    struct PathWorkspace {
        private var storage: [Int] = []

        mutating func match(
            _ term: [UInt8], in text: UnsafeBufferPointer<UInt8>, exact: Bool,
            prefix: Bool, suffix: Bool, dotStart: Int?, minimumScore: Int = 0
        ) -> PathHit? {
            guard !term.isEmpty, term.count <= text.count else { return nil }
            if !exact {
                for start in stride(from: text.count - term.count, through: 0, by: -1)
                where start == 0 || text[start - 1] == 47 || start == dotStart {
                    if term.indices.allSatisfy({ Self.fold(text[start + $0]) == term[$0] }) {
                        return PathHit(
                            score: scoreMatch * term.count + bonusDelimiter * (term.count + 1),
                            start: start)
                    }
                }
                if minimumScore >= scoreMatch * term.count + bonusDelimiter * (term.count + 1) {
                    return nil
                }
            }
            var matched = 0
            var first = 0
            for index in text.indices where Self.fold(text[index]) == term[matched] {
                if matched == 0 { first = index }
                matched += 1
                if matched == term.count { break }
            }
            guard matched == term.count else { return nil }
            var last = text.count - 1
            while Self.fold(text[last]) != term.last! { last -= 1 }
            let range = first...last
            if storage.count < text.count * 7 {
                storage = Array(repeating: 0, count: text.count * 7)
            }
            return storage.withUnsafeMutableBufferPointer { buffer in
                let bonuses = buffer.baseAddress!
                var scores = bonuses + text.count
                var runs = scores + text.count
                var nextScores = runs + text.count
                var nextRuns = nextScores + text.count
                var starts = nextRuns + text.count
                var nextStarts = starts + text.count
                var previous =
                    first == 0
                    ? CharClass.delimiter : asciiClass(text[first - 1], scheme: .path)
                for index in range {
                    let current = asciiClass(text[index], scheme: .path)
                    bonuses[index] =
                        index == dotStart
                        ? bonusDelimiter : bonus(after: previous, at: current, scheme: .path)
                    previous = current
                }
                if exact {
                    var best: PathHit?
                    for start in first...(last - term.count + 1) {
                        if prefix && start != 0 { continue }
                        if suffix && start + term.count != text.count { continue }
                        guard term.indices.allSatisfy({ Self.fold(text[start + $0]) == term[$0] })
                        else { continue }
                        var carried = bonuses[start]
                        var score = scoreMatch + carried * firstCharMultiplier
                        for index in 1..<term.count {
                            score += scoreMatch + runBonus(bonuses[start + index], carried: &carried)
                        }
                        if score >= (best?.score ?? -1) { best = PathHit(score: score, start: start) }
                    }
                    return best
                }
                var inGap = false
                var left = 0
                var leftStart = first
                for index in range {
                    if Self.fold(text[index]) == term[0] {
                        scores[index] = scoreMatch + bonuses[index] * firstCharMultiplier
                        runs[index] = 1
                        leftStart = index
                        inGap = false
                    } else {
                        scores[index] = max(0, left + (inGap ? gapExtension : gapStart))
                        runs[index] = 0
                        inGap = true
                    }
                    starts[index] = leftStart
                    left = scores[index]
                }
                if term.count == 1 {
                    let end = range.max { scores[$0] < scores[$1] }!
                    return PathHit(score: scores[end], start: starts[end])
                }
                var earliest = first
                var best = 0
                var bestStart = first
                for letter in 1..<term.count {
                    earliest += 1
                    while Self.fold(text[earliest]) != term[letter] { earliest += 1 }
                    inGap = false
                    left = 0
                    leftStart = first
                    for index in earliest...last {
                        let gap = left + (inGap ? gapExtension : gapStart)
                        var score = 0
                        var consecutive = 0
                        if Self.fold(text[index]) == term[letter] {
                            score = scores[index - 1] + scoreMatch
                            var value = bonuses[index]
                            consecutive = runs[index - 1] + 1
                            if consecutive > 1 {
                                let firstBonus = bonuses[index - consecutive + 1]
                                if value >= bonusBoundary && value > firstBonus {
                                    consecutive = 1
                                } else {
                                    value = max(value, bonusConsecutive, firstBonus)
                                }
                            }
                            if score + value < gap {
                                score += bonuses[index]
                                consecutive = 0
                            } else {
                                score += value
                            }
                        }
                        inGap = score < gap
                        if !inGap { leftStart = starts[index - 1] }
                        left = max(score, gap, 0)
                        nextScores[index] = left
                        nextRuns[index] = consecutive
                        nextStarts[index] = leftStart
                        if letter == term.count - 1 && left >= best {
                            best = left
                            bestStart = leftStart
                        }
                    }
                    swap(&scores, &nextScores)
                    swap(&runs, &nextRuns)
                    swap(&starts, &nextStarts)
                }
                return PathHit(score: best, start: bestStart)
            }
        }

        private static func fold(_ byte: UInt8) -> UInt8 {
            (65...90).contains(byte) ? byte + 32 : byte
        }
    }

    private static func asciiClass(_ byte: UInt8, scheme: Scheme) -> CharClass {
        switch byte {
        case 9...13, 32: return .white
        case 47: return .delimiter
        case 44, 58, 59, 124: return scheme == .path ? .nonWord : .delimiter
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
