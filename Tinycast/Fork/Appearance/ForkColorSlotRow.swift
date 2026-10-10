import AppKit
import SwiftUI

/// One theme colour as Slack lists it: a swatch to pick from, its hex, and a pencil to type one.
struct ForkColorSlotRow: View {
    let slot: ForkColorTheme.Slot
    @Binding var color: ForkThemeValue.Color
    @State private var isEditing = false
    @State private var typed = ""

    var body: some View {
        SettingsRow(title: slot.title, anchor: .appearanceColors) {
            HStack(spacing: Theme.Spacing.sm) {
                ColorPicker(slot.title, selection: swatch, supportsOpacity: false)
                    .labelsHidden()
                Text(color.hex6)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button {
                    typed = color.hex6
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Type a hex colour")
                .accessibilityLabel("Edit \(slot.title)")
                .popover(isPresented: $isEditing, arrowEdge: .bottom) { editor }
            }
        }
    }

    private var editor: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("#RRGGBB", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(width: ForkColorSlotLayout.field)
                .onSubmit(commit)
            Button("Set", action: commit)
                .disabled(ForkThemeValue.Color(hex: typed) == nil)
        }
        .padding(Theme.Spacing.md)
    }

    private func commit() {
        guard let parsed = ForkThemeValue.Color(hex: typed) else { return }
        color = parsed.withAlpha(1)
        isEditing = false
    }

    private var swatch: Binding<Color> {
        Binding(
            get: { Color(.sRGB, red: color.red, green: color.green, blue: color.blue) },
            set: { picked in
                guard let srgb = NSColor(picked).usingColorSpace(.sRGB) else { return }
                color = .init(
                    red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: 1)
            })
    }
}

private enum ForkColorSlotLayout {
    static let field: CGFloat = 110
}
