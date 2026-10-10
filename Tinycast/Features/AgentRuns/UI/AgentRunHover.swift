import SwiftUI

/// What a card needs to know about the launcher's pointer arming, injected so the card does not depend
/// on `PaletteState` (the preview target compiles the cards without the palette).
struct AgentRunHoverArming: Sendable {
    let isArmed: @MainActor @Sendable () -> Bool
    let disarmToken: @MainActor @Sendable () -> UUID

    /// Previews and the playground: hover always lights.
    static let always = AgentRunHoverArming(isArmed: { true }, disarmToken: { Self.constantToken })
    private static let constantToken = UUID()
}

extension EnvironmentValues {
    @Entry var agentRunHoverArming = AgentRunHoverArming.always
}

private struct AgentRunHover: ViewModifier {
    @Environment(\.agentRunHoverArming) private var arming
    @Binding var hovered: Bool

    func body(content: Content) -> some View {
        content
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active: hovered = arming.isArmed()
                case .ended: hovered = false
                }
            }
            // Disarming under a still pointer fires no hover phase, so the drop clears the card.
            .onChange(of: arming.disarmToken()) { hovered = false }
    }
}

extension View {
    /// `armedHover` for run cards: same behaviour, with the arming state supplied by the environment.
    func agentRunHover(_ hovered: Binding<Bool>) -> some View {
        modifier(AgentRunHover(hovered: hovered))
    }
}
