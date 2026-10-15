import Foundation

/// One row of Chrome's `urls` table.
struct ChromeHistoryEntry: Sendable, Hashable {
    let title: String
    let url: URL
    let visitCount: Int
    let lastVisit: Date

    /// Chrome stores times as microseconds since 1601-01-01 UTC.
    static func date(webKitMicroseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(webKitMicroseconds) / 1_000_000 - 11_644_473_600)
    }
}
