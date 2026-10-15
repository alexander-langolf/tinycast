import CoreGraphics
import Foundation

@main
struct NotchTests {
    static func main() {
        geometry()
        policy()
        entry()
        backdrop()
    }

    static func elementCount(_ path: CGPath) -> Int {
        var count = 0
        path.applyWithBlock { _ in count += 1 }
        return count
    }

    static func geometry() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let content = CGSize(width: 340, height: 44)
        let notched = NotchGeometry(
            screen: screen, safeAreaTop: 32, auxiliaryLeftMaxX: 656, auxiliaryRightMinX: 856,
            content: content)
        precondition(!notched.isVirtual)
        precondition(notched.collapsed == CGSize(width: 200, height: 32), "collapsed matches the notch")
        precondition(notched.expanded == CGSize(width: 340, height: 76))
        precondition(notched.panel.maxY == screen.maxY, "flush with the screen top")
        precondition(notched.panel.midX == 756, "centred on the notch")
        precondition(notched.contentTop == 32)

        let flat = NotchGeometry(
            screen: screen, safeAreaTop: 0, auxiliaryLeftMaxX: nil, auxiliaryRightMinX: nil, content: content)
        precondition(flat.isVirtual && flat.collapsed.height == 0, "virtual notch collapses to nothing")
        precondition(flat.collapsed.width == NotchGeometry.virtualWidth)
        precondition(flat.panel.midX == screen.midX)
        precondition(flat.expanded.height == NotchGeometry.nominalMenuBarHeight + 44)

        let offset = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let external = NotchGeometry(
            screen: offset, safeAreaTop: 0, auxiliaryLeftMaxX: nil, auxiliaryRightMinX: nil, content: content)
        precondition(external.panel.midX == offset.midX && external.panel.maxY == offset.maxY)

        let tiny = CGRect(x: 0, y: 0, width: 300, height: 60)
        let clamped = NotchGeometry(
            screen: tiny, safeAreaTop: 0, auxiliaryLeftMaxX: nil, auxiliaryRightMinX: nil, content: content)
        precondition(tiny.contains(clamped.panel), "panel stays inside a small display")

        let inverted = NotchGeometry(
            screen: screen, safeAreaTop: 32, auxiliaryLeftMaxX: 900, auxiliaryRightMinX: 800, content: content
        )
        precondition(inverted.isVirtual, "inconsistent auxiliary areas fall back to the virtual notch")

        for geometry in [notched, flat, external, clamped] {
            let from = geometry.path(expanded: false)
            let to = geometry.path(expanded: true)
            precondition(elementCount(from) == elementCount(to), "paths interpolate")
            precondition(
                CGRect(origin: .zero, size: geometry.panel.size).contains(to.boundingBoxOfPath),
                "expanded shape fits its panel")
        }
        precondition(
            abs(notched.path(expanded: true).boundingBoxOfPath.width - notched.panel.width) < 0.001,
            "the flared top spans the whole panel")
    }

    static func policy() {
        var policy = NotchPolicy()
        precondition(policy.target == .expanded)
        precondition(!policy.expand(), "already expanded")
        let initial = policy.identity
        precondition(policy.retract())
        precondition(!policy.accepts(initial), "reversal invalidates the older transition")
        let retracting = policy.identity
        precondition(!policy.retract(), "duplicate retract is a no-op")
        precondition(policy.expand())
        precondition(!policy.accepts(retracting), "stale completion is rejected")
        precondition(policy.accepts(policy.identity))
        policy.stop()
        precondition(!policy.accepts(policy.identity) && !policy.retract() && !policy.expand())
        policy = NotchPolicy()
        precondition(policy.target == .expanded && policy.retract(), "a hide resets to a usable policy")
    }

    static func entry() {
        let app = GhosttyApplicationIdentity(processID: 1, launchedAt: Date(timeIntervalSince1970: 0))
        func tab(
            _ id: String, title: String?, directory: String?, selected: Bool = false
        ) -> GhosttyTabSnapshot {
            GhosttyTabSnapshot(
                id: .init(application: app, windowID: "w", tabID: id), title: title,
                terminals: [.init(id: "t\(id)", workingDirectory: directory)], focusedTerminalID: "t\(id)",
                isSelected: selected)
        }
        func loaded(
            _ tabs: [GhosttyTabSnapshot], _ associations: [GhosttyTerminalIdentity: GhosttyAgentKind] = [:]
        ) -> GhosttyStatusState {
            .loaded(
                GhosttyTabInventory(
                    application: app, tabs: tabs, readAt: Date(timeIntervalSince1970: 0),
                    capability: .verifiedProcesses, associations: associations))
        }

        let shell = NotchEntry.make(
            state: loaded([
                tab("1", title: "first", directory: "/a/one"),
                tab("2", title: "  build  ", directory: "/work/tinycast", selected: true)
            ]))
        precondition(shell == NotchEntry(icon: .ghostty, title: "build", subtitle: "tinycast"))

        let first = NotchEntry.make(state: loaded([tab("1", title: nil, directory: nil)]))
        precondition(first == NotchEntry(icon: .ghostty, title: "Terminal", subtitle: "Terminal"))

        let identity = GhosttyTerminalIdentity(
            tab: .init(application: app, windowID: "w", tabID: "1"), terminalID: "t1")
        let claude = NotchEntry.make(
            state: loaded([tab("1", title: "agent", directory: "/x/y", selected: true)], [identity: .claude]))
        precondition(claude.icon == .claude)
        let codex = NotchEntry.make(
            state: loaded([tab("1", title: "agent", directory: "/x/y")], [identity: .codex]))
        precondition(codex.icon == .codex)
        let misleading = NotchEntry.make(
            state: loaded([tab("1", title: "claude code", directory: "/claude")]))
        precondition(misleading.icon == .ghostty, "titles never identify an agent")

        for state in [GhosttyStatusState.closed, .unavailable, .empty, .permissionRequired] {
            let neutral = NotchEntry.make(state: state)
            precondition(neutral.icon == .ghostty && neutral.title == "Ghostty")
        }
        precondition(NotchEntry.make(state: loaded([])).subtitle == "No tabs")
    }

    static func backdrop() {
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for row in 0..<4 {
            for column in 0..<4 {
                let index = (row * 4 + column) * 4
                pixels[index] = row == 0 ? 255 : 0
                pixels[index + 1] = column < 2 ? 255 : 0
                pixels[index + 3] = 255
            }
        }
        let top = NotchBackdrop.average(rgba: pixels, width: 4, height: 4, x: 0...1, y: 0...0.25)
        precondition(top == NotchBackdropColor(red: 1, green: 0.5, blue: 0), "top row, whole width")
        let left = NotchBackdrop.average(rgba: pixels, width: 4, height: 4, x: 0...0.5, y: 0...0.25)
        precondition(left == NotchBackdropColor(red: 1, green: 1, blue: 0))
        precondition(NotchBackdrop.average(rgba: [], width: 4, height: 4, x: 0...1, y: 0...1) == nil)
        let wide = NotchBackdrop.imageRange(screen: 0...1, screenAspect: 1, imageAspect: 2, horizontal: true)
        precondition(wide == 0.25...0.75, "a wider image is cropped at the sides")
        let same = NotchBackdrop.imageRange(
            screen: 0...0.5, screenAspect: 2, imageAspect: 2, horizontal: false)
        precondition(same == 0...0.5)
        let tall = NotchBackdrop.imageRange(
            screen: 0...0.1, screenAspect: 2, imageAspect: 1, horizontal: false)
        precondition(tall == 0.25...0.30, "a taller image is cropped top and bottom")
    }
}
