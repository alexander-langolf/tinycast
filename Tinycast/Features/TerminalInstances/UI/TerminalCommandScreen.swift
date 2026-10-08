import SwiftUI

/// The launcher's `$ command` answer: one row whose ↵ opens a terminal instance.
struct TerminalCommandScreen: PaletteScreen {
    struct Row: Identifiable {
        let id = "terminal-command"
        let command: String
    }

    let command: String
    let core: AppCore

    var rows: [Row] { command.isEmpty ? [] : [Row(command: command)] }

    var primaryActionTitle: String { "Run in New Terminal" }

    func hasPrimaryAction(at selection: Int) -> Bool { !command.isEmpty }

    func hasActions(at selection: Int) -> Bool { false }

    func activate(at selection: Int) {
        guard !command.isEmpty else { return }
        core.terminalInstances.open(command: command)
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        if command.isEmpty {
            return AnyView(EmptyResults(text: "Type a command to run in a new terminal"))
        }
        return AnyView(TerminalCommandRow(command: command) { activate(at: 0) })
    }
}

private struct TerminalCommandRow: View {
    let command: String
    let onActivate: () -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: metrics.spacing.lg) {
                Image(systemName: "terminal")
                    .font(metrics.typography.menuIcon)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                Text(command)
                    .font(metrics.typography.inlineCode)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: metrics.spacing.md)
                Text("New Terminal")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.horizontal, metrics.spacing.md)
            .padding(.vertical, metrics.spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(Theme.Colors.selection)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isSelected)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.top, metrics.spacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
