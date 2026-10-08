import SwiftUI
import Synchronization

nonisolated struct ForkColors {
    struct Pair: Hashable, Sendable {
        let dark: NSColor
        let light: NSColor

        var color: Color {
            Color(
                nsColor: NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                })
        }
    }

    private static let overrides = Mutex<[Pair: Pair]>([:])

    var accent: Pair?
    var pairs: [Pair: Pair] = [:]

    func publish() {
        Self.overrides.withLock { $0 = pairs }
    }

    static func adaptive(dark: NSColor, light: NSColor) -> Color {
        let upstream = Pair(dark: dark, light: light)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let pair = overrides.withLock { $0[upstream] } ?? upstream
                return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? pair.dark : pair.light
            })
    }
}
