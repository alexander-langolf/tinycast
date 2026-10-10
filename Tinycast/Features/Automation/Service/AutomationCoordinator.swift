import Foundation
import Observation

/// Inbound automation: the feature's single entry from `AppCore`. It owns the router and what the
/// transports share. Separate from the MCP client under `Features/MCP/`.
@MainActor
@Observable
final class AutomationCoordinator {
    let clients: AutomationClientStore
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored let audit = AutomationAuditLog.standard()
    @ObservationIgnored private(set) var approvals: AutomationApprovalQueue
    @ObservationIgnored private(set) var router: AutomationRouter

    init(core: AppCore) {
        self.core = core
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
        clients.load()
        clients.onChange = { [approvals] revoked in
            if let revoked { approvals.cancelAll(for: revoked) }
        }
    }

    func createClient(
        label: String, scopes: Set<AutomationScope>, lifetime: TimeInterval?
    ) throws
        -> AutomationClient
    {
        try clients.create(label: label, scopes: scopes, lifetime: lifetime)
    }

    func stop() {
        approvals.stop()
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
