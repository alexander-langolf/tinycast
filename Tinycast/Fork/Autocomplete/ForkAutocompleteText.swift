import Foundation

struct ForkAutocompleteInput: Sendable {
    let context: [String]
    let prefix: String
}

enum ForkAutocompleteText {
    private static let separators = CharacterSet(charactersIn: ".!?\n:;()[]{}\"`|<>/\\=*#_~@$%^&+,0123456789")
    private static let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'-")
    private static let tokenCharacters = letters.union(.decimalDigits)

    static func input(_ text: String, caret: Int) -> ForkAutocompleteInput? {
        let value = text as NSString
        guard caret == value.length else { return nil }
        let before = String(text.suffix(512))
        let prefix = String(before.reversed().prefix { $0.unicodeScalars.allSatisfy(letters.contains) }.reversed())
        guard prefix.count <= 30, prefix.isEmpty || valid(prefix.lowercased()) else { return nil }
        let context = Self.context(String(before.dropLast(prefix.count)))
        return ForkAutocompleteInput(context: context, prefix: prefix)
    }

    static func context(_ text: String) -> [String] {
        let segment = text.components(separatedBy: separators).last ?? ""
        let tokens = segment.components(separatedBy: letters.inverted)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'-")).lowercased() }
            .filter { valid($0) }
        return Array((["<s>", "<s>"] + tokens).suffix(2))
    }

    static func finishedWords(previous: String, current: String, location: Int) -> [(context: [String], word: String)] {
        let old = previous as NSString
        let new = current as NSString
        let length = new.length - old.length
        guard length > 0, length <= 256, location >= 0, location <= old.length,
              new.substring(to: location) == old.substring(to: location),
              new.substring(from: location + length) == old.substring(from: location) else { return [] }
        let inserted = new.substring(with: NSRange(location: location, length: length)) as NSString
        var result: [(context: [String], word: String)] = []
        for index in 0..<inserted.length {
            if let scalar = UnicodeScalar(inserted.character(at: index)), tokenCharacters.contains(scalar) { continue }
            let end = location + index
            guard end > 0 else { continue }
            let before = new.substring(with: NSRange(location: max(0, end - 512), length: min(512, end)))
            let token = String(before.reversed().prefix { $0.unicodeScalars.allSatisfy(tokenCharacters.contains) }.reversed())
            let word = token.trimmingCharacters(in: CharacterSet(charactersIn: "'-")).lowercased()
            guard valid(word) else { continue }
            result.append((context(String(before.dropLast(token.count))), word))
        }
        return result
    }

    private static func valid(_ word: String) -> Bool {
        guard !word.isEmpty, word.count <= 30, let first = word.utf8.first,
              (97...122).contains(first) else { return false }
        return word.utf8.allSatisfy { (97...122).contains($0) || $0 == 39 || $0 == 45 }
    }
}
