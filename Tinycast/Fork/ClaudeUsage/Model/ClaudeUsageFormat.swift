import Foundation

enum ClaudeUsageFormat: Sendable {
    static func label(snapshot: ClaudeUsageSnapshot?, display: ClaudeUsageMenuBarDisplay,
        locale: Locale) -> String
    {
        guard let snapshot, let session = snapshot.session else { return "" }
        switch display {
        case .disabled, .usageIcon:
            return ""
        case .sessionPercent:
            return percent(session.percent, locale: locale)
        case .sessionAndWeek:
            guard let weekly = snapshot.weekly else {
                return percent(session.percent, locale: locale)
            }
            return "\(percent(session.percent, locale: locale)) · \(percent(weekly.percent, locale: locale))"
        }
    }

    static func percent(_ value: Double, locale: Locale) -> String {
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        return (rounded / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    static func windowTitle(_ window: ClaudeUsageSnapshot.Window, locale: Locale) -> String {
        switch window.kind {
        case "session": String(localized: "Session", locale: locale)
        case "weekly_all": String(localized: "Weekly (all models)", locale: locale)
        case "weekly_scoped":
            if let modelName = window.modelName {
                String(localized: "\(modelName) weekly", locale: locale)
            } else {
                window.kind
            }
        default: window.kind
        }
    }

    static func reset(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
            locale: locale, timeZone: timeZone))
    }

    static func updated(_ date: Date, now: Date, locale: Locale) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        return String(localized: "Updated \(minutes) min ago", locale: locale)
    }
}
