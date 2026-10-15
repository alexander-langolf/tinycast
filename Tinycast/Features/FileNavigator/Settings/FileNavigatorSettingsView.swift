import SwiftUI

struct FileNavigatorSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var fsearchPath = FSearchClient.installedExecutable()?.path
    @State private var fullDiskAccess: Bool?

    private var fsearchNote: String {
        if fsearchPath == nil { return "Search Files needs fsearch installed. Run fsearch install." }
        if fullDiskAccess == false {
            return
                "fsearch has no Full Disk Access, so results may be incomplete until that binary is granted it."
        }
        return "Search Files and global folder search find files through fsearch."
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                LabeledContent {
                    Text(fsearchPath ?? "Not found")
                        .foregroundStyle(.secondary)
                } label: {
                    SettingsRowTitle(.fileNavigatorSearchEngine, "fsearch")
                    Text(fsearchNote)
                }
            } header: {
                SettingsSectionHeader(.fileNavigatorSearchEngine)
            }
            Section {
                Toggle(isOn: $settings.fileSearchHidden) {
                    SettingsRowTitle(.fileNavigatorSearchHidden, "Search hidden files")
                    Text("Lists dotfiles and dot-folders such as .config. .git is always skipped.")
                }
            } header: {
                SettingsSectionHeader(.fileNavigatorSearchHidden)
            }
            Section {
                Picker(selection: $settings.fileNavigatorEditorKind) {  // FORK: monaco-editor
                    ForEach(FileNavigatorEditorKind.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.fileNavigatorEditor, "Editor kind")
                    Text("Terminal runs the command below. Monaco opens the first file in an editor window.")
                }
                if settings.fileNavigatorEditorKind == .terminal {
                    TextField(text: $settings.fileNavigatorEditor, prompt: Text("fresh")) {
                        SettingsRowTitle(.fileNavigatorEditor, "Editor command")
                        Text("Leave blank to use Fresh. Shell arguments are allowed.")
                    }
                }
            } header: {
                SettingsSectionHeader(.fileNavigatorEditor)
            }
            FeatureCommandsSection(owner: .fileNavigator, anchor: .fileNavigatorCommands)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.fileNavigator)
        .task { fullDiskAccess = await FSearchClient.fullDiskAccess() }
    }
}
