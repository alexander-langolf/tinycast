import AppKit
import SwiftUI

/// One token: a switch, or a slider and stepper in points or percent, or a colour well, with a reset.
struct ForkThemeTokenRow: View {
    let token: ForkThemeToken
    private var store: ForkThemeStore { ForkThemeStore.current! }

    var body: some View {
        let theme = store.tokens
        let anchor = SettingsAnchor.appearance(token.component)
        Group {
            if case .flag = token.kind {
                Toggle(isOn: flag) {
                    SettingsRowTitle(anchor, token.title)
                    if let subtitle = token.subtitle { Text(subtitle) }
                }
            } else {
                SettingsRow(title: token.title, subtitle: token.subtitle, anchor: anchor) {
                    HStack(spacing: Theme.Spacing.sm) {
                        control
                        Button {
                            store.reset(token)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Reset to default")
                        .accessibilityLabel("Reset \(token.title)")
                        .disabled(!theme.isOverridden(token))
                    }
                }
            }
        }
        .settingsEnabled(isEnabled(theme))
    }

    @ViewBuilder private var control: some View {
        switch token.kind {
        case .length(let range, let step, _):
            NumberControl(token: token, range: range, step: step, value: number, text: points)
        case .fontSize(let range, _):
            NumberControl(token: token, range: range, step: 1, value: number, text: points)
        case .opacity:
            NumberControl(token: token, range: 0...1, step: 0.05, value: number) {
                "\(Int(($0 * 100).rounded())) %"
            }
        case .color:
            ColorPicker(token.title, selection: color, supportsOpacity: true)
                .labelsHidden()
        case .flag:
            EmptyView()
        }
    }

    /// Width and colour mean nothing while the stroke they describe is switched off.
    private func isEnabled(_ theme: ForkTheme) -> Bool {
        switch token {
        case .agentCardBorderWidth, .agentCardBorderColor: theme.flag(.agentCardBorder)
        case .paletteBorderWidth, .paletteBorderColor: theme.flag(.paletteBorder)
        case .terminalDividerWidth: theme.flag(.terminalDivider)
        default: true
        }
    }

    private func points(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value)) pt" : String(format: "%.1f pt", value)
    }

    private var number: Binding<Double> {
        Binding(
            get: { store.tokens.number(token) },
            set: { store.set(.number($0), for: token) })
    }

    private var flag: Binding<Bool> {
        Binding(
            get: { store.tokens.flag(token) },
            set: { store.set(.flag($0), for: token) })
    }

    /// Unset, the well shows the ink the surface draws today.
    private var color: Binding<Color> {
        Binding(
            get: {
                store.tokens.color(token)
                    ?? (token == .agentCardModelColor ? Theme.Colors.textTertiary : Theme.Colors.border)
            },
            set: { picked in
                guard let srgb = NSColor(picked).usingColorSpace(.sRGB) else { return }
                store.set(
                    .color(
                        .init(
                            red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent,
                            alpha: srgb.alphaComponent)),
                    for: token)
            })
    }
}

/// A slider for reach and a stepper for the last point; the slider snaps to the stepper's grid.
private struct NumberControl: View {
    let token: ForkThemeToken
    let range: ClosedRange<Double>
    let step: Double
    @Binding var value: Double
    let text: (Double) -> String

    var body: some View {
        Slider(value: snapped, in: range)
            .frame(width: ForkThemeRowLayout.slider)
            .accessibilityLabel(token.title)
        Text(text(value))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: ForkThemeRowLayout.readout, alignment: .trailing)
        Stepper(token.title, value: snapped, in: range, step: step)
            .labelsHidden()
    }

    private var snapped: Binding<Double> {
        Binding(
            get: { value },
            set: { value = min(max(($0 / step).rounded() * step, range.lowerBound), range.upperBound) })
    }
}

private enum ForkThemeRowLayout {
    static let slider: CGFloat = 140
    static let readout: CGFloat = 52
}
