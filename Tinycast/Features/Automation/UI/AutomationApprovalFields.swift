import SwiftUI

/// The approval dialog's body: one labelled block per field, never one joined string, so a value
/// cannot pass for another line of the dialog.
struct AutomationApprovalFields: View {
    @Environment(\.metrics) private var metrics
    let presentation: AutomationApprovalPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.lg) {
            ForEach(presentation.fields) { field in
                VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                    Text(field.label)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(verbatim: field.value)
                        .font(metrics.typography.code)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(metrics.spacing.md)
                        .background(
                            Theme.Colors.controlSurface,
                            in: RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(field.label): \(field.value)")
            }
        }
    }
}
