import SwiftUI

struct FileNavigatorSettingsView: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        @Bindable var settings = settings
        return Form {
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
    }
}
