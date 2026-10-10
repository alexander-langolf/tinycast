import Foundation
import Observation

/// Inbound automation: the feature's single entry from `AppCore`. It owns the router and what the
/// transports share. Separate from the MCP client under `Features/MCP/`.
@MainActor
@Observable
final class AutomationCoordinator {
    private static let enabledKey = "automationEnabled"

    let clients: AutomationClientStore
    private(set) var server: AutomationHTTPServer?
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored let audit = AutomationAuditLog.standard()
    @ObservationIgnored let hub = AutomationEventHub()
    @ObservationIgnored private(set) var approvals: AutomationApprovalQueue
    @ObservationIgnored private(set) var router: AutomationRouter
    @ObservationIgnored private var lastRefusalRecord: Date?

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
            present: { [unowned core] request in await Self.ask(request, core: core) })
        self.approvals = approvals
        router = AutomationRouter(
            runner: AutomationRunner(core: core), audit: audit, approvals: approvals,
            currentCaller: { [clients] caller in
                guard let id = caller.clientID else { return caller }
                return clients.current(id).map(AutomationCaller.client)
            })
        clients.onChange = { [approvals, hub] revoked in
            guard let revoked else { return }
            approvals.cancelAll(for: revoked)
            hub.end(client: revoked)
        }
    }

    /// Called once from `AppCore.start()`; a disabled feature touches nothing.
    func start() {
        apply()
    }

    func stop() {
        server?.stop()
        server = nil
        approvals.stop()
        hub.endAll()
    }

    /// True when the URL is an automation link and has been handled, whatever the router decided.
    /// A disabled feature claims nothing, so the URL falls through to the extension handler.
    func handleLink(_ url: URL) -> Bool {
        guard isEnabled, let request = AutomationURL.parse(url) else { return false }
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
    ) throws
        -> AutomationClient
    {
        try clients.create(label: label, scopes: scopes, lifetime: lifetime)
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
        clients.loadDigests()
        let handler = AutomationMCPHandler(
            router: router, hub: hub,
            serverVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
        let server = AutomationHTTPServer(
            port: AutomationEndpoint.port(bundleIdentifier: Bundle.main.bundleIdentifier),
            handler: handler,
            authenticate: { [clients] in clients.authenticate(bearer: $0) },
            onRefused: { [weak self] in self?.recordRefusal($0) })
        self.server = server
        server.start()
    }

    /// One audit line per ten seconds: a client hammering a bad token must not fill the disk.
    private func recordRefusal(_ reason: String) {
        let now = Date()
        if let last = lastRefusalRecord, now.timeIntervalSince(last) < 10 { return }
        lastRefusalRecord = now
        try? audit.append(
            AutomationAuditEvent(
                id: UUID(), request: UUID(), at: now, kind: .denied, transport: "mcp-http",
                callerRequestID: nil, caller: "unauthenticated", client: nil,
                operation: "authenticate", arguments: nil, detail: reason))
    }

    /// Tinycast's own dialog, defaulting to Deny so a stray return never approves.
    private static func ask(_ request: AutomationApprovalRequest, core: AppCore) async -> Bool {
        let message = request.details.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
        let choice = await core.choose(
            title: request.title, message: message, symbol: "terminal",
            options: [DialogAction(title: "Allow"), DialogAction(title: "Deny", role: .cancel)],
            defaultIndex: 1, tone: .danger)
        return choice == 0
    }
}
