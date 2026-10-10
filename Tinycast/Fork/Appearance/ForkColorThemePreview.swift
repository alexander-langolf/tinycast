import SwiftUI

/// The palette, an agent card and a terminal card in a theme Settings has not applied yet.
struct ForkColorThemePreview: View {
    let palette: ForkColorPalette?
    let systemIsDark: Bool

    var body: some View {
        let preview = ForkColorPreview.showing(palette, isDark: palette?.isDark ?? systemIsDark)
        VStack(spacing: Theme.Spacing.md) {
            ForkColorThemePaletteRows()
            AgentRunCard(run: AgentRunsPreviewData.blocked) {}
            TerminalInstancesPreviewData.Card(
                phase: .idle(lastStatus: 1), command: "make",
                lines: TerminalInstancesPreviewData.buildFailure, fillsWidth: true)
        }
        .environment(\.forkColorPreview, preview)
        .padding(ForkColorThemePreviewLayout.inset)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme preview")
    }
}

/// A stand-in for the launcher: a query and three rows, the second selected, in the theme's inks.
private struct ForkColorThemePaletteRows: View {
    @Environment(\.forkColorPreview) private var preview
    @Environment(\.metrics) private var metrics

    private static let rows = [("Terminal", "Application"), ("Tinycast Settings", "Command"), ("Notes", "Command")]

    var body: some View {
        let ink = ForkInk(preview)
        let theme = ForkTheme.current
        VStack(alignment: .leading, spacing: 0) {
            Text("term")
                .font(metrics.typography.searchField)
                .foregroundStyle(ink.textPrimary)
                .frame(height: metrics.size.compactHeight)
                .padding(.horizontal, metrics.spacing.md * 2)
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: metrics.spacing.xl) {
                    RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                        .fill(ink.iconPlaceholder)
                        .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                    Text(row.0)
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(ink.textPrimary)
                    Spacer()
                    Text(row.1)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(ink.textTertiary)
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.rowVertical)
                .background(
                    RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                        .fill(index == 1 ? ink.selection : .clear))
            }
            .padding(.horizontal, metrics.spacing.md)
        }
        .padding(.bottom, metrics.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ink.paletteScrim)
        .background(GlassEffectView())
        .clipShape(
            RoundedRectangle(cornerRadius: theme.points(.paletteCornerRadius, metrics), style: .continuous))
    }
}

private enum ForkColorThemePreviewLayout {
    static let inset: CGFloat = 16
}
