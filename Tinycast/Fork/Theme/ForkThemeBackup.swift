import Foundation

/// Tokens and colour theme as one flat object, so a backup from before colour themes still reads.
struct ForkThemeBackup: Codable, Sendable {
    static let colorThemeKey = "colorTheme"

    var tokens: [String: ForkThemeValue] = [:]
    var colorTheme: ForkColorTheme?

    init(tokens: [String: ForkThemeValue], colorTheme: ForkColorTheme?) {
        self.tokens = tokens
        self.colorTheme = colorTheme
    }

    private struct Key: CodingKey {
        let stringValue: String
        init(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    /// An entry that doesn't decode is skipped, as a token the store wouldn't accept would be.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        for key in container.allKeys {
            if key.stringValue == Self.colorThemeKey {
                colorTheme = try? container.decode(ForkColorTheme.self, forKey: key)
            } else if let value = try? container.decode(ForkThemeValue.self, forKey: key) {
                tokens[key.stringValue] = value
            }
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (name, value) in tokens { try container.encode(value, forKey: Key(stringValue: name)) }
        try container.encodeIfPresent(colorTheme, forKey: Key(stringValue: Self.colorThemeKey))
    }
}
