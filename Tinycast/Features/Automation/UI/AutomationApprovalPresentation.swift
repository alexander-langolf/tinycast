import Foundation

@MainActor
final class AutomationApprovalPresentation {
    struct Field: Identifiable {
        let id: Int
        let label: String
        let value: String
    }

    static let valueLimit = 1_200

    let request: AutomationApprovalRequest
    var dismiss: (() -> Void)?

    init(request: AutomationApprovalRequest) {
        self.request = request
    }

    /// Each value on its own, with line breaks and invisible characters made visible.
    var fields: [Field] {
        request.details.enumerated().map { index, detail in
            Field(
                id: index, label: detail.label,
                value: AutomationText.visible(detail.value, limit: Self.valueLimit))
        }
    }
}
