import Foundation

/// `$ command` in the palette. `$` must stand alone so `$100 in eur` stays a calculation.
enum TerminalCommandQuery {
    static let prefix: Character = "$"

    /// The command to run, "" while only the prefix is typed, nil for any other query.
    static func command(in query: String) -> String? {
        let trimmed = query.drop { $0.isWhitespace }
        guard trimmed.first == prefix else { return nil }
        let rest = trimmed.dropFirst()
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }
}
