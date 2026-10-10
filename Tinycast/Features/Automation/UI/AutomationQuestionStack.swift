import SwiftUI

/// What agents are waiting to ask: each card names the client that asked, which is the token's
/// label and so cannot be claimed by the question's own text.
struct AutomationQuestionStack: View {
    @Environment(\.metrics) private var metrics
    let store: AutomationQuestionStore

    static let cardLimit = 3

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            ForEach(store.pending.prefix(Self.cardLimit)) { question in
                card(question)
            }
            if store.pending.count > Self.cardLimit {
                Text("+\(store.pending.count - Self.cardLimit) more")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private func card(_ question: AutomationQuestion) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            Text("\(question.clientLabel) needs you")
                .font(metrics.typography.keyCap)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(question.text)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: metrics.spacing.sm) {
                ForEach(question.choices, id: \.self) { choice in
                    DialogChip(title: choice, selected: false) {
                        store.answer(question.id, with: choice)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(metrics.spacing.xl)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(question.clientLabel) asks: \(question.text)")
    }
}
