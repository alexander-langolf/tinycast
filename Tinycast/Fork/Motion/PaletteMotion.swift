import AppKit
import SwiftUI

/// The palette's motion tokens: every animated presentation change reads its numbers here.
enum PaletteMotion {
    /// One block's entrance: `order` staggers it after the window starts, `offset` is where it starts.
    struct Reveal: Equatable, Sendable {
        var order: Int
        var offset: CGSize

        /// The header's leading glyph and placeholder: a cross-fade in place.
        static let glyph = Reveal(order: 0, offset: .zero)
        /// Controls joining the header's trailing edge.
        static let accessory = Reveal(order: 1, offset: CGSize(width: 8, height: 0))
        static let body = Reveal(order: 2, offset: CGSize(width: 0, height: 14))
        static let footer = Reveal(order: 3, offset: CGSize(width: 0, height: 8))

        var delay: TimeInterval { Double(order) * PaletteMotion.stagger }
    }

    /// The window's resize: no bounce, so the bottom edge settles without overshooting.
    static let handoffDuration: TimeInterval = 0.34
    static let windowSpring = Spring(duration: 0.34, bounce: 0)
    /// A shrink waits this long, so the body and footer have faded before the edge passes them.
    static let collapseDelay: TimeInterval = 0.08
    static let stagger: TimeInterval = 0.035
    static let revealDuration: TimeInterval = 0.28
    static let revealCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.2, y: 0.8), endControlPoint: UnitPoint(x: 0.2, y: 1))
    static let fadeDuration: TimeInterval = 0.15
    static let exit = Animation.easeIn(duration: 0.1)

    @MainActor static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
