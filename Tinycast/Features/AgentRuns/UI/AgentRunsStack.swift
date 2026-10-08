import SwiftUI

struct AgentRunsStack: View {
    @Environment(AgentRunsCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    static let cardLimit = 4

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            ForEach(coordinator.runs.prefix(Self.cardLimit)) { run in
                AgentRunCard(run: run) { coordinator.attach(run) }
            }
            if coordinator.runs.count > Self.cardLimit {
                Text("+\(coordinator.runs.count - Self.cardLimit) more")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.size.barButtonHeight)
                    .background(PaletteBackground(window: nil))
                    .clipShape(RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
