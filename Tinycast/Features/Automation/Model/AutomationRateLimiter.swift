import Foundation

/// A token bucket with the clock passed in, so a harness can drive time.
struct AutomationRateLimiter: Sendable {
    let capacity: Double
    let refillPerSecond: Double
    private var tokens: Double
    private var updated: Date?

    init(capacity: Int, perSecond: Double) {
        self.capacity = Double(capacity)
        refillPerSecond = perSecond
        tokens = Double(capacity)
    }

    mutating func take(at now: Date) -> Bool {
        if let updated {
            let elapsed = max(0, now.timeIntervalSince(updated))
            tokens = min(capacity, tokens + elapsed * refillPerSecond)
        }
        updated = now
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}
