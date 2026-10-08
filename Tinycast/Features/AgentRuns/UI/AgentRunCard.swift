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
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            HStack(spacing: metrics.spacing.sm) {
                Circle()
                    .fill(stateColor)
                    .frame(width: metrics.size.agentRunStatusDot, height: metrics.size.agentRunStatusDot)
                    .accessibilityLabel(run.state)
                Text(run.name)
                    .font(metrics.typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: metrics.spacing.sm) {
                Text(kindLabel)
                Spacer(minLength: metrics.spacing.xs)
                Text(Date(timeIntervalSince1970: Double(run.startedAt) / 1_000), style: .timer)
                    .monospacedDigit()
                    .fixedSize()
            }
            Text(run.last ?? " ")
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(run.cwd)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(metrics.typography.rowTrailing)
        .foregroundStyle(Theme.Colors.textTertiary)
        .lineLimit(1)
        .padding(metrics.spacing.md)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.size.agentRunCardHeight)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .fill(hovered && canAttach ? Theme.Colors.rowHover : Theme.Colors.cardFill)
        )
        .contentShape(RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
