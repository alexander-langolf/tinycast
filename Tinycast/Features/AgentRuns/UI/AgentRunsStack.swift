import SwiftUI

struct AgentRunsStack: View {
    @Environment(AgentRunsCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    static let cardLimit = 4

    var body: some View {
        let layout = AgentRunsMetrics(metrics: metrics)
        return VStack(spacing: layout.gap) {
            ForEach(coordinator.runs.prefix(Self.cardLimit)) { run in
                AgentRunCard(run: run) { coordinator.attach(run) }
            }
            if coordinator.runs.count > Self.cardLimit {
                Text("+\(coordinator.runs.count - Self.cardLimit) more")
                    .font(layout.trailingFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.size.barButtonHeight)
                    .background(layout.scrim)
                    .background(GlassEffectView())
                    .clipShape(layout.shape)
                    .overlay { AgentRunCardBorder(layout: layout) }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
