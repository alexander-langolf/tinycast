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
                    SettingsRowTitle(.generalAppearance, "Appearance")
                    if isThemed { Text("Only applies to Tinycast (default) colours.") }
                }
                .settingsEnabled(!isThemed)
                Toggle(isOn: $settings.animationsEnabled) {
                    SettingsRowTitle(.generalAppearance, "Show animations")
                }
                InterfaceSizeRow()
                ForkFontRow()
                ForkFontRow(kind: .monospaced)
                WindowModeRow()
                    .background {
                        if !settings.compactMode {
                            Color.clear.settingsAnchor(.generalCompactShortcuts)
                        }
                    }
                Toggle(isOn: $settings.openOnCursorScreen) {
                    SettingsRowTitle(.generalAppearance, "Follow the cursor across displays")
                }
                Toggle(isOn: $settings.paletteDraggable) {
                    SettingsRowTitle(.generalAppearance, "Drag to move the launcher")
                    Text("Move the launcher by dragging the search bar.")
                }
            } header: {
                SettingsSectionHeader(.generalAppearance)
            }

            if settings.compactMode { CompactShortcutsSection() }

            ForkColorThemeSection()
            ForkThemeSection(component: .agentCard) { AgentCardThemePreview() }
            ForkThemeSection(component: .terminalInstance) { TerminalCardThemePreview() }
            ForkThemeSection(component: .palette)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.appearance)
    }
}
