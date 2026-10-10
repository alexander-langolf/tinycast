import Foundation
import os

/// The one door. Every transport authenticates its own caller, then hands a call here; nothing
/// else decides who may do what. Each call leaves received, then one or more outcome events.
@MainActor
final class AutomationRouter {
    static let approvalWindow: TimeInterval = 60

    private let runner: AutomationRunner
    private let audit: AutomationAuditLog
    private let approvals: AutomationApprovalQueue
    private let currentCaller: (AutomationCaller) -> AutomationCaller?
    private let now: () -> Date
    private var limiters: [String: AutomationRateLimiter] = [:]
    private var lastThrottleRecord: [String: Date] = [:]
    private static let logger = Logger(subsystem: "com.tinycast", category: "Automation")

    /// `currentCaller` returns the caller as it stands now, nil once revoked or expired.
    init(
        runner: AutomationRunner, audit: AutomationAuditLog, approvals: AutomationApprovalQueue,
        currentCaller: @escaping (AutomationCaller) -> AutomationCaller?,
        now: @escaping () -> Date = { Date() }
    ) {
        self.runner = runner
        self.audit = audit
        self.approvals = approvals
        self.currentCaller = currentCaller
        self.now = now
    }

    func route(_ call: AutomationCall) async -> AutomationOutcome {
        let operation = call.operation
        guard admit(call.caller) else {
            recordThrottled(call)
            return .toolError("Too many requests; try again shortly.")
        }
        do {
            try record(.received, call, detail: nil)
        } catch  where operation.isPrivileged {
            return .toolError("The audit log is unavailable, so this action is refused.")
        } catch {}

        if case .deny(let reason) = AutomationPolicy.decide(caller: call.caller, operation: operation) {
            try? record(.denied, call, detail: reason)
            return .rpcError(.invalidParams(Self.unavailable(operation)))
        }
        if let problem = AutomationSchemaValidator.validate(
            arguments: call.arguments, against: operation.inputSchema)
        {
            try? record(.denied, call, detail: problem)
            return .rpcError(.invalidParams(problem))
        }
        let prepared: Prepared
        switch runner.prepare(call) {
        case .failure(let failure):
            try? record(.denied, call, detail: failure.description)
            return .toolError(failure.description)
        case .success(let value):
            prepared = value
        }

        if operation.needsApproval {
            if let refusal = await approve(call, prepared) { return refusal }
        }
        guard let caller = currentCaller(call.caller),
            AutomationPolicy.permits(caller: caller, operation: operation)
        else {
            try? record(.denied, call, detail: "Authority was withdrawn before the action ran")
            return .toolError("This client is no longer authorized.")
        }
        guard !Task.isCancelled else {
            try? record(.cancelled, call, detail: "Caller went away before the action ran")
            return .toolError("Cancelled.")
        }
        if operation.isPrivileged, !audit.isHealthy {
            return .toolError("The audit log is unavailable, so this action is refused.")
        }
        let outcome = await runner.perform(call, prepared: prepared)
        switch outcome {
        case .value: try? record(.completed, call, detail: nil)
        case .toolError(let message): try? record(.failed, call, detail: message)
        case .rpcError(let error): try? record(.failed, call, detail: error.message)
        }
        return outcome
    }

    private func approve(_ call: AutomationCall, _ prepared: Prepared) async -> AutomationOutcome? {
        let created = now()
        let request = AutomationApprovalRequest(
            id: call.request, clientID: call.caller.clientID, clientLabel: call.caller.label,
            operation: call.operation.name, title: prepared.approvalTitle,
            details: prepared.approvalDetails, createdAt: created,
            expiresAt: created.addingTimeInterval(Self.approvalWindow))
        switch await approvals.request(request) {
        case .allowed:
            try? record(.approved, call, detail: "Approved by the user")
            return nil
        case .denied:
            try? record(.denied, call, detail: "Declined by the user")
            return .toolError("The user declined.")
        case .expired:
            try? record(.denied, call, detail: "Approval expired")
            return .toolError("The approval request expired before the user answered.")
        case .cancelled:
            try? record(.cancelled, call, detail: "Caller went away while waiting for approval")
            return .toolError("Cancelled.")
        case .tooMany:
            try? record(.denied, call, detail: "Too many pending approvals")
            return .toolError("Too many approval requests are waiting; try again later.")
        }
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

    /// A flood must not flood the log: one throttled record per caller every ten seconds.
    private func recordThrottled(_ call: AutomationCall) {
        let key = call.caller.clientID?.uuidString ?? "link"
        let current = now()
        if let last = lastThrottleRecord[key], current.timeIntervalSince(last) < 10 { return }
        lastThrottleRecord[key] = current
        try? record(.denied, call, detail: "Rate limited")
    }

    private func record(
        _ kind: AutomationAuditEvent.Kind, _ call: AutomationCall, detail: String?
    ) throws {
        try audit.append(
            AutomationAuditEvent(
                id: UUID(), request: call.request, at: now(), kind: kind, transport: call.transport,
                caller: call.caller.label, client: call.caller.clientID,
                operation: call.operation.name,
                arguments: AutomationAuditEvent.summary(of: call.arguments), detail: detail))
    }

    /// What the runner worked out before approval: the exact thing the user will be shown.
    struct Prepared: Sendable {
        var approvalTitle = ""
        var approvalDetails: [AutomationApprovalRequest.Detail] = []
        var command: String?
        var directory: String?
    }
}
