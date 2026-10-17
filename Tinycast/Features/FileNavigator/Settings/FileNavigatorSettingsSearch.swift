import Foundation

enum FileNavigatorSettingsSearch {
    static let entries: [SettingsSearchEntry] = [
        .init(pane: .fileNavigator, keywords: ["browse", "files", "folders"]),
        .init(
            .fileNavigatorEditor, "Editor kind",
            keywords: ["Monaco", "terminal", "code editor", "VS Code"]),
        .init(.fileNavigatorEditor, "Editor command", keywords: ["Fresh", "shell arguments", "terminal"]),
        .init(group: .fileNavigatorCommands, "Commands", keywords: ["Browse Files", "shortcut"])
    ]
}
