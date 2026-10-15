import Foundation

enum FileNavigatorSettingsSearch {
    static let entries: [SettingsSearchEntry] = [
        .init(pane: .fileNavigator, keywords: ["browse", "files", "folders"]),
        .init(.fileNavigatorSearchEngine, "fsearch", keywords: ["file search", "engine", "index"]),
        .init(
            .fileNavigatorSearchHidden, "Search hidden files",
            keywords: ["dotfiles", "--hidden", "ripgrep", "rg"]),
        .init(
            .fileNavigatorEditor, "Editor kind",
            keywords: ["Monaco", "terminal", "code editor", "VS Code"]),
        .init(.fileNavigatorEditor, "Editor command", keywords: ["Fresh", "shell arguments", "terminal"]),
        .init(group: .fileNavigatorCommands, "Commands", keywords: ["Browse Files", "shortcut"])
    ]
}
