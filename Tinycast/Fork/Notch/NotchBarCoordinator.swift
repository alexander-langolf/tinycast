import AppKit

@MainActor
final class NotchBarCoordinator {
    private static let contentSize = CGSize(width: 340, height: 44)

    private unowned let core: AppCore
    private let model = NotchBarModel()
    private var policy = NotchPolicy()
    private var panel: NotchPanel?
    private var surface: NotchSurfaceView?
    private var observers: [NotificationToken] = []
    private var menuBarProbe: NSStatusItem?
    private var appearanceObservation: NSKeyValueObservation?
    private var backdropTask: Task<Void, Never>?
    private var started = false
    private var suspended = false

    init(core: AppCore) { self.core = core }

    func applyEnabled() {
        if core.settings.notchBarEnabled { start() } else { hide() }
    }

    func start() {
        guard !started, policy.target != .stopped else { return }
        started = true
        core.ghosttyStatus.start()
        core.ghosttyStatus.onChange = { [weak self] in self?.refreshEntry() }
        refreshEntry()
        observe(NSApplication.didChangeScreenParametersNotification, center: .default) { [weak self] in
            self?.reconcile()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.activeSpaceDidChangeNotification, center: workspace) { [weak self] in
            self?.refreshBackdrop()
        }
        for name in [
            NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ] {
            observe(name, center: workspace) { [weak self] in self?.setSuspended(true) }
        }
        for name in [
            NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            observe(name, center: workspace) { [weak self] in self?.setSuspended(false) }
        }
        guard let geometry = currentGeometry() else { return }
        let probe = NSStatusBar.system.statusItem(withLength: 0)
        menuBarProbe = probe
        let panel = NotchPanel()
        let surface = NotchSurfaceView(geometry: geometry, model: model)
        panel.contentView = surface
        panel.setFrame(geometry.panel, display: false)
        self.panel = panel
        self.surface = surface
        surface.place(expanded: false)
        let options: NSKeyValueObservingOptions = [.initial, .new]
        appearanceObservation = probe.button?.observe(\.effectiveAppearance, options: options) {
            [weak panel] button, _ in
            let appearance = button.effectiveAppearance
            MainActor.assumeIsolated { panel?.appearance = appearance }
        }
        panel.orderFrontRegardless()
        refreshBackdrop()
        if core.palette.isVisible { sessionDidStart() } else { animate() }
    }

    func sessionDidStart() {
        guard started, policy.retract() else { return }
        core.ghosttyStatus.setResting(false)
        animate()
    }

    func sessionDidEnd() {
        guard started, policy.expand() else { return }
        core.ghosttyStatus.setResting(true)
        refreshBackdrop()
        animate()
    }

    func hide() {
        guard started else { return }
        tearDown()
        core.ghosttyStatus.setResting(true)
        core.ghosttyStatus.stop()
        policy = NotchPolicy()
    }

    func stop() {
        policy.stop()
        tearDown()
    }

    private func tearDown() {
        started = false
        suspended = false
        observers = []
        appearanceObservation = nil
        backdropTask?.cancel()
        if let menuBarProbe { NSStatusBar.system.removeStatusItem(menuBarProbe) }
        menuBarProbe = nil
        surface?.place(expanded: false)
        panel?.orderOut(nil)
        panel = nil
        surface = nil
    }

    private func animate() {
        guard !suspended, let surface else { return }
        let identity = policy.identity
        surface.transition(
            toExpanded: policy.target == .expanded,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ) { [weak self] in self?.policy.accepts(identity) == true }
    }

    private func refreshBackdrop() {
        backdropTask?.cancel()
        guard let screen = NSScreen.primary, let geometry = currentGeometry(), started else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            surface?.setBackdrop(nil)
            return
        }
        backdropTask = Task { [weak self] in
            let sample = await NotchBackdropReader.sample(
                screen: screen, panel: geometry.panel, band: geometry.contentTop)
            guard !Task.isCancelled, let self else { return }
            surface?.setBackdrop(
                sample.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) })
        }
    }

    private func refreshEntry() {
        model.entry = NotchEntry.make(state: core.ghosttyStatus.state)
        model.applicationIcon = core.ghosttyStatus.applicationIcon
    }

    private func setSuspended(_ value: Bool) {
        guard started, suspended != value else { return }
        suspended = value
        if value {
            panel?.orderOut(nil)
        } else {
            reconcile()
            panel?.orderFrontRegardless()
        }
    }

    private func reconcile() {
        guard started, !suspended, let panel, let surface, let geometry = currentGeometry() else {
            return
        }
        panel.setFrame(geometry.panel, display: true)
        surface.apply(geometry, expanded: policy.target == .expanded)
        refreshBackdrop()
    }

    private func currentGeometry() -> NotchGeometry? {
        guard let screen = NSScreen.primary else { return nil }
        return NotchGeometry(
            screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftMaxX: screen.auxiliaryTopLeftArea?.maxX,
            auxiliaryRightMinX: screen.auxiliaryTopRightArea?.minX, content: Self.contentSize)
    }

    private func observe(
        _ name: Notification.Name, center: NotificationCenter, handler: @escaping @MainActor () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in handler() }
        }
        observers.append(NotificationToken(token, center: center))
    }
}
