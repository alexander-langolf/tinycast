import Foundation

enum ClaudeUsagePollPolicy: Sendable {
    enum Trigger: Sendable {
        case activation
        case timer
        case wake
        case manual
    }

    static let interval: TimeInterval = 300

    static func isEnabled(inserted: Bool, signedIn: Bool) -> Bool {
        inserted && signedIn
    }

    static func nextPoll(after now: Date) -> Date {
        now.addingTimeInterval(interval)
    }

    static func shouldFetch(trigger: Trigger, inserted: Bool, signedIn: Bool, now: Date,
        nextPoll: Date?, rateLimitedUntil: Date?) -> Bool
    {
        guard isEnabled(inserted: inserted, signedIn: signedIn) else { return false }
        if let rateLimitedUntil, now < rateLimitedUntil { return false }
        switch trigger {
        case .activation, .wake, .manual:
            return true
        case .timer:
            return nextPoll.map { now >= $0 } ?? false
        }
    }
}
