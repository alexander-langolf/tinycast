import SwiftUI

/// What an empty chat shows on either surface, and why it cannot answer when it cannot.
struct AIEmptyState: View {

    @Environment(\.metrics) private var metrics
    let message: String?
    let canConfigure: Bool
    let onConfigure: () -> Void

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            Image(systemName: "sparkles")
                .font(metrics.typography.placeholderGlyph)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text("Ask anything")
                .font(metrics.typography.rowTitle)
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                if canConfigure {
                    Button("Configure AI", action: onConfigure)
                        .font(metrics.typography.rowTitle)
                }
            } else {
                HStack(spacing: metrics.spacing.sm) {
                    Text("Send a message")
                    KeyCapChip(text: "↵")
                }
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, metrics.spacing.xxl)
    }
}
