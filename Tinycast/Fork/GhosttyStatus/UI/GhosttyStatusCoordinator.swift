import AppKit

@MainActor
struct GhosttyStatusDependencies {
    var currentTarget: () -> GhosttyApplicationTarget?
    var read: (GhosttyApplicationTarget) async -> GhosttyStatusState
    var select: (GhosttyTabIdentity, GhosttyApplicationTarget) async -> Bool
    var requestPermission: (GhosttyApplicationTarget) async -> Bool

    static var live: Self {
        .init(
            currentTarget: GhosttyStatusService.currentTarget, read: GhosttyStatusService.read,
            select: { await GhosttyStatusService.select($0, target: $1) },
            requestPermission: GhosttyStatusService.requestPermission)
    }
}

@MainActor
@Observable
final class GhosttyStatusCoordinator {
    private(set) var state: GhosttyStatusState = .closed
    private(set) var applicationIcon: NSImage?
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let dependencies: GhosttyStatusDependencies
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var selection: Task<Void, Never>?
    @ObservationIgnored private var permission: Task<Void, Never>?
    @ObservationIgnored private var observers: [NotificationToken] = []
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var selectionID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var resting = true
    @ObservationIgnored private var suspended = false

    init(dependencies: GhosttyStatusDependencies = .live) { self.dependencies = dependencies }

    var associations: [GhosttyTerminalIdentity: GhosttyAgentKind] {
        if case .loaded(let inventory) = state { return inventory.associations }
        return [:]
    }
    var tabs: [GhosttyTabSnapshot] {
        if case .loaded(let inventory) = state { return inventory.tabs }
        return []
    }
    var canRefresh: Bool { started && resting && !suspended }
    var isReading: Bool { reading != nil }

    func start(observeLifecycle: Bool = true) {
        guard !started else { return }
        started = true
        if observeLifecycle {
            let center = NSWorkspace.shared.notificationCenter
            for name in [
                NSWorkspace.didLaunchApplicationNotification,
                NSWorkspace.didTerminateApplicationNotification,
                NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                NSWorkspace.sessionDidResignActiveNotification,
                NSWorkspace.sessionDidBecomeActiveNotification
            ] {
                let token = center.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] notification in
                    let bundleID =
                        (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication)?.bundleIdentifier
                    Task { @MainActor [weak self] in self?.handle(name: name, bundleID: bundleID) }
                }
                observers.append(NotificationToken(token, center: center))
            }
        }
        reconcilePolling()
    }

    func setResting(_ value: Bool) {
        guard resting != value else { return }
        resting = value
        invalidate()
        reconcilePolling()
    }

    func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        invalidate()
        reconcilePolling()
    }

    private func invalidate() {
        generation &+= 1
        reading?.cancel()
        selection?.cancel()
        permission?.cancel()
        pendingRefresh = canRefresh
    }

    private func reconcilePolling() {
        polling?.cancel()
        polling = nil
        guard canRefresh else { return }
        requestRefresh()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self, canRefresh else { return }
                requestRefresh()
            }
        }
    }

    func requestRefresh() {
        guard canRefresh else { return }
        guard reading == nil else { pendingRefresh = true; return }
        pendingRefresh = false
        guard let target = dependencies.currentTarget() else { publish(.closed); return }
        if case .loaded(let inventory) = state, inventory.application != target.identity { publish(.closed) }
        applicationIcon = NSWorkspace.shared.icon(forFile: target.bundleURL.path)
        let request = generation
        reading = Task { [weak self] in
            guard let self else { return }
            defer {
                reading = nil
                if pendingRefresh && canRefresh { requestRefresh() }
            }
            guard !Task.isCancelled, canRefresh, request == generation else { return }
            let result = await dependencies.read(target)
            guard !Task.isCancelled, canRefresh,
                GhosttyStatusReconciliation.accepts(
                    requestGeneration: request, currentGeneration: generation,
                    requestedApplication: target.identity,
                    currentApplication: dependencies.currentTarget()?.identity)
            else { return }
            publish(result)
        }
    }

    func applicationDidChange(terminated: Bool) {
        guard started else { return }
        invalidate()
        if terminated || dependencies.currentTarget()?.identity != tabs.first?.id.application {
            publish(.closed)
        }
        requestRefresh()
    }

    func select(_ tab: GhosttyTabSnapshot) {
        guard canRefresh, tabs.contains(where: { $0.id == tab.id }),
            let target = dependencies.currentTarget(), target.identity == tab.id.application
        else { return }
        selection?.cancel()
        selectionID &+= 1
        let operation = selectionID
        let request = generation
        selection = Task { [weak self] in
            guard let self, !Task.isCancelled, canRefresh, request == generation else { return }
            let selected = await dependencies.select(tab.id, target)
            guard !Task.isCancelled, operation == selectionID, request == generation else { return }
            selection = nil
            if !selected { requestRefresh() }
        }
    }

    func requestPermission() {
        guard canRefresh, permission == nil, case .permissionRequired = state,
            let target = dependencies.currentTarget()
        else { return }
        let request = generation
        permission = Task { [weak self] in
            guard let self else { return }
            let allowed = await dependencies.requestPermission(target)
            permission = nil
            guard !Task.isCancelled, canRefresh, request == generation,
                dependencies.currentTarget()?.identity == target.identity
            else { return }
            if allowed { requestRefresh() }
        }
    }

    private func publish(_ state: GhosttyStatusState) {
        self.state = state
        onChange?()
    }

    private func handle(name: Notification.Name, bundleID: String?) {
        guard started else { return }
        switch name {
        case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification:
            setSuspended(true)
        case NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification:
            setSuspended(false)
        default:
            guard bundleID == "com.mitchellh.ghostty" else { return }
            applicationDidChange(terminated: name == NSWorkspace.didTerminateApplicationNotification)
        }
    }

    func stop() {
        started = false
        invalidate()
        pendingRefresh = false
        polling?.cancel()
        polling = nil
        observers = []
        publish(.closed)
    }

    isolated deinit {
        polling?.cancel()
        reading?.cancel()
        selection?.cancel()
        permission?.cancel()
    }
}
