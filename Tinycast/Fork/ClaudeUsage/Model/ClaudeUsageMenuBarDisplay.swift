import Foundation

enum ClaudeUsageMenuBarDisplay: String, Codable, CaseIterable, Sendable {
    case disabled
    case usageIcon
    case sessionPercent
    case sessionAndWeek

    var title: String {
        switch self {
        case .disabled: String(localized: "Disabled")
        case .usageIcon: String(localized: "Usage Icon")
        case .sessionPercent: String(localized: "Session Percent")
        case .sessionAndWeek: String(localized: "Session and Week")
        }
    }
}
