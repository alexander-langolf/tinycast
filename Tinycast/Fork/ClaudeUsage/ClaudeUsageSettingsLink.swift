import SwiftUI

struct ClaudeUsageSettingsLink: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(ClaudeUsageCoordinator.self) private var coordinator
    @Environment(SettingsNavigationState.self) private var navigation

    func body(content: Content) -> some View {
        content
            .onChange(of: coordinator.settingsRequest, initial: true) {
                if coordinator.settingsRequest != nil { isPresented = true }
            }
            .onChange(of: navigation.scrollRequest, initial: true) {
                guard navigation.scrollRequest?.target == ForkSettingsSearch.claudeUsageMenuBar.target else { return }
                coordinator.openAccountSettings()
            }
    }
}
