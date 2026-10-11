import SwiftUI

struct FileNavigatorSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                TextField("${EDITOR:-fresh}", text: $settings.fileNavigatorEditor) {
                    SettingsRowTitle(.fileNavigatorEditor, "Editor command")
                    Text("Leave blank to use $EDITOR, or Fresh when unset. Shell arguments are allowed.")
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
