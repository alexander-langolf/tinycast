import SwiftUI

struct AgentRunCard: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.forkColorPreview) private var preview
    let run: AgentRun
    let onAttach: () -> Void
    @State private var hovered = false

    private var agentRunsMetrics: AgentRunsMetrics { AgentRunsMetrics(metrics: metrics) }

    private var canAttach: Bool { run.attach.map { !$0.isEmpty } ?? false }

    private func stateColor(_ ink: ForkInk) -> Color {
        switch run.state {
        case "working": ink.accent
        case "blocked": ink.warning
        default: ink.textTertiary
        }
    }

    /// Subagents carry no kind label: the model alone says what is working.
    private var kindLabel: String? {
        switch run.agent {
        case .claude: "Claude"
        case .subagent: nil
        case .codex: "Codex"
        }
    }

    /// "Opus · medium": the model, with its reasoning effort when the helper reports one.
    private var modelLabel: String? {
        guard let model = run.model, !model.isEmpty else { return nil }
        guard let effort = run.effort, !effort.isEmpty else { return model }
        return "\(model) · \(effort)"
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
        let layout = agentRunsMetrics
        let theme = layout.theme
        let ink = ForkInk(preview, theme: theme)
        return HStack(spacing: metrics.spacing.lg) {
            HStack(spacing: layout.dotGap) {
                Circle()
                    .fill(stateColor(ink))
                    .frame(width: layout.statusDot, height: layout.statusDot)
                    .frame(width: metrics.size.rowIcon)
                    .accessibilityLabel(run.state)
                VStack(alignment: .leading, spacing: 0) {
                    Text(run.name)
                        .font(layout.titleFont)
                        .foregroundStyle(ink.textPrimary)
                    Text(run.last ?? " ")
                        .font(layout.detailFont)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: metrics.spacing.xs) {
                    if let kindLabel { Text(kindLabel) }
                    if let model = modelLabel {
                        Text(model).foregroundStyle(
                            theme.color(.agentCardModelColor)
                                ?? (kindLabel == nil ? ink.textSecondary : ink.textTertiary)
                        )
                    }
                }
                elapsed(from: Date(timeIntervalSince1970: Double(run.startedAt) / 1_000))
            }
            .fixedSize()
        }
        .font(layout.trailingFont)
        .foregroundStyle(ink.textSecondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.cardVerticalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: layout.cardHeight)
        .background(hovered && canAttach ? ink.rowHover : .clear)
        .background(layout.scrim(ink))
        .background(GlassEffectView())
        .clipShape(layout.shape)
        .overlay { AgentRunCardBorder(layout: layout, ink: ink) }
        .contentShape(layout.shape)
        .accessibilityElement(children: .combine)
    }

    private func elapsed(from start: Date) -> some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            Text(CommandDuration.text(from: start, to: context.date))
                .monospacedDigit()
        }
    }
}

/// Drawn over the clip, so the stroke keeps its full width at the corners.
struct AgentRunCardBorder: View {
    let layout: AgentRunsMetrics
    let ink: ForkInk

    var body: some View {
        if layout.theme.flag(.agentCardBorder) {
            layout.shape
                .strokeBorder(
                    layout.theme.color(.agentCardBorderColor) ?? ink.border,
                    lineWidth: layout.theme.points(.agentCardBorderWidth, layout.metrics)
                )
                .allowsHitTesting(false)
        }
    }
}
