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

    /// What the resolver reads off-main: the pair overrides, the colour theme and its memo.
    private struct Published {
        var pairs: [Pair: Pair] = [:]
        var theme: ForkColorPalette?
        /// Each upstream pair's themed colour, or nil for a pair the theme leaves alone.
        var themed: [Pair: NSColor?] = [:]
    }

    private static let published = Mutex(Published())

    var accent: Pair?
    var pairs: [Pair: Pair] = [:]
    /// Settings → Appearance → Colours; nil keeps Tinycast's adaptive look.
    var theme: ForkColorPalette?

    /// A theme's accent outranks the source-level one; it is the same in both appearances.
    var effectiveAccent: Pair? {
        guard let theme else { return accent }
        let accent = theme.nsColor(.accent)
        return Pair(dark: accent, light: accent)
    }

    /// A theme pins the app to its base appearance, so glass and vibrancy match its background.
    var appearance: NSAppearance? { theme?.appearance }

    func publish() {
        Self.published.withLock { $0 = Published(pairs: pairs, theme: theme) }
    }

    static func adaptive(dark: NSColor, light: NSColor) -> Color {
        let upstream = Pair(dark: dark, light: light)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                if let themed = themed(upstream) { return themed }
                let pair = published.withLock { $0.pairs[upstream] } ?? upstream
                return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? pair.dark : pair.light
            })
    }

    private static func themed(_ upstream: Pair) -> NSColor? {
        published.withLock { state in
            guard let theme = state.theme else { return nil }
            if let memo = state.themed[upstream] { return memo }
            let color = theme.color(forUpstream: upstream.dark, light: upstream.light)
            state.themed[upstream] = .some(color)
            return color
        }
    }
}
