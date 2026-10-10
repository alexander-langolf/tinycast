import Foundation

/// Elapsed time, in the one place a duration becomes text.
enum CommandDuration {
    static func text(from start: Date, to end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        if seconds < 10 { return String(format: "%.1fs", seconds) }
        if seconds < 60 { return "\(Int(seconds))s" }
        let whole = Int(seconds)
        return "\(whole / 60)m \(whole % 60)s"
    }
}
