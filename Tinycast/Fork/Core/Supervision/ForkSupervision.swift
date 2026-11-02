import Foundation

@MainActor
final class ForkSupervision {
    private(set) static weak var current: ForkSupervision?
    let betterTouchTool = ForkAppSupervisor(
        app: ForkBetterTouchTool.descriptor, control: ForkWorkspaceAppControl())

    var processes: [ForkProcessSupervisor] = []
    var workflowActionCount: (() -> Int)?

    func start() {
        Self.current = self
        betterTouchTool.start()
    }

    func stop() {
        betterTouchTool.stop()
        if Self.current === self { Self.current = nil }
    }

    func health(_ call: AutomationCall) async -> AutomationOutcome {
        await ForkTrace.run(.health, category: .automation, clientID: call.caller.clientID) {
            if call.operation.name == ForkHealth.repair.name { _ = await betterTouchTool.repair() }
            for process in processes { await process.refreshHealth() }
            let owner = await ForkHealth.secureInputOwner()
            return .value(ForkHealth.json(
                apps: [betterTouchTool.snapshot], processes: processes.map(\.snapshot), secureInputOwner: owner,
                accessibility: Permissions.isAccessibilityTrusted(), workflowActionCount: workflowActionCount?()))
        }
    }
}
