import SwiftUI

struct FileNavigatorSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Picker(selection: $settings.fileSearchEngine) {
                    ForEach(ForkFileSearchEngine.allCases, id: \.self) { engine in
                        Text(engine.title).tag(engine)
                    }
                } label: {
                    SettingsRowTitle(.fileNavigatorSearchEngine, "File search engine")
                    Text(
                        ForkFileSearchEngine.executable() == nil
                            ? "ripgrep was not found. File search uses Spotlight."
                            : "Choose how Search Files and recursive folder search find files.")
                }
            } header: {
                SettingsSectionHeader(.fileNavigatorSearchEngine)
            }
            Section {
                TextField(text: $settings.fileNavigatorEditor, prompt: Text("fresh")) {
                    SettingsRowTitle(.fileNavigatorEditor, "Editor command")
                    Text("Leave blank to use Fresh. Shell arguments are allowed.")
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
