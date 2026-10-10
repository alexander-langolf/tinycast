import SwiftUI

/// What the card's buttons and return key do; previews pass the defaults.
struct TerminalInstanceActions {
    var submit: () -> Void = {}
    var togglePinned: () -> Void = {}
    var openInKitty: () -> Void = {}
    var close: () -> Void = {}
}

/// Variant A, "Grow": one glass card whose bar is the compact palette and whose log grows below.
/// Plain values in and a view builder for the output, so previews need no session, shell or libghostty.
struct TerminalInstanceCard<Output: View>: View {
    let phase: TerminalSessionPhase
    let command: String
    let directory: String
    let startupNotice: String?
    let isFullScreen: Bool
    let isPinned: Bool
    let showsOutput: Bool
    @Binding var input: String
    var actions = TerminalInstanceActions()
    @ViewBuilder let output: Output
    @Environment(\.metrics) private var metrics
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous)
        VStack(spacing: 0) {
            bar
            if showsOutput {
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: TerminalInstanceStack.dividerHeight)
                output
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(shape)
        .onAppear { fieldFocused = true }
        .onChange(of: phase) { _, phase in
            if case .idle = phase { fieldFocused = true }
        }
    }

    /// The palette header's row: its gutters, icon slot and trailing accessory spacing.
    private var bar: some View {
        HStack(spacing: 0) {
            gutter(metrics.spacing.md * 2)
            statusGlyph
                .frame(width: metrics.size.headerIconSlot)
            gutter(metrics.spacing.xl)
            commandArea
                .frame(maxWidth: .infinity, alignment: .leading)
            if isFullScreen {
                Text("Full-screen program · ⌘O opens kitty")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.warning)
                    .lineLimit(1)
                gutter(metrics.spacing.md)
            }
            Text((directory as NSString).abbreviatingWithTildeInPath)
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            gutter(metrics.spacing.md)
            barButton(
                isPinned ? "pin.fill" : "pin.slash",
                help: isPinned ? "Unpin  ⌘P" : "Pin on Top  ⌘P"
            ) { actions.togglePinned() }
            barButton("arrow.up.forward.app", help: "Open in kitty  ⌘O") { actions.openInKitty() }
            barButton("xmark", help: "Close  ⌘W") { actions.close() }
            gutter(metrics.spacing.md * 2)
        }
        .frame(height: metrics.size.compactHeight)
    }

    private func gutter(_ width: CGFloat) -> some View {
        Color.clear.frame(width: width, height: 1)
    }

    @ViewBuilder
    private var commandArea: some View {
        switch phase {
        case .starting where startupNotice != nil:
            Text(startupNotice ?? "")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .starting, .running:
            Text(command)
                .font(metrics.typography.searchField)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .ended:
            Text("Shell ended · ⌘W closes")
                .font(metrics.typography.searchField)
                .foregroundStyle(Theme.Colors.textSecondary)
        case .idle:
            TextField("", text: $input)
                .textFieldStyle(.plain)
                .font(metrics.typography.searchField)
                .tint(Theme.Colors.textPrimary)
                .focused($fieldFocused)
                .background(alignment: .leading) {
                    if input.isEmpty {
                        Text("Next command")
                            .font(metrics.typography.searchField)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(Text("Next command"))
                .onSubmit { actions.submit() }
        }
    }

    /// The palette's magnifier slot; the phase shows in its symbol and colour instead of a border.
    @ViewBuilder
    private var statusGlyph: some View {
        switch phase {
        case .starting, .running:
            ProgressView().controlSize(.small).tint(Color.accentColor)
        case .idle(let status?) where status != 0:
            Text(String(status))
                .font(metrics.typography.keyCap.monospacedDigit())
                .foregroundStyle(Theme.Colors.destructive)
        case .ended:
            glyph("powersleep").foregroundStyle(Theme.Colors.textTertiary)
        case .idle:
            glyph("dollarsign").foregroundStyle(.secondary)
        }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(metrics.typography.headerIcon)
            .symbolRenderingMode(.hierarchical)
    }

    private func barButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        BarButton(chrome: .rounded, isCompact: true, action: action) {
            Image(systemName: symbol)
                .font(metrics.typography.barSymbol)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: metrics.size.barButtonHeight - metrics.spacing.sm * 2)
        }
        .focusable(false)
        .help(help)
        .accessibilityLabel(help)
    }
}
