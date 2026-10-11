import SwiftUI

/// The bottom of the palette, the margin under it and two run cards, from the canvas's sample runs.
struct AgentCardThemePreview: View {
    var body: some View {
        let layout = AgentRunsMetrics(metrics: .standard)
        VStack(spacing: layout.paletteMargin) {
            ForkThemePaletteEdge()
            VStack(spacing: layout.gap) {
                AgentRunCard(run: AgentRunsPreviewData.working) {}
                AgentRunCard(run: AgentRunsPreviewData.blocked) {}
            }
        }
        .modifier(ForkThemeBackdrop())
    }
}

/// A finished command's card, from the canvas's sample output.
struct TerminalCardThemePreview: View {
    var body: some View {
        TerminalInstancesPreviewData.Card(
            phase: .idle(lastStatus: 0), command: "ls -la",
            lines: Array(TerminalInstancesPreviewData.listing.prefix(4)), fillsWidth: true
        )
        .modifier(ForkThemeBackdrop())
    }
}

/// The palette's lower edge in its own glass, scrim and outline, to measure the cards' margin against.
private struct ForkThemePaletteEdge: View {
    var body: some View {
        let theme = ForkTheme.current
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: theme.points(.paletteCornerRadius, .standard),
            bottomTrailingRadius: theme.points(.paletteCornerRadius, .standard), style: .continuous)
        Color.clear
            .frame(height: ForkThemePreviewLayout.paletteEdge)
            .background(theme.paletteScrim)
            .background(GlassEffectView())
            .clipShape(shape)
            .accessibilityHidden(true)
    }
}

/// A desktop-like gradient behind the glass, as in the cards' canvas previews.
private struct ForkThemeBackdrop: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(ForkThemePreviewLayout.inset)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .padding(.vertical, Theme.Spacing.xs)
    }
}

private enum ForkThemePreviewLayout {
    static let inset: CGFloat = 16
    static let paletteEdge: CGFloat = 28
}
