import Foundation
import Observation

@MainActor
@Observable
final class AutomationCoordinator {
    private static let enabledKey = "automationEnabled"

    let clients: AutomationClientStore
    private(set) var server: AutomationHTTPServer?
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored let audit = AutomationAuditLog.standard()
    @ObservationIgnored let hub = AutomationEventHub()
    @ObservationIgnored let questions = AutomationQuestionStore()
    @ObservationIgnored private(set) lazy var questionPresenter = AutomationQuestionPresenter(
        core: core, store: questions)
    @ObservationIgnored private var observationGeneration = 0
    @ObservationIgnored private(set) var approvals: AutomationApprovalQueue
    @ObservationIgnored private(set) var router: AutomationRouter
    @ObservationIgnored private var lastRefusalRecord: Date?
    @ObservationIgnored private var startup: Task<Void, Never>?

    /// Off until the user turns it on, and never carried by a backup or settings.json.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            apply()
        }
    }

    init(core: AppCore) {
        self.core = core
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let clients = AutomationClientStore()
        self.clients = clients
        let approvals = AutomationApprovalQueue(
            isBusy: { [unowned core] in core.isShowingDialog },
            present: { [unowned core] approval in await core.approveAutomation(approval) })
        self.approvals = approvals
        router = AutomationRouter(
            runner: AutomationRunner(core: core, questions: questions),
            audit: audit, approvals: approvals,
            currentCaller: { [clients] caller in
                guard let id = caller.clientID else { return caller }
                return clients.current(id).map(AutomationCaller.client)
            })
        clients.onChange = { [approvals, hub, questions] revoked in
            guard let revoked else { return }
            approvals.cancelAll(for: revoked)
            hub.end(client: revoked)
            questions.removeAll(for: revoked)
        }
        questions.onChange = { [hub] client in
            hub.publish(uri: AutomationOperationCatalog.questions.name, client: client)
        }
        hub.onActivityChange = { [unowned core] active in core.agentRuns.setAutomationHold(active) }
    }

    /// Called once from `AppCore.start()`; a disabled feature touches nothing.
    func start() {
        apply()
    }

    func stop() {
        observationGeneration += 1
        startup?.cancel()
        startup = nil
        server?.stop()
        server = nil
        clients.stopWatchingExpiry()
        approvals.stop()
        hub.endAll()
        questions.stop()
        questionPresenter.stop()
        core.agentRuns.setAutomationHold(false)
    }

    func handleLink(_ url: URL) -> Bool {
        guard isEnabled, let request = AutomationURL.parse(url, channelScheme: Bundle.main.bundleIdentifier)
        else { return false }
        let router = router
        Task {
            _ = await router.route(
                AutomationCall(
                    request: UUID(), caller: .link, operation: request.operation,
                    arguments: request.arguments, transport: "link"))
        }
        return true
    }

    func createClient(
        label: String, scopes: Set<AutomationScope>, lifetime: TimeInterval?
    ) async throws
        -> AutomationClient
    {
        try await clients.create(label: label, scopes: scopes, lifetime: lifetime)
    }

    var endpointURL: String {
        AutomationEndpoint.url(port: AutomationEndpoint.port(bundleIdentifier: Bundle.main.bundleIdentifier))
    }

    private func apply() {
        guard isEnabled else {
            stop()
            return
        }
        guard server == nil else { return }
        let handler = AutomationMCPHandler(
            router: router, hub: hub,
            serverVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
        let server = AutomationHTTPServer(
            port: AutomationEndpoint.port(bundleIdentifier: Bundle.main.bundleIdentifier),
            handler: handler,
            authenticate: { [clients] in clients.authenticate(bearer: $0) },
            onRefused: { [weak self] in await self?.recordRefusal($0) })
        self.server = server
        startup = Task { [weak self] in
            await self?.clients.loadDigests()
            guard !Task.isCancelled, let self, self.server === server else { return }
            self.clients.watchExpiry()
            server.start()
        }
        questionPresenter.start()
        observationGeneration += 1
        observe(AutomationOperationCatalog.agents.name, generation: observationGeneration) { [unowned core] in
            _ = core.agentRuns.runs
        }
        let terminals = AutomationOperationCatalog.terminals.name
        observe(terminals, generation: observationGeneration) { [unowned core] in
            for instance in core.terminalInstances.instances {
                _ = instance.session.phase
                _ = instance.session.directory
            }
        }
    }

    /// Publishes a resource-updated event each time what `read` touches changes.
    private func observe(
        _ uri: String, generation: Int, _ read: @escaping @MainActor () -> Void
    ) {
        withObservationTracking {
            read()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observationGeneration == generation else { return }
                self.hub.publish(uri: uri)
                self.observe(uri, generation: generation, read)
            }
        }
    }

    /// One audit line per ten seconds: a client hammering a bad token must not fill the disk.
    private func recordRefusal(_ reason: String) async {
        let now = Date()
        if let last = lastRefusalRecord, now.timeIntervalSince(last) < 10 { return }
        lastRefusalRecord = now
        try? await audit.append(
            AutomationAuditEvent(
                id: UUID(), request: UUID(), at: now, kind: .denied, transport: "mcp-http",
                callerRequestID: nil, caller: "unauthenticated", client: nil,
                operation: "authenticate", arguments: nil, detail: reason))
    }
}
