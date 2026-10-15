import AppKit
import QuartzCore
import SwiftUI

/// Moves the palette window between frames on `PaletteMotion.windowSpring`, one display frame a step.
@MainActor @Observable
final class PaletteFrameAnimator: NSObject {
    /// The height the content lays out at while the window moves, so nothing reflows per frame.
    private(set) var layoutHeight: CGFloat?
    /// The clip's live radius; nil until the first move, when the view's own radius stands.
    private(set) var cornerRadius: CGFloat?

    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var flight: Flight?

    private struct Flight {
        var from: NSRect
        var to: NSRect
        var fromRadius: CGFloat
        var toRadius: CGFloat
        var start: CFTimeInterval
        var initialVelocity: Double

        /// Rounded to device pixels, so the glass and the clip land on the same edge every frame.
        func frame(at progress: Double, scale: CGFloat) -> NSRect {
            func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
                ((from + (to - from) * progress) * scale).rounded() / scale
            }
            let top = mix(from.maxY, to.maxY)
            let height = mix(from.height, to.height)
            return NSRect(
                x: mix(from.minX, to.minX), y: top - height, width: mix(from.width, to.width),
                height: height)
        }

        func radius(at progress: Double) -> CGFloat {
            fromRadius + (toRadius - fromRadius) * progress
        }
    }

    /// Hidden windows, Reduce Motion and unchanged frames jump; a move in flight retargets smoothly.
    func move(_ window: NSWindow, to frame: NSRect, radius: CGFloat) {
        if let flight, flight.to == frame, flight.toRadius == radius { return }
        let current = window.frame
        guard window.isVisible, !PaletteMotion.reduceMotion, current != frame else {
            settle(window, at: frame, radius: radius)
            return
        }
        let now = CACurrentMediaTime()
        let shrinking = frame.height < current.height
        flight = Flight(
            from: current, to: frame, fromRadius: cornerRadius ?? radius, toRadius: radius,
            start: now + (shrinking && flight == nil ? PaletteMotion.collapseDelay : 0),
            initialVelocity: flight.map { carriedVelocity(from: $0, at: now, to: frame, current) } ?? 0)
        layoutHeight = max(layoutHeight ?? current.height, frame.height)
        self.window = window
        guard link == nil else { return }
        let link = window.displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let flight, let window else { return stop() }
        guard window.isVisible else { return settle(window, at: flight.to, radius: flight.toRadius) }
        let time = link.targetTimestamp - flight.start
        guard time > 0 else { return }
        let spring = PaletteMotion.windowSpring
        guard time < spring.settlingDuration else {
            return settle(window, at: flight.to, radius: flight.toRadius)
        }
        let progress = spring.value(target: 1.0, initialVelocity: flight.initialVelocity, time: time)
        window.setFrame(flight.frame(at: progress, scale: window.backingScaleFactor), display: true)
        let radius = flight.radius(at: progress)
        if cornerRadius != radius { cornerRadius = radius }
    }

    /// The old flight's speed, restated as progress toward the new target, so a retarget never stalls.
    private func carriedVelocity(
        from old: Flight, at now: CFTimeInterval, to frame: NSRect, _ current: NSRect
    ) -> Double {
        let time = max(now - old.start, 0)
        let progressVelocity = PaletteMotion.windowSpring.velocity(
            target: 1.0, initialVelocity: old.initialVelocity, time: time)
        let distance = frame.height - current.height
        guard abs(distance) >= 1 else { return 0 }
        return progressVelocity * (old.to.height - old.from.height) / distance
    }

    private func settle(_ window: NSWindow, at frame: NSRect, radius: CGFloat) {
        stop()
        window.setFrame(frame, display: true)
        // The shadow is traced from the content's shape, which only now stopped changing.
        window.invalidateShadow()
        if layoutHeight != nil { layoutHeight = nil }
        if cornerRadius != radius { cornerRadius = radius }
    }

    private func stop() {
        flight = nil
        link?.invalidate()
        link = nil
    }
}
