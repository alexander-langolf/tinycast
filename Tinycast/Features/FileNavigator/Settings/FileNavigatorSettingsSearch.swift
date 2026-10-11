import Foundation

enum FileNavigatorSettingsSearch {
    static let entries: [SettingsSearchEntry] = [
        .init(pane: .fileNavigator, keywords: ["browse", "files", "folders"]),
        .init(.fileNavigatorSearchEngine, "File search engine", keywords: ["ripgrep", "Spotlight", "rg"]),
        .init(.fileNavigatorEditor, "Editor command", keywords: ["Fresh", "EDITOR", "terminal"]),
        .init(group: .fileNavigatorCommands, "Commands", keywords: ["Browse Files", "shortcut"])
    ]
}
