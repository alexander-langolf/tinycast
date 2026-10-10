import SwiftUI

/// General's former Appearance section, then the theme tokens per component, each with its reset.
struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings
    private var isThemed: Bool { ForkTheme.current.colorTheme != nil }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Picker(selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                } label: {
                    SettingsRowTitle(.generalAppearance, "Theme")
                    if isThemed { Text("Only applies to Tinycast (default) colours.") }
                }
                .settingsEnabled(!isThemed)
                InterfaceSizeRow()
                ForkFontRow()
                ForkFontRow(kind: .monospaced)
                WindowModeRow()
                Toggle(isOn: $settings.showFavoritesInCompactMode) {
                    SettingsRowTitle(.generalAppearance, "Show favorites in compact mode")
                    Text("Launch them with ⌘1–⌘5.")
                }
                .settingsEnabled(settings.compactMode)
                Toggle(isOn: $settings.openOnCursorScreen) {
                    SettingsRowTitle(.generalAppearance, "Follow the cursor across displays")
                }
                Toggle(isOn: $settings.paletteDraggable) {
                    SettingsRowTitle(.generalAppearance, "Drag to reposition")
                    Text("Drag the strip above the search field.")
                }
            } header: {
                SettingsSectionHeader(.generalAppearance)
            }

            ForkColorThemeSection()
            ForkThemeSection(component: .agentCard) { AgentCardThemePreview() }
            ForkThemeSection(component: .terminalInstance) { TerminalCardThemePreview() }
            ForkThemeSection(component: .palette)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.appearance)
    }
}
