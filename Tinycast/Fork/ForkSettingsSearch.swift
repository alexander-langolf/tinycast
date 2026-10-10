import Foundation

enum ForkSettingsSearch {
    static let entry = SettingsSearchEntry(
        .generalAppearance, "Interface font", keywords: ["font", "typeface", "family"])
    static let monoEntry = SettingsSearchEntry(
        .generalAppearance, "Monospaced font", keywords: ["font", "code", "mono", "fixed width", "terminal"])
    static let aiWorkingDirectoryTitle = "Working folder"
    static let aiWorkingDirectoryEntry = SettingsSearchEntry(
        .aiChat, aiWorkingDirectoryTitle,
        keywords: ["cwd", "directory", "vault", "agents.md", "claude.md", "codex", "claude"])
}
