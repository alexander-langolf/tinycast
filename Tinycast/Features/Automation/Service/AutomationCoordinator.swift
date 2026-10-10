import Foundation
import Observation

/// Inbound automation: the feature's single entry from `AppCore`. It owns the router and, as the
/// transports arrive, everything they share. Separate from the MCP client under `Features/MCP/`.
@MainActor
@Observable
final class AutomationCoordinator {
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private(set) lazy var runner = AutomationRunner(core: core)
    @ObservationIgnored private(set) lazy var router = AutomationRouter(runner: runner)

    init(core: AppCore) {
        self.core = core
    }
}
