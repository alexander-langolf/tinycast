import SwiftUI

struct PersistentLauncherHeader: View {
    let metrics: InterfaceMetrics

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: ForkTheme.current.points(.paletteCornerRadius, metrics),
            style: .continuous)
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: metrics.spacing.md * 2)
            Image(systemName: PaletteMode.launcher.systemImage)
                .font(metrics.typography.headerIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: metrics.size.headerIconSlot)
            Spacer().frame(width: metrics.spacing.xl)
            Text(PaletteMode.launcher.placeholder)
                .font(metrics.typography.searchField)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: metrics.spacing.md * 2)
        }
        .frame(height: metrics.size.headerHeight)
        .padding(.vertical, metrics.size.headerPadding)
        .frame(width: metrics.size.panelWidth)
        .background(ForkTheme.current.paletteScrim)
        .background(GlassEffectView())
        .clipShape(shape)
        .overlay {
            if ForkTheme.current.flag(.paletteBorder) {
                shape.strokeBorder(
                    ForkTheme.current.color(.paletteBorderColor) ?? Theme.Colors.border,
                    lineWidth: ForkTheme.current.points(.paletteBorderWidth, .standard))
            }
        }
    }
}
