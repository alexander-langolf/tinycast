import AppKit
import QuartzCore
import SwiftUI

@MainActor @Observable
final class PersistentLauncherCoordinator: NSObject {
    @ObservationIgnored private unowned let core: AppCore
    private(set) var policy = PersistentLauncherPolicy()
    private(set) var scale: CGFloat = PersistentLauncherGeometry.restingScale
    private(set) var surfaceWidth: CGFloat = 0
    private(set) var showsStatus = true
    private(set) var frozenStatus: GhosttyStatusState?
    private(set) var headerImage: NSImage?
    private(set) var headerSize: CGSize = .zero
    @ObservationIgnored private var panel: PersistentLauncherPanel?
    @ObservationIgnored private var overflowPanel: PersistentLauncherPanel?
    @ObservationIgnored private var outsideMonitor: Any?
    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private let tooltip = GhosttyStatusTooltipPresenter()
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
        core.ghosttyStatus.onChange = { [weak self] in self?.reconcileOverflow() }
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
                    dismissStatusAccessories()
                    if policy.isActive { core.paletteCoordinator.hidePalette(restoreFocus: false) }
                    stopFlight()
                    panel?.orderOut(nil)
                case NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                    NSWorkspace.sessionDidBecomeActiveNotification:
                    suspended = false
                    onGeometryChange?()
                    reconcile()
                default:
                    dismissStatusAccessories()
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
        let accepted = policy.summon()
        if accepted {
            frozenStatus = core.ghosttyStatus.state
            core.ghosttyStatus.setResting(false)
            tooltip.hide()
        }
        return accepted
    }
    func dismiss() -> Bool { policy.dismiss() }

    func activate() {
        guard !suspended, policy.phase == .resting || policy.phase == .closing else { return }
        invocationScreen = selectedScreen()
        core.paletteCoordinator.showPalette(mode: .launcher)
    }

    func open(_ active: PalettePanel) {
        guard started, !suspended, policy.isActive, let panel else { return }
        core.ghosttyStatus.setResting(false)
        closeOverflow()
        tooltip.hide()
        activePanel = active
        let screen = active.screen ?? invocationScreen ?? preferredScreen()
        invocationScreen = nil
        let crossDisplay = screen?.displayKey != displayKey
        displayKey = screen?.displayKey
        if crossDisplay || policy.phase == .active {
            if let screen { place(at: travellingResting(on: screen)) }
        } else if flight == nil, let screen {
            place(at: travellingResting(on: screen))
        }
        setRenderingHidden(true, on: active)
        captureHeader()
        showsStatus = false
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
        activePanel = active ?? activePanel
        captureHeader()
        frozenStatus = core.ghosttyStatus.state
        showsStatus = false
        tooltip.hide()
        activePanel = nil
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        if let screen = selectedScreen() { move(to: travellingResting(on: screen)) }
    }

    func reconcile() {
        guard started, !suspended, policy.phase != .stopped else { return }
        if let activePanel, policy.isActive {
            if policy.phase == .opening {
                if let screen = activePanel.screen, screen.displayKey != displayKey {
                    displayKey = screen.displayKey
                    place(at: travellingResting(on: screen))
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
        if relocated {
            place(at: policy.phase == .closing ? travellingResting(on: screen) : resting(on: screen))
        }
        if policy.phase == .closing {
            policy.retarget()
            move(to: travellingResting(on: screen))
        } else {
            headerImage = nil
            showsStatus = true
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
            header: CGSize(width: metrics.size.panelWidth, height: metrics.size.compactHeight),
            restingHeight: GhosttyStatusMetrics(metrics: metrics).restingHeight)
    }

    private func activeHeaderFrame(_ active: NSPanel) -> CGRect {
        CGRect(
            x: active.frame.minX, y: active.frame.maxY - metrics.size.compactHeight,
            width: metrics.size.panelWidth, height: metrics.size.compactHeight)
    }

    private func travellingResting(on screen: NSScreen) -> CGRect {
        PersistentLauncherGeometry.travellingResting(
            status: resting(on: screen),
            header: CGSize(width: metrics.size.panelWidth, height: metrics.size.compactHeight),
            visible: screen.visibleFrame)
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
        flight = Flight(
            identity: identity, from: panel.frame, to: frame, start: CACurrentMediaTime())
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
        surfaceWidth = frame.width
        panel?.setFrame(frame, display: true)
    }

    private func finish(_ identity: UInt64) {
        guard identity == policy.identity else { return }
        stopFlight()
        policy.complete(identity)
        frozenStatus = nil
        if policy.isActive {
            panel?.orderOut(nil)
            if let activePanel { setRenderingHidden(false, on: activePanel) }
            onSettled?()
        } else {
            if let screen = selectedScreen() { place(at: resting(on: screen)) }
            showsStatus = true
            panel?.ignoresMouseEvents = false
            core.ghosttyStatus.setResting(true)
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
        closeOverflow()
        tooltip.hide()
        core.ghosttyStatus.onChange = nil
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

    var isOverflowVisible: Bool { overflowPanel != nil }

    func dismissStatusAccessories() {
        closeOverflow()
        tooltip.hide()
    }

    func toggleOverflow() {
        guard policy.phase == .resting, !suspended else { return }
        if overflowPanel != nil { closeOverflow(); return }
        overflowPanel = PersistentLauncherPanel()
        reconcileOverflow()
        guard overflowPanel != nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            Task { @MainActor [weak self] in self?.closeOverflow() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown])
        { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .keyDown && event.keyCode == 53 {
                    self.dismissStatusAccessories()
                } else if event.type != .keyDown, event.window !== self.overflowPanel,
                    event.window !== self.panel
                {
                    self.dismissStatusAccessories()
                }
            }
            return event
        }
    }

    private func reconcileOverflow() {
        guard let overflow = overflowPanel, let panel else { return }
        let layout = GhosttyStatusMetrics(metrics: metrics)
        let visible = visibleTabCount(width: panel.frame.width)
        let count = core.ghosttyStatus.tabs.count - visible
        guard policy.phase == .resting, !suspended, count > 0 else { closeOverflow(); return }
        let screen = panel.screen?.visibleFrame ?? panel.frame
        let width = min(max(panel.frame.width, layout.cardWidth + layout.inset * 2), screen.width)
        let height = min(
            CGFloat(count) * (layout.rowHeight + layout.gap) + layout.inset * 2,
            layout.overflowMaxHeight, max(layout.rowHeight, panel.frame.minY - screen.minY - layout.gap))
        overflow.setFrame(
            CGRect(
                x: min(max(panel.frame.minX, screen.minX), screen.maxX - width),
                y: panel.frame.minY - height - layout.gap, width: width, height: height), display: true)
        let root = AnyView(
            OverflowList(
                coordinator: core.ghosttyStatus,
                visibleCount: visible, width: width, metrics: metrics,
                tooltip: { [weak self] text, frame in self?.hover(text, frame: frame, in: self?.overflowPanel)
                },
                close: { [weak self] in self?.closeOverflow() }
            ).forkAppearance())
        if let hosting = overflow.contentView as? NSHostingView<AnyView> {
            hosting.rootView = root
        } else {
            overflow.contentView = NSHostingView(rootView: root)
        }
        overflow.orderFrontRegardless()
    }

    private func visibleTabCount(width: CGFloat) -> Int {
        let layout = GhosttyStatusMetrics(metrics: metrics)
        let generic: Bool
        if case .loaded(let inventory) = core.ghosttyStatus.state {
            generic = inventory.capability == .tabsOnly
        } else {
            generic = false
        }
        return layout.fit(
            count: core.ghosttyStatus.tabs.count,
            width: width - (generic ? layout.icon + layout.gap : 0)
        ).visibleCount
    }

    private func hover(_ text: String?, frame: CGRect, in panel: PersistentLauncherPanel?) {
        guard policy.phase == .resting, !suspended, let panel else { tooltip.hide(); return }
        let screenFrame = CGRect(
            x: panel.frame.minX + frame.minX, y: panel.frame.maxY - frame.maxY,
            width: frame.width, height: frame.height)
        tooltip.hover(text, anchor: screenFrame, metrics: metrics)
    }

    private func closeOverflow() {
        tooltip.hide()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        outsideMonitor = nil
        localMonitor = nil
        overflowPanel?.orderOut(nil)
        overflowPanel?.contentView = nil
        overflowPanel = nil
    }

    private struct OverflowList: View {
        let coordinator: GhosttyStatusCoordinator
        let visibleCount: Int
        let width: CGFloat
        let metrics: InterfaceMetrics
        let tooltip: (String?, CGRect) -> Void
        let close: () -> Void

        var body: some View {
            let layout = GhosttyStatusMetrics(metrics: metrics)
            ScrollView {
                VStack(spacing: layout.gap) {
                    ForEach(coordinator.tabs.dropFirst(visibleCount)) { tab in
                        GhosttyStatusCard(
                            tab: tab, agent: tab.agentKind(associations: coordinator.associations),
                            icon: coordinator.applicationIcon, height: layout.rowHeight,
                            width: width - layout.inset * 2, tooltip: tooltip
                        ) {
                            coordinator.select(tab)
                            close()
                        }
                    }
                }
                .padding(layout.inset)
            }
            .environment(\.metrics, metrics)
            .background(ForkTheme.current.paletteScrim)
            .background(GlassEffectView())
        }
    }

    private struct Surface: View {
        unowned let owner: PersistentLauncherCoordinator

        var body: some View {
            let width =
                owner.surfaceWidth > 0 ? owner.surfaceWidth : owner.metrics.size.panelWidth * owner.scale
            let height = owner.metrics.size.compactHeight * owner.scale
            ZStack {
                Group {
                    if let image = owner.headerImage {
                        Image(nsImage: image).resizable().frame(
                            width: owner.headerSize.width, height: owner.headerSize.height)
                    }
                }
                .scaleEffect(owner.scale)
                .frame(width: width, height: height)
                .opacity(owner.showsStatus ? 0 : 1)
                GhosttyStatusBar(
                    coordinator: owner.core.ghosttyStatus,
                    state: owner.frozenStatus ?? owner.core.ghosttyStatus.state,
                    width: min(
                        owner.metrics.size.panelWidth * PersistentLauncherGeometry.restingScale, width),
                    height: GhosttyStatusMetrics(metrics: owner.metrics).restingHeight,
                    openLauncher: { [weak owner] in owner?.activate() },
                    showOverflow: { [weak owner] in owner?.toggleOverflow() },
                    tooltip: { [weak owner] text, frame in owner?.hover(text, frame: frame, in: owner?.panel)
                    }
                )
                .opacity(owner.showsStatus ? 1 : 0)
                .allowsHitTesting(owner.policy.phase == .resting)
                .environment(\.metrics, owner.metrics)
            }
            .frame(width: width, height: height)
            .accessibilityHidden(owner.policy.isActive)
        }
    }
}
