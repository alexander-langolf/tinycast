import Foundation

@MainActor
enum ForkAutomationTrace {
    static func run(
        _ call: AutomationCall, _ dispatch: @MainActor () async -> AutomationOutcome
    ) async -> AutomationOutcome {
        let lyra = call.operation.name == "lyra_rewrite"
        let policy = lyra ? ForkPolicyStore.current?.snapshot : nil
        return await ForkPolicySnapshot.$current.withValue(policy) {
            await ForkTrace.run(
                lyra ? .lyra : .automation,
                category: .automation, clientID: call.caller.clientID,
                fields: .init(automationOperation: ForkEvent.AutomationOperation(rawValue: call.operation.name) ?? .unknown,
                              policyVersion: policy?.version)
            ) {
                let outcome = await dispatch()
                switch outcome {
                case .value: break
                case .toolError: ForkTrace.context?.failure.code.withLock { $0 = -1 }
                case .rpcError(let error): ForkTrace.context?.failure.code.withLock { $0 = error.code }
                }
                return outcome
            }
        }
    }

    static func unknown(caller: AutomationCaller, _ record: @MainActor () async -> Void) async {
        await ForkTrace.run(
            .automation, category: .automation, clientID: caller.clientID,
            fields: .init(automationOperation: .unknown)
        ) {
            await record()
            ForkTrace.context?.failure.code.withLock { $0 = -32602 }
        }
    }

    static func auditArguments(_ call: AutomationCall) -> String? {
        ForkSelectionOperations.contains(call.operation) ? nil : AutomationAuditEvent.summary(of: call.arguments)
    }

    static func auditDetail(_ detail: String?, call: AutomationCall) -> String? {
        ForkSelectionOperations.contains(call.operation) && detail != nil ? "Selection operation refused or failed" : detail
    }
}
