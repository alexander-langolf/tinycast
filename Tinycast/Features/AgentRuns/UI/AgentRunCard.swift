import SwiftUI

struct AgentRunCard: View {
    @Environment(\.metrics) private var metrics
    let run: AgentRun
    let onAttach: () -> Void
    @State private var hovered = false

    private var agentRunsMetrics: AgentRunsMetrics { AgentRunsMetrics(metrics: metrics) }

    private var canAttach: Bool { run.attach.map { !$0.isEmpty } ?? false }

    private var stateColor: Color {
        switch run.state {
        case "working": Color.accentColor
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
        .agentRunHover($hovered)
    }

    private var content: some View {
        HStack(spacing: metrics.spacing.lg) {
            Circle()
                .fill(stateColor)
                .frame(width: agentRunsMetrics.statusDot, height: agentRunsMetrics.statusDot)
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
                HStack(spacing: metrics.spacing.xs) {
                    Text(kindLabel)
                    if let model = run.model, !model.isEmpty {
                        Text(model).foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                elapsed(from: Date(timeIntervalSince1970: Double(run.startedAt) / 1_000))
            }
            .fixedSize()
        }
        .font(metrics.typography.rowTrailing)
        .foregroundStyle(Theme.Colors.textSecondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, agentRunsMetrics.cardVerticalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: agentRunsMetrics.cardHeight)
        .background(hovered && canAttach ? Theme.Colors.rowHover : .clear)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func elapsed(from start: Date) -> some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            Text(CommandDuration.text(from: start, to: context.date))
                .monospacedDigit()
        }
    }
}
