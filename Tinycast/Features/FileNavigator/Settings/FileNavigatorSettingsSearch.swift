import Foundation

enum FileNavigatorSettingsSearch {
    static let entries: [SettingsSearchEntry] = [
        .init(pane: .fileNavigator, keywords: ["browse", "files", "folders"]),
        .init(.fileNavigatorSearchEngine, "File search engine", keywords: ["ripgrep", "Spotlight", "rg"]),
        .init(
            .fileNavigatorSearchHidden, "Search hidden files",
            keywords: ["dotfiles", "--hidden", "ripgrep", "rg"]),
        .init(.fileNavigatorEditor, "Editor command", keywords: ["Fresh", "shell arguments", "terminal"]),
        .init(group: .fileNavigatorCommands, "Commands", keywords: ["Browse Files", "shortcut"])
    ]
}
