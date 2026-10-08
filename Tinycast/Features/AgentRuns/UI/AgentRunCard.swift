import SwiftUI

struct AgentRunCard: View {
    @Environment(\.metrics) private var metrics
    let run: AgentRun
    let onAttach: () -> Void
    @State private var hovered = false

    private var canAttach: Bool { run.attach.map { !$0.isEmpty } ?? false }

    private var stateColor: Color {
        switch run.state {
        case "working": Theme.Colors.accent
        case "blocked": Theme.Colors.warning
        default: Theme.Colors.textTertiary
        }
    }

    private var kindLabel: String {
        switch run.agent {
        case .claude: "Claude"
        case .subagent: "Subagent"
        case .codex: "Codex"
        }
    }

    var body: some View {
        Group {
            if canAttach {
                Button(action: onAttach) { content }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Attach in kitty")
                    .accessibilityHint("Opens this run in a new kitty window")
            } else {
                content
            }
        }
        .armedHover($hovered)
    }

    private var content: some View {
        HStack(spacing: metrics.spacing.lg) {
            Circle()
                .fill(stateColor)
                .frame(width: metrics.size.agentRunStatusDot, height: metrics.size.agentRunStatusDot)
                .frame(width: metrics.size.rowIcon)
                .accessibilityLabel(run.state)
            VStack(alignment: .leading, spacing: 0) {
                Text(run.name)
                    .font(metrics.typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(run.last ?? " ")
                    .font(metrics.typography.keyCap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(kindLabel)
                Text(Date(timeIntervalSince1970: Double(run.startedAt) / 1_000), style: .timer)
                    .monospacedDigit()
            }
            .fixedSize()
        }
        .font(metrics.typography.rowTrailing)
        .foregroundStyle(Theme.Colors.textSecondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, metrics.spacing.xl)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.size.rowIcon + metrics.spacing.sm * 2)
        .background(hovered && canAttach ? Theme.Colors.rowHover : .clear)
        .background(PaletteBackground(window: nil))
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
