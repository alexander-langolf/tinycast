import Foundation
import os

/// The one door. Every transport authenticates its own caller, then hands a call here; nothing
/// else decides who may do what.
@MainActor
final class AutomationRouter {
    private let runner: AutomationRunner
    private let now: () -> Date
    private var limiters: [String: AutomationRateLimiter] = [:]
    private static let logger = Logger(subsystem: "com.tinycast", category: "Automation")

    init(runner: AutomationRunner, now: @escaping () -> Date = { Date() }) {
        self.runner = runner
        self.now = now
    }

    func route(_ call: AutomationCall) async -> AutomationOutcome {
        let operation = call.operation
        switch AutomationPolicy.decide(caller: call.caller, operation: operation) {
        case .deny(let reason):
            Self.logger.info("Refused \(operation.name, privacy: .public): \(reason, privacy: .public)")
            return .rpcError(.invalidParams(Self.unavailable(operation)))
        case .requireApproval, .allow:
            break
        }
        if let problem = AutomationSchemaValidator.validate(
            arguments: call.arguments, against: operation.inputSchema)
        {
            return .rpcError(.invalidParams(problem))
        }
        guard admit(call.caller) else { return .toolError("Too many requests; try again shortly.") }
        return await perform(call)
    }

    private static func unavailable(_ operation: AutomationOperation) -> String {
        operation.kind == .tool ? "Unknown tool: \(operation.name)" : "Resource not found"
    }

    private func admit(_ caller: AutomationCaller) -> Bool {
        let key = caller.clientID?.uuidString ?? "link"
        var limiter =
            limiters[key]
            ?? (caller.channel == .link
                ? AutomationRateLimiter(capacity: 3, perSecond: 0.5)
                : AutomationRateLimiter(capacity: 30, perSecond: 5))
        let admitted = limiter.take(at: now())
        limiters[key] = limiter
        return admitted
    }

    private func perform(_ call: AutomationCall) async -> AutomationOutcome {
        let arguments = call.arguments
        switch call.operation.name {
        case AutomationOperationCatalog.hudShow.name:
            runner.showMessage(from: call.caller.label, text: arguments["text"]?.stringValue ?? "")
            return .value(.object(["shown": .bool(true)]))
        case AutomationOperationCatalog.paletteShow.name:
            runner.showPalette(query: arguments["query"]?.stringValue ?? "")
            return .value(.object(["shown": .bool(true)]))
        default:
            return .rpcError(.internalError("Operation is not implemented"))
        }
    }
}
