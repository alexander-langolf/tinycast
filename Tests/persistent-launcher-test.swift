import CoreGraphics
import Foundation

@main
struct PersistentLauncherTests {
    static func main() {
        var policy = PersistentLauncherPolicy()
        precondition(policy.phase == .resting && !policy.isActive)
        precondition(policy.summon(), "first summon starts a session")
        let session = policy.sessionIdentity
        let beforeRetarget = policy.identity
        policy.retarget()
        precondition(policy.sessionIdentity == session, "geometry edits preserve the input session")
        policy.complete(beforeRetarget)
        precondition(policy.phase == .opening, "retarget invalidates the old completion")
        let first = policy.identity
        precondition(!policy.summon(), "repeated summon preserves session")
        precondition(policy.dismiss(), "dismiss tears down once")
        precondition(!policy.dismiss(), "duplicate dismissal has no effects")
        policy.complete(first)
        precondition(policy.phase == .closing, "stale opening cannot win")
        precondition(policy.summon(), "closing reverses into a new session")
        precondition(policy.sessionIdentity != session, "reversal invalidates old focus retries")
        let reversal = policy.identity
        policy.complete(reversal)
        precondition(policy.phase == .active && policy.isActive)
        precondition(policy.dismiss())
        policy.complete(policy.identity)
        precondition(policy.phase == .resting && !policy.isActive)
        precondition(!policy.quit(), "idle quit has no session teardown")
        precondition(!policy.summon(), "quit cannot reopen")
        var activeQuit = PersistentLauncherPolicy()
        precondition(activeQuit.summon())
        precondition(activeQuit.quit())
        activeQuit.complete(activeQuit.identity)
        precondition(activeQuit.phase == .stopped)
        for factor in [1.0, 1.1, 1.2] {
            let size = CGSize(width: 750 * factor, height: 60 * factor)
            let screen = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
            let visible = CGRect(x: -1920, y: 100, width: 1920, height: 1056)
            let rectangular = PersistentLauncherGeometry.resting(
                screen: screen, visible: visible, safeTop: 0, header: size)
            precondition(rectangular.width == size.width * 0.5)
            precondition(rectangular.height == size.height * 0.5)
            precondition(rectangular.midX == screen.midX)
            precondition(rectangular.maxY == visible.maxY - 4)
            let notch = PersistentLauncherGeometry.resting(
                screen: screen, visible: visible, safeTop: 40, header: size)
            precondition(notch.maxY == screen.maxY - 44)
            precondition(visible.contains(notch))
            let active = CGRect(x: -1500, y: 700, width: size.width, height: size.height)
            precondition(
                PersistentLauncherGeometry.interpolate(rectangular, active, progress: 0) == rectangular)
            precondition(PersistentLauncherGeometry.interpolate(rectangular, active, progress: 1) == active)
            let middle = PersistentLauncherGeometry.interpolate(rectangular, active, progress: 0.5)
            precondition(abs(middle.width / size.width - middle.height / size.height) < 0.00001)
        }
        let fractional = CGRect(x: 10.3, y: 100.4, width: 375, height: 30)
        for backing in [1.0, 2.0] {
            let aligned = PersistentLauncherGeometry.aligned(fractional, backingScale: backing)
            precondition(aligned.size == fractional.size, "alignment preserves uniform scale")
            precondition((aligned.minX * backing).rounded() == aligned.minX * backing)
            precondition((aligned.maxY * backing).rounded() == aligned.maxY * backing)
            precondition(aligned.maxY <= fractional.maxY, "alignment cannot cross the safe edge")
        }
        precondition(
            PersistentLauncherGeometry.display(
                held: "gone", available: ["primary", "other"], preferred: "other") == "other")
        precondition(
            PersistentLauncherGeometry.display(
                held: "primary", available: ["primary", "other"], preferred: "other") == "primary")
        precondition(PersistentLauncherGeometry.display(held: nil, available: [], preferred: nil) == nil)
        print("persistent launcher policy and geometry passed")
    }
}
