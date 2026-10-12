import AppKit
import QuartzCore
import SwiftUI

@MainActor @Observable
final class PersistentLauncherCoordinator: NSObject {
    @ObservationIgnored private unowned let core: AppCore
    private(set) var policy = PersistentLauncherPolicy()
    private(set) var scale: CGFloat = PersistentLauncherGeometry.restingScale
    private(set) var headerImage: NSImage?
    private(set) var headerSize: CGSize = .zero
    @ObservationIgnored private var panel: PersistentLauncherPanel?
    @ObservationIgnored private weak var activePanel: PalettePanel?
    @ObservationIgnored private var displayKey: String?
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var flight: Flight?
    @ObservationIgnored private var observers: [NotificationToken] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored var onGeometryChange: (() -> Void)?
    @ObservationIgnored var onSettled: (() -> Void)?
    @ObservationIgnored var invocationScreen: NSScreen?

    private struct Flight {
        let identity: UInt64
        let from: CGRect
        let to: CGRect
        let start: CFTimeInterval
    }

    init(core: AppCore) { self.core = core }

    var isActive: Bool { policy.isActive }
    var canShow: Bool { !suspended && policy.phase != .stopped }
    var isTravelling: Bool { policy.phase == .opening || policy.phase == .closing }
    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    func start() {
        guard !started, policy.phase != .stopped else { return }
        started = true
        let panel = PersistentLauncherPanel()
        let hosting = NSHostingView(rootView: Surface(owner: self).forkAppearance())
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        observe(NSApplication.didChangeScreenParametersNotification, center: .default)
        observe(NSWorkspace.activeSpaceDidChangeNotification, center: NSWorkspace.shared.notificationCenter)
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter)
        observe(NSWorkspace.screensDidWakeNotification, center: NSWorkspace.shared.notificationCenter)
        observe(
            NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            center: NSWorkspace.shared.notificationCenter)
        observe(NSWorkspace.willSleepNotification, center: NSWorkspace.shared.notificationCenter)
        observe(NSWorkspace.screensDidSleepNotification, center: NSWorkspace.shared.notificationCenter)
        observe(NSWorkspace.sessionDidResignActiveNotification, center: NSWorkspace.shared.notificationCenter)
        observe(NSWorkspace.sessionDidBecomeActiveNotification, center: NSWorkspace.shared.notificationCenter)
        reconcile()
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, started else { return }
                switch name {
                case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                    NSWorkspace.sessionDidResignActiveNotification:
                    suspended = true
                    if policy.isActive { core.paletteCoordinator.hidePalette(restoreFocus: false) }
                    stopFlight()
                    panel?.orderOut(nil)
                case NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                    NSWorkspace.sessionDidBecomeActiveNotification:
                    suspended = false
                    onGeometryChange?()
                    reconcile()
                default:
                    onGeometryChange?()
                    reconcile()
                }
            }
        }
        observers.append(NotificationToken(token, center: center))
    }

    func summon() -> Bool {
        guard canShow else { return false }
        if !started { start() }
        return policy.summon()
    }
    func dismiss() -> Bool { policy.dismiss() }

    func activate() {
        guard !suspended, policy.phase == .resting || policy.phase == .closing else { return }
        invocationScreen = selectedScreen()
        core.paletteCoordinator.showPalette(mode: .launcher)
    }

    func open(_ active: PalettePanel) {
        guard started, !suspended, policy.isActive, let panel else { return }
        activePanel = active
        let screen = active.screen ?? invocationScreen ?? preferredScreen()
        invocationScreen = nil
        let crossDisplay = screen?.displayKey != displayKey
        displayKey = screen?.displayKey
        if crossDisplay || policy.phase == .active {
            if let screen { place(at: resting(on: screen)) }
        }
        setRenderingHidden(true, on: active)
        captureHeader()
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        move(to: activeHeaderFrame(active))
    }

    func close(from active: PalettePanel?) {
        guard started, !suspended, policy.phase == .closing, let panel else { return }
        if let active, let screen = active.screen {
            displayKey = screen.displayKey
            if flight == nil { place(at: activeHeaderFrame(active)) }
        }
        activePanel = nil
        headerImage = nil
        headerSize = CGSize(width: metrics.size.panelWidth, height: metrics.size.compactHeight)
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        if let screen = selectedScreen() { move(to: resting(on: screen)) }
    }

    func reconcile() {
        guard started, !suspended, policy.phase != .stopped else { return }
        if let activePanel, policy.isActive {
            if policy.phase == .opening {
                if let screen = activePanel.screen, screen.displayKey != displayKey {
                    displayKey = screen.displayKey
                    place(at: resting(on: screen))
                }
                policy.retarget()
                captureHeader()
                move(to: activeHeaderFrame(activePanel))
            }
            return
        }
        guard let screen = selectedScreen() else {
            stopFlight()
            panel?.orderOut(nil)
            return
        }
        let relocated = displayKey != screen.displayKey
        displayKey = screen.displayKey
        if relocated { place(at: resting(on: screen)) }
        headerSize = CGSize(width: metrics.size.panelWidth, height: metrics.size.compactHeight)
        headerImage = nil
        if policy.phase == .closing {
            policy.retarget()
            move(to: resting(on: screen))
        } else {
            place(at: resting(on: screen))
            panel?.ignoresMouseEvents = false
            panel?.orderFrontRegardless()
        }
    }

    func finishOpening() {
        guard policy.phase == .opening, let activePanel else { return }
        place(at: activeHeaderFrame(activePanel))
        finish(policy.identity)
    }

    private func preferredScreen() -> NSScreen? {
        core.settings.openOnCursorScreen ? NSScreen.underCursor : NSScreen.primary
    }

    private func selectedScreen() -> NSScreen? {
        let key = PersistentLauncherGeometry.display(
            held: displayKey, available: NSScreen.screens.map(\.displayKey),
            preferred: preferredScreen()?.displayKey)
        return NSScreen.screens.first { $0.displayKey == key }
    }

    private func resting(on screen: NSScreen) -> CGRect {
        PersistentLauncherGeometry.resting(
            screen: screen.frame, visible: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
            header: CGSize(width: metrics.size.panelWidth, height: metrics.size.compactHeight))
    }

    private func activeHeaderFrame(_ active: NSPanel) -> CGRect {
        CGRect(
            x: active.frame.minX, y: active.frame.maxY - metrics.size.compactHeight,
            width: metrics.size.panelWidth, height: metrics.size.compactHeight)
    }

    private func captureHeader() {
        guard let view = activePanel?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let opacity = view.layer?.opacity
        view.layer?.opacity = 1
        defer {
            if let opacity { view.layer?.opacity = opacity }
            CATransaction.commit()
        }
        let size = CGSize(width: metrics.size.panelWidth, height: metrics.size.compactHeight)
        let rect = CGRect(
            x: 0, y: view.isFlipped ? 0 : view.bounds.height - size.height,
            width: size.width, height: size.height)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
        view.cacheDisplay(in: rect, to: bitmap)
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        headerSize = size
        headerImage = image
    }

    private func setRenderingHidden(_ hidden: Bool, on active: PalettePanel) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        active.alphaValue = 1
        active.contentView?.layer?.opacity = hidden ? 0 : 1
        active.hasShadow = !hidden
        active.ignoresMouseEvents = hidden
        CATransaction.commit()
    }

    private func move(to frame: CGRect) {
        guard let panel else { return }
        let identity = policy.identity
        if PaletteMotion.reduceMotion || panel.frame == frame {
            place(at: frame)
            finish(identity)
            return
        }
        flight = Flight(identity: identity, from: panel.frame, to: frame, start: CACurrentMediaTime())
        guard link == nil else { return }
        let link = panel.displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let flight, flight.identity == policy.identity else { return stopFlight() }
        if PaletteMotion.reduceMotion {
            place(at: flight.to)
            finish(flight.identity)
            return
        }
        let time = link.targetTimestamp - flight.start
        if policy.phase == .opening { captureHeader() }
        guard time < PaletteMotion.handoffDuration else {
            place(at: flight.to)
            finish(flight.identity)
            return
        }
        let progress = PaletteMotion.windowSpring.value(target: 1, initialVelocity: 0, time: max(time, 0))
        place(at: PersistentLauncherGeometry.interpolate(flight.from, flight.to, progress: progress))
    }

    private func place(at frame: CGRect) {
        let frame = PersistentLauncherGeometry.aligned(frame, backingScale: panel?.backingScaleFactor ?? 1)
        scale = frame.height / max(metrics.size.compactHeight, 1)
        panel?.setFrame(frame, display: true)
    }

    private func finish(_ identity: UInt64) {
        guard identity == policy.identity else { return }
        stopFlight()
        policy.complete(identity)
        if policy.isActive {
            panel?.orderOut(nil)
            if let activePanel { setRenderingHidden(false, on: activePanel) }
            onSettled?()
        } else {
            panel?.ignoresMouseEvents = false
        }
        headerImage = nil
        panel?.invalidateShadow()
    }

    private func stopFlight() {
        link?.invalidate()
        link = nil
        flight = nil
    }

    func stop() {
        started = false
        _ = policy.quit()
        stopFlight()
        observers = []
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        headerImage = nil
        activePanel = nil
        invocationScreen = nil
    }

    isolated deinit {
        link?.invalidate()
        panel?.contentView = nil
        panel?.orderOut(nil)
    }

    private struct Surface: View {
        unowned let owner: PersistentLauncherCoordinator

        var body: some View {
            Button(action: { [weak owner] in owner?.activate() }) {
                Group {
                    if let image = owner.headerImage {
                        Image(nsImage: image).resizable().frame(
                            width: owner.headerSize.width, height: owner.headerSize.height)
                    } else {
                        PersistentLauncherHeader(metrics: owner.metrics)
                    }
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ForkTheme.current.points(.paletteCornerRadius, owner.metrics),
                        style: .continuous)
                )
                .scaleEffect(owner.scale)
                .frame(
                    width: owner.metrics.size.panelWidth * owner.scale,
                    height: owner.metrics.size.compactHeight * owner.scale
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: ForkTheme.current.points(.paletteCornerRadius, owner.metrics)
                            * owner.scale, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Tinycast")
            .accessibilityHidden(owner.policy.isActive)
        }
    }
}
