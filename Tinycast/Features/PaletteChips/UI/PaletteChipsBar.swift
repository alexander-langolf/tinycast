import SwiftUI

/// Four round glass chips; the selected one is tinted with the accent.
struct PaletteChipsBar: View {
    @Environment(PaletteChipsCoordinator.self) private var chips
    @Environment(\.metrics) private var metrics

    var body: some View {
        let layout = chips.layout(metrics)
        GlassEffectContainer(spacing: layout.gap) {
            HStack(spacing: layout.gap) {
                ForEach(PaletteChip.allCases, id: \.self) { chip in
                    chipButton(chip, side: layout.chipSide)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func chipButton(_ chip: PaletteChip, side: CGFloat) -> some View {
        let selected = chips.selected == chip
        let enabled = chips.available.contains(chip)
        return Button {
            chips.pick(chip)
        } label: {
            Image(systemName: chip.systemImage)
                .font(metrics.typography.headerIcon)
                .foregroundStyle(selected ? Color.accentColor : Theme.Colors.textPrimary)
                .frame(width: side, height: side)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .glassEffect(
            selected ? .regular.tint(Color.accentColor.opacity(0.35)).interactive() : .regular.interactive(),
            in: Circle()
        )
        .help("\(chip.title)  ⌘\(chip.rawValue + 1)")
        .accessibilityLabel(chip.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
