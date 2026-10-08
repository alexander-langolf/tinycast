import SwiftUI

struct AgentRunsFooter: View {
    @Environment(AgentRunsCoordinator.self) private var coordinator
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics

    private static let cardLimit = 3

    var body: some View {
        if palette.isVisible, !coordinator.runs.isEmpty {
            VStack(spacing: metrics.spacing.xs) {
                HStack(spacing: metrics.spacing.md) {
                    SectionHeader(title: "Background agents", isFirst: true)
                    if coordinator.runs.count > Self.cardLimit {
                        Text("+\(coordinator.runs.count - Self.cardLimit) more")
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize()
                            .padding(.trailing, metrics.spacing.md)
                    }
                }
                HStack(spacing: metrics.spacing.sm) {
                    ForEach(coordinator.runs.prefix(Self.cardLimit)) { run in
                        AgentRunCard(run: run) { coordinator.attach(run) }
                    }
                }
            }
            .padding(.horizontal, metrics.spacing.md)
            .padding(.bottom, metrics.spacing.md)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
