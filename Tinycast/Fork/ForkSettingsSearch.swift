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

    /// The Appearance pane and one row per theme token, each under its component's section.
    static let appearance: [SettingsSearchEntry] =
        [.init(pane: .appearance, keywords: ["theme", "look", "style", "customise", "tokens"])]
        + ForkThemeToken.Component.allCases.flatMap { component -> [SettingsSearchEntry] in
            let anchor = SettingsAnchor.appearance(component)
            let group = SettingsSearchEntry(
                group: anchor, anchor.title, keywords: ["appearance", "theme", "reset"])
            return [group]
                + component.tokens.map { SettingsSearchEntry(anchor, $0.title, keywords: $0.keywords) }
        }
}

extension SettingsAnchor {
    static let appearanceAgentCard = Self(tab: .appearance, title: "Agent Card")
    static let appearanceTerminalInstance = Self(tab: .appearance, title: "Terminal Instance")
    static let appearancePalette = Self(tab: .appearance, title: "Palette")

    static func appearance(_ component: ForkThemeToken.Component) -> Self {
        switch component {
        case .agentCard: appearanceAgentCard
        case .terminalInstance: appearanceTerminalInstance
        case .palette: appearancePalette
        }
    }
}
