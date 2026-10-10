import Foundation

enum AutomationApprovalVerdict: Equatable, Sendable {
    case allowed
    case denied
    case expired
    case cancelled
    case tooMany
}
