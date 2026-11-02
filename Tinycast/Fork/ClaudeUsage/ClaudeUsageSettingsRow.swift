import SwiftUI

struct ClaudeUsageSettingsRow: View {
    @Environment(ClaudeUsageCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var settings = coordinator.settings
        Picker(selection: $settings.display) {
            ForEach(ClaudeUsageMenuBarDisplay.allCases, id: \.self) { display in
                Text(display.title).tag(display)
            }
        } label: {
            SettingsRowTitle(.aiProviders, "Menu Bar")
        }
    }
}
