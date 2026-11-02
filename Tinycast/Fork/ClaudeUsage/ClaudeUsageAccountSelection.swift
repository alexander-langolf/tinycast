import SwiftUI

struct ClaudeUsageAccountSelection: ViewModifier {
    @Binding var selection: AIProviderRoute?
    @Binding var tab: AIProviderTab
    @Environment(ClaudeUsageCoordinator.self) private var coordinator

    func body(content: Content) -> some View {
        content.onChange(of: coordinator.settingsRequest, initial: true) {
            guard coordinator.consumeSettingsRequest() else { return }
            selection = .api(coordinator.accountConnectionID)
            tab = .overview
        }
    }
}
