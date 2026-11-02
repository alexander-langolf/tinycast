import Foundation

struct MonacoTheme: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case dark, light
    }

    struct TokenColor: Codable, Sendable {
        enum Scope: Codable, Sendable {
            case single(String)
            case multiple([String])

            init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let scopes = try? value.decode([String].self) {
                    self = .multiple(scopes)
                } else {
                    self = .single(try value.decode(String.self))
                }
            }

            func encode(to encoder: Encoder) throws {
                var value = encoder.singleValueContainer()
                switch self {
                case .single(let scope): try value.encode(scope)
                case .multiple(let scopes): try value.encode(scopes)
                }
            }
        }

        struct Settings: Codable, Sendable {
            let foreground: String?
            let fontStyle: String?
        }

        let scope: Scope?
        let settings: Settings
    }

    let type: Kind
    let colors: [String: String]
    let tokenColors: [TokenColor]

    static func parse(_ data: Data) throws -> MonacoTheme {
        let decoded: MonacoTheme
        do { decoded = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw MonacoSettings.Failure.invalidJSON }
        // VS Code themes write "" for a colour they leave unset, so it is dropped, not rejected.
        let theme = MonacoTheme(
            type: decoded.type, colors: decoded.colors.filter { !$0.value.isEmpty }, tokenColors: decoded.tokenColors)
        guard theme.colors.values.allSatisfy(isColor),
            theme.tokenColors.allSatisfy({ $0.settings.foreground.map(isColor) ?? true })
        else { throw MonacoSettings.Failure.invalidValue }
        return theme
    }

    private static func isColor(_ value: String) -> Bool {
        value.first == "#" && [3, 4, 6, 8].contains(value.utf8.count - 1)
            && value.dropFirst().utf8.allSatisfy {
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            }
    }
}
