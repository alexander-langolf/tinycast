import Foundation

struct MonacoSettings: Codable, Sendable {
    enum WordWrap: String, Codable, Sendable {
        case off, on, wordWrapColumn, bounded
    }

    struct Profile: Sendable {
        let settings: MonacoSettings
        let theme: MonacoTheme

        func fontFamily(fallback: String) -> String {
            "\"\(settings.fontFamily)\", \(fallback)"
        }
    }

    enum Failure: Error, Sendable {
        case unreadable, invalidJSON, invalidValue, missingFont
    }

    let theme: String
    let fontFamily: String
    let fontSize: Double
    let lineHeight: Double
    let minimap: Bool
    let wordWrap: WordWrap

    static func parse(_ data: Data) throws -> MonacoSettings {
        let settings: MonacoSettings
        do { settings = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw Failure.invalidJSON }
        guard !settings.theme.isEmpty, !settings.theme.hasPrefix("/"),
            !settings.theme.hasPrefix("~"), !settings.theme.contains(":"),
            !settings.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !settings.fontFamily.contains(where: { $0 == "\"" || $0 == "\\" || $0.isNewline }),
            settings.fontSize.isFinite, (6...100).contains(settings.fontSize),
            settings.lineHeight.isFinite, (0...150).contains(settings.lineHeight)
        else { throw Failure.invalidValue }
        return settings
    }

    func themeURL(relativeTo settingsURL: URL) -> URL {
        settingsURL.deletingLastPathComponent().appending(path: theme)
    }
}
