import Foundation

/// Elapsed time, in the one place a duration becomes text.
enum CommandDuration {
    static func text(from start: Date, to end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        let duration = Duration.seconds(seconds)
        if seconds < 10 {
            return duration.formatted(
                .units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: 1)))
        }
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds < 60 ? [.seconds] : [.minutes, .seconds]
        return duration.formatted(
            .units(
                allowed: units, width: .narrow, zeroValueUnits: .show(length: 1),
                fractionalPart: .hide(rounded: .down)))
    }
}
