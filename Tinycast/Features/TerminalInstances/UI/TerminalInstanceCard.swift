import SwiftUI

/// What the card's buttons and return key do; previews pass the defaults.
struct TerminalInstanceActions {
    var submit: () -> Void = {}
    var togglePinned: () -> Void = {}
    var openInTerminal: () -> Void = {}
    var browseHere: () -> Void = {}  // FORK: file-navigator
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
    var isEditor = false  // FORK: file-navigator
    @ViewBuilder let output: Output
    @Environment(\.metrics) private var metrics
    @Environment(\.forkColorPreview) private var preview
    @FocusState private var fieldFocused: Bool

    // FORK: file-navigator
    private var layout: TerminalInstanceMetrics {
        TerminalInstanceMetrics(metrics: metrics, isEditor: isEditor)
    }
    private var ink: ForkInk { ForkInk(preview) }

    var body: some View {
        let layout = layout
        let ink = ink
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        VStack(spacing: 0) {
            bar(layout)
            if showsOutput {
                if layout.dividerHeight > 0 {
                    Rectangle()
                        .fill(ink.separator)
                        .frame(height: layout.dividerHeight)
                }
                output
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { Rectangle().fill(ink.terminalScrim).allowsHitTesting(false) }
        .background { GlassEffectView().allowsHitTesting(false) }
        .clipShape(shape)
        .onAppear { fieldFocused = true }
        .onChange(of: phase) { _, phase in
            if case .idle = phase { fieldFocused = true }
        }
    }

    /// The palette header's row: its gutters, icon slot and trailing accessory spacing.
    private func bar(_ layout: TerminalInstanceMetrics) -> some View {
        HStack(spacing: 0) {
            gutter(layout.gutter)
            statusGlyph
                .frame(width: metrics.size.headerIconSlot)
            gutter(metrics.spacing.xl)
            commandArea
                .frame(maxWidth: .infinity, alignment: .leading)
            if isFullScreen {
                Text("Full-screen program · ⌘O opens Ghostty")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(ink.warning)
                    .lineLimit(1)
                gutter(metrics.spacing.md)
            }
            Text((directory as NSString).abbreviatingWithTildeInPath)
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(ink.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
            gutter(metrics.spacing.md)
            barButton(
                isPinned ? "pin.fill" : "pin.slash",
                help: isPinned ? "Unpin  ⌘P" : "Pin on Top  ⌘P"
            ) { actions.togglePinned() }
            barButton("folder", help: "Browse here") { actions.browseHere() }  // FORK: file-navigator
            barButton("arrow.up.forward.app", help: "Open in Ghostty  ⌘O") { actions.openInTerminal() }
            barButton("xmark", help: "Close  ⌘W") { actions.close() }
            gutter(layout.gutter)
        }
        .frame(height: layout.barHeight)
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
                .foregroundStyle(ink.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .starting, .running:
            Text(command)
                .font(metrics.typography.searchField)
                .foregroundStyle(ink.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .ended:
            Text("Shell ended · ⌘W closes")
                .font(metrics.typography.searchField)
                .foregroundStyle(ink.textSecondary)
        case .idle:
            TextField("", text: $input)
                .textFieldStyle(.plain)
                .font(metrics.typography.searchField)
                .tint(ink.textPrimary)
                .focused($fieldFocused)
                .background(alignment: .leading) {
                    if input.isEmpty {
                        Text("Next command")
                            .font(metrics.typography.searchField)
                            .foregroundStyle(ink.textTertiary)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(Text("Next command"))
                .onSubmit { actions.submit() }
        }
    }

    /// Shells report a signal as 128 + its number; only these mean the program crashed or was killed.
    /// Any other non-zero exit is often a normal answer (`brew outdated`, `grep` with no match, `diff`).
    static func crashSignal(_ status: Int32) -> String? {
        [132: "SIGILL", 134: "SIGABRT", 136: "SIGFPE", 137: "SIGKILL", 138: "SIGBUS", 139: "SIGSEGV"][status]
    }

    /// The palette's magnifier slot; the phase shows in its symbol and colour instead of a border.
    @ViewBuilder
    private var statusGlyph: some View {
        switch phase {
        case .starting, .running:
            ProgressView().controlSize(.small).tint(ink.accent)
        case .idle(let status?) where status != 0:
            let crash = Self.crashSignal(status)
            glyph(crash == nil ? "exclamationmark.circle" : "xmark.octagon")
                .foregroundStyle(crash == nil ? ink.textSecondary : ink.error)
                .help(crash.map { "Killed by \($0) (status \(status))" } ?? "Exited with status \(status)")
        case .ended:
            glyph("powersleep").foregroundStyle(ink.textTertiary)
        case .idle:
            glyph("dollarsign").foregroundStyle(ink.textSecondary)
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
                .foregroundStyle(ink.textSecondary)
                .frame(width: metrics.size.barButtonHeight - metrics.spacing.sm * 2)
        }
        .focusable(false)
        .help(help)
        .accessibilityLabel(help)
    }
}
