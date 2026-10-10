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

    /// The Appearance pane, its colour theme, and one row per token under its component's section.
    static let appearance: [SettingsSearchEntry] =
        [
            .init(pane: .appearance, keywords: ["theme", "look", "style", "customise", "tokens"]),
            .init(
                .appearanceColors, "Colour theme",
                keywords: ["color", "preset", "github", "ayu", "material", "cursor", "monokai", "slack"]),
            .init(group: .appearanceColors, "Import theme", keywords: ["paste", "string", "vs code", "vscode"]),
            .init(group: .appearanceColors, "Copy theme string", keywords: ["export", "share"]),
            .init(.appearanceColors, "Window gradient", keywords: ["fade", "background"])
        ]
        + ForkColorTheme.Slot.allCases.map {
            SettingsSearchEntry(.appearanceColors, $0.title, keywords: ["color", "colour", "theme", "hex"])
        }
        + ForkThemeToken.Component.allCases.flatMap { component -> [SettingsSearchEntry] in
            let anchor = SettingsAnchor.appearance(component)
            let group = SettingsSearchEntry(
                group: anchor, anchor.title, keywords: ["appearance", "theme", "reset"])
            return [group]
                + component.tokens.map { SettingsSearchEntry(anchor, $0.title, keywords: $0.keywords) }
        }

    /// The Automation pane, its sections and the rows a user would search for by name.
    static let automation: [SettingsSearchEntry] = [
        .init(pane: .automation, keywords: ["mcp", "api", "tinycast://", "agent", "integration"]),
        .init(.automationClients, "Allow automation", keywords: ["mcp", "server", "enable", "listen"]),
        .init(.automationClients, "Create Client", keywords: ["token", "keychain", "scope", "rotate", "revoke"]),
        .init(
            .automationConnect, "Connect an Agent",
            keywords: ["claude code", "codex", "cursor", "mcp add", "config", "bridge"]),
        .init(.automationCapabilities, "What Clients Can Do", keywords: ["tools", "resources", "scopes"]),
        .init(.automationLinks, "Links", keywords: ["url", "url scheme", "deep link", "hud", "palette"]),
        .init(.automationFiles, "Automation folder", keywords: ["audit", "log", "agent profiles", "finder"])
    ]
}

extension SettingsAnchor {
    static let appearanceColors = Self(tab: .appearance, title: "Colours")
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
