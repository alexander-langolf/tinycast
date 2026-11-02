import Foundation
import Synchronization

extension ForkSearch {
    /// A candidate's text folded once into scorer units, so a keystroke never folds it again.
    struct Text: Sendable, Equatable, Hashable {
        /// One code per folded unit; see `unitCode`.
        let units: [UInt32]
        /// The fzf bonus of each unit.
        let bonuses: [UInt8]
        /// The source `Character` offset of each unit, or `nil` when units map one to one.
        let sources: [Int32]?
        /// The source text's `Character` count.
        let length: Int
        /// Pure ASCII without CR: units are the folded bytes, so folding the source is lowercasing.
        let isASCII: Bool
        /// The whole source folded by `ForkSearch.fold`; nil for ASCII, whose units are the fold.
        let folded: String?

        init(_ raw: String, scheme: ForkFzf.Scheme = .standard, humps: [Int] = []) {
            let humpStarts = Set(humps)
            let bytes = Array(raw.utf8)
            // Byte offsets match Character offsets only without CR, since "\r\n" is one Character.
            if bytes.allSatisfy({ $0 < 128 && $0 != 13 }) {
                units = bytes.map { UInt32((65...90).contains($0) ? $0 + 32 : $0) }
                var previous: ForkFzf.CharClass = scheme == .path ? .delimiter : .white
                bonuses = bytes.enumerated().map { index, byte in
                    let current = ForkFzf.asciiClass(byte, scheme: scheme)
                    var value = ForkFzf.bonus(after: previous, at: current, scheme: scheme)
                    if humpStarts.contains(index) { value = max(value, ForkFzf.bonusCamel) }
                    previous = current
                    return UInt8(value)
                }
                sources = nil
                length = bytes.count
                isASCII = true
                folded = nil
                return
            }
            let chars = Array(raw)
            var units: [UInt32] = [], sources: [Int32] = [], bonuses: [UInt8] = []
            var previous: ForkFzf.CharClass = scheme == .path ? .delimiter : .white
            for (j, char) in chars.enumerated() {
                let current = ForkFzf.charClass(char, scheme: scheme)
                var value = ForkFzf.bonus(after: previous, at: current, scheme: scheme)
                if humpStarts.contains(j) { value = max(value, ForkFzf.bonusCamel) }
                previous = current
                let folded: [Character]
                if let ascii = char.asciiValue {
                    let lower = (65...90).contains(ascii) ? ascii + 32 : ascii
                    folded = [Character(UnicodeScalar(lower))]
                } else {
                    folded = Array(fold(String(char)))
                }
                // An expanding fold yields several units; the later ones form a run.
                for (k, unit) in (folded.isEmpty ? [char] : folded).enumerated() {
                    units.append(ForkSearch.unitCode(unit))
                    sources.append(Int32(j))
                    bonuses.append(UInt8(k > 0 ? ForkFzf.bonusConsecutive : value))
                }
            }
            self.units = units
            self.bonuses = bonuses
            // Each character yields at least one unit, so equal counts mean one-to-one.
            self.sources = units.count == chars.count ? nil : sources
            length = chars.count
            isASCII = false
            folded = fold(raw)
        }
    }

    private static let interned = Mutex<[String: UInt32]>([:])

    /// A folded character's unit: its scalar, or a code above the scalar range for a grapheme.
    static func unitCode(_ c: Character) -> UInt32 {
        // Scalars below U+0300 have no canonical singleton, so NFC leaves them unchanged.
        if let only = c.unicodeScalars.first, c.unicodeScalars.count == 1, only.value < 0x300 {
            return only.value
        }
        let folded = String(c).precomposedStringWithCanonicalMapping
        if let only = folded.unicodeScalars.first, folded.unicodeScalars.count == 1 {
            return only.value
        }
        return interned.withLock { table in
            if let code = table[folded] { return code }
            let code = 0x110000 + UInt32(table.count)
            table[folded] = code
            return code
        }
    }
}

extension ForkSearch {
    /// A clipboard text prepared for search: a scan head, plus the whole text when it is capped.
    struct ClipboardText: Sendable {
        let raw: String
        let capped: Bool
        let head: Text
        /// The whole text: `head` itself when uncapped, otherwise prepared for literal words.
        let whole: Text

        init(_ raw: String) {
            self.raw = raw
            capped = raw.utf8.count > ForkSearch.clipboardScanLimit
            head = Text(capped ? String(raw.prefix(ForkSearch.clipboardScanLimit)) : raw)
            whole = capped ? Text(raw) : head
        }
    }
}
