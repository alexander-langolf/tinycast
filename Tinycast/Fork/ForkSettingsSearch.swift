import Foundation

enum ForkSettingsSearch {
    static let entry = SettingsSearchEntry(
        .generalAppearance, "Interface font", keywords: ["font", "typeface", "family"])
    static let monoEntry = SettingsSearchEntry(
        .generalAppearance, "Monospaced font", keywords: ["font", "code", "mono", "fixed width", "terminal"])
}
