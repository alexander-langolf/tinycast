import CoreGraphics
import Foundation

enum PersistentLauncherGeometry {
    static let restingScale: CGFloat = 0.5
    static let safeGap: CGFloat = 4

    static func resting(screen: CGRect, visible: CGRect, safeTop: CGFloat, header: CGSize) -> CGRect {
        let width = min(header.width * restingScale, visible.width)
        let height = min(header.height * restingScale, visible.height)
        let top = min(visible.maxY, screen.maxY - safeTop) - safeGap
        return CGRect(
            x: min(max(screen.midX - width / 2, visible.minX), visible.maxX - width),
            y: max(visible.minY, top - height), width: width, height: height)
    }

    static func interpolate(_ from: CGRect, _ to: CGRect, progress: Double) -> CGRect {
        let progress = min(max(progress, 0), 1)
        func mix(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
            start + (end - start) * progress
        }
        let height = mix(from.height, to.height)
        return CGRect(
            x: mix(from.minX, to.minX), y: mix(from.maxY, to.maxY) - height,
            width: mix(from.width, to.width), height: height)
    }

    static func aligned(_ frame: CGRect, backingScale: CGFloat) -> CGRect {
        let backingScale = max(backingScale, 1)
        return CGRect(
            x: (frame.minX * backingScale).rounded() / backingScale,
            y: floor(frame.maxY * backingScale) / backingScale - frame.height,
            width: frame.width, height: frame.height)
    }

    static func display(held: String?, available: [String], preferred: String?) -> String? {
        if let held, available.contains(held) { return held }
        if let preferred, available.contains(preferred) { return preferred }
        return available.first
    }
}
