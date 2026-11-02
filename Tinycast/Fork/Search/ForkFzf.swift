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
        match(term.map(ForkSearch.unitCode), in: ForkSearch.Text(raw, scheme: scheme, humps: humps), exact: exact)
    }

    /// Best alignment of a folded term over prepared text, as source character offsets.
    static func match(_ term: [UInt32], in text: ForkSearch.Text, exact: Bool) -> Hit? {
        guard !term.isEmpty, containsSubsequence(term, in: text.units) else { return nil }
        guard
            let hit = exact
                ? exactMatch(term, text.units, text.bonuses)
                : align(term, text.units, text.bonuses)
        else { return nil }
        guard let sources = text.sources else { return hit }
        return Hit(score: hit.score, positions: Set(hit.positions.map { Int(sources[$0]) }).sorted())
    }

    static func asciiClass(_ byte: UInt8, scheme: Scheme) -> CharClass {
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

    private static func exactMatch(_ term: [UInt32], _ text: [UInt32], _ bonuses: [UInt8]) -> Hit? {
        let m = term.count
        var best: Hit?
        for start in 0...(text.count - m)
        where text[start] == term[0] && text[start..<start + m].elementsEqual(term) {
            var carried = Int(bonuses[start])
            var score = scoreMatch + Int(bonuses[start]) * firstCharMultiplier
            for k in 1..<max(m, 1) where k < m {
                score += scoreMatch + runBonus(Int(bonuses[start + k]), carried: &carried)
            }
            if score > (best?.score ?? Int.min) {
                best = Hit(score: score, positions: Array(start..<start + m))
            }
        }
        return best
    }

    private static func align(_ term: [UInt32], _ text: [UInt32], _ bonuses: [UInt8]) -> Hit? {
        let m = term.count
        // Alignments lie between the first term[0] and the last term[m-1], so DP only that window.
        guard let lo = text.firstIndex(of: term[0]), let hi = text.lastIndex(of: term[m - 1]),
            hi - lo + 1 >= m
        else { return nil }
        let none = Int.min / 2
        let width = hi - lo + 1
        // Each distinct term letter gets a slot; equal letters share its window columns.
        var letters: [UInt32] = []
        var slot: [Int] = []
        for unit in term {
            if let known = letters.firstIndex(of: unit) {
                slot.append(known)
            } else {
                letters.append(unit)
                slot.append(letters.count - 1)
            }
        }
        var asciiSlot = [Int](repeating: -1, count: 128)
        for (index, unit) in letters.enumerated() where unit < 128 { asciiSlot[Int(unit)] = index }
        let letterSlots = letters
        func slotOf(_ unit: UInt32) -> Int {
            unit < 128 ? asciiSlot[Int(unit)] : (letterSlots.firstIndex(of: unit) ?? -1)
        }
        // Window columns where each letter occurs, ascending, stored as one run per slot.
        var counts = [Int](repeating: 0, count: letters.count)
        for j in 0..<width {
            let s = slotOf(text[lo + j])
            if s >= 0 { counts[s] += 1 }
        }
        var offsets = [Int](repeating: 0, count: letters.count + 1)
        for s in letters.indices { offsets[s + 1] = offsets[s] + counts[s] }
        var occurrence = [Int](repeating: 0, count: offsets[letters.count])
        var cursor = offsets
        for j in 0..<width {
            let s = slotOf(text[lo + j])
            if s >= 0 {
                occurrence[cursor[s]] = j
                cursor[s] += 1
            }
        }
        // Cells are flat: row i is `rowStart[i]..<rowStart[i + 1]`; `back` holds absolute indices.
        let cellCount = slot.reduce(0) { $0 + counts[$1] }
        var columns: [Int] = [], scores: [Int] = [], carried: [Int] = [], back: [Int] = []
        columns.reserveCapacity(cellCount)
        scores.reserveCapacity(cellCount)
        carried.reserveCapacity(cellCount)
        back.reserveCapacity(cellCount)
        var rowStart = [0]
        for j in occurrence[offsets[slot[0]]..<offsets[slot[0] + 1]] {
            columns.append(j)
            scores.append(scoreMatch + Int(bonuses[lo + j]) * firstCharMultiplier)
            carried.append(Int(bonuses[lo + j]))
            back.append(-1)
        }
        rowStart.append(columns.count)
        for i in 1..<max(m, 1) where i < m {
            let previousStart = rowStart[i - 1], previousEnd = rowStart[i]
            // Running max over k <= j-2 of score[k] + k: a gap of g letters costs -2-g.
            var gapBest = none, gapAt = -1
            var p = previousStart
            for j in occurrence[offsets[slot[i]]..<offsets[slot[i] + 1]] {
                // Ascending k with a strict > keeps the first maximum, as the dense row did.
                while p < previousEnd, columns[p] <= j - 2 {
                    let value = scores[p] + columns[p]
                    if value > gapBest { gapBest = value; gapAt = p }
                    p += 1
                }
                let bonus = Int(bonuses[lo + j])
                var viaRun = none, runCarry = 0, runFrom = -1
                if p < previousEnd, columns[p] == j - 1 {
                    runCarry = carried[p]
                    viaRun = scores[p] + scoreMatch + runBonus(bonus, carried: &runCarry)
                    runFrom = p
                }
                let viaGap = gapBest > none ? gapBest - j - 1 + scoreMatch + bonus : none
                if viaRun == none, viaGap == none { continue }
                columns.append(j)
                if viaRun >= viaGap {
                    scores.append(viaRun); carried.append(runCarry); back.append(runFrom)
                } else {
                    scores.append(viaGap); carried.append(bonus); back.append(gapAt)
                }
            }
            if columns.count == previousEnd { return nil }
            rowStart.append(columns.count)
        }
        // The first maximal cell wins, as `max(by:)` over the dense row did.
        let lastStart = rowStart[m - 1]
        guard lastStart < rowStart[m] else { return nil }
        var end = lastStart
        for index in lastStart..<rowStart[m] where scores[index] > scores[end] { end = index }
        var positions = [Int](repeating: 0, count: m)
        var index = end
        for i in stride(from: m - 1, through: 0, by: -1) {
            positions[i] = columns[index] + lo
            index = back[index]
        }
        return Hit(score: scores[end], positions: positions)
    }
}
