import Foundation

@MainActor
enum ForkLyraAutomation {
    static func perform(_ call: AutomationCall, coordinator: ForkLyraCoordinator) async -> AutomationOutcome {
        do {
            guard let policy = ForkPolicySnapshot.current ?? ForkPolicyStore.current?.snapshot else {
                return .toolError("The Lyra rewrite could not be completed.")
            }
            let arguments = try ForkLyraArguments(arguments: call.arguments, modes: policy.policy.availableModes)
            let result = try await coordinator.service.rewrite(mode: arguments.mode, target: arguments.target, apply: arguments.apply)
            return .value(.object(["text": .string(result.text), "applied": .bool(result.applied)]))
        } catch is CancellationError { return .toolError("Cancelled.") }
        catch let error as ForkLyraArguments.Failure { return .toolError(error.description) }
        catch { return .toolError("The Lyra rewrite could not be completed.") }
    }
}
