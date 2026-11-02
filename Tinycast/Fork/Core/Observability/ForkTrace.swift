import Foundation
import Synchronization

enum ForkTrace {
    final class FailureState: Sendable {
        let code = Mutex<Int?>(nil)
    }

    struct Context: Sendable {
        let id: UUID
        let operation: ForkEvent.Operation
        let clientID: UUID?
        let failure: FailureState
        var policyVersion: String? = nil

        init(id: UUID, operation: ForkEvent.Operation, clientID: UUID?, failure: FailureState = FailureState(),
             policyVersion: String? = nil) {
            self.id = id
            self.operation = operation
            self.clientID = clientID
            self.failure = failure
            self.policyVersion = policyVersion
        }
    }

    struct Span: Sendable {
        let context: Context
        let category: ForkEvent.Category
        let step: ForkEvent.Step
        let started: ContinuousClock.Instant

        func end(_ outcome: ForkEvent.Outcome = .success, fields: ForkEvent.Fields = .init()) {
            var fields = fields
            fields.clientID = fields.clientID ?? context.clientID
            fields.policyVersion = fields.policyVersion ?? context.policyVersion
            emit(ForkEvent(
                level: outcome == .failed ? .error : .info, category: category,
                operation: context.operation, correlationID: context.id, step: step,
                durationMS: milliseconds(since: started), outcome: outcome, fields: fields))
        }
    }

    @TaskLocal static var context: Context?
    @TaskLocal static var recorder: (@Sendable (ForkEvent) -> Void)?

    static func emit(_ event: ForkEvent) { (recorder ?? ForkLog.record)(event) }

    static func begin(
        _ operation: ForkEvent.Operation, category: ForkEvent.Category, step: ForkEvent.Step
    ) -> Span {
        Span(
            context: context ?? Context(id: UUID(), operation: operation, clientID: nil),
            category: category, step: step, started: .now)
    }

    @MainActor
    static func run<T: Sendable>(
        _ operation: ForkEvent.Operation, category: ForkEvent.Category, clientID: UUID? = nil,
        fields: ForkEvent.Fields = .init(),
        _ body: @MainActor () async throws -> T
    ) async rethrows -> T {
        var trace = context ?? Context(id: UUID(), operation: operation, clientID: clientID)
        trace.policyVersion = fields.policyVersion ?? trace.policyVersion
        var metadata = fields
        metadata.clientID = trace.clientID
        metadata.policyVersion = trace.policyVersion
        return try await $context.withValue(trace) {
            let start = ContinuousClock.now
            emit(ForkEvent(
                category: category, operation: trace.operation, correlationID: trace.id,
                step: .start, outcome: .started, fields: metadata))
            do {
                let result = try await body()
                let failure = trace.failure.code.withLock { $0 }
                var finalFields = metadata
                finalFields.errorCode = failure
                emit(ForkEvent(
                    level: failure == nil ? .info : .error,
                    category: category, operation: trace.operation, correlationID: trace.id,
                    step: failure == nil ? .end : .error, durationMS: milliseconds(since: start),
                    outcome: Task.isCancelled ? .cancelled : failure == nil ? .success : .failed,
                    fields: finalFields))
                return result
            } catch {
                if !(error is CancellationError) {
                    trace.failure.code.withLock { $0 = (error as NSError).code }
                }
                var finalFields = metadata
                finalFields.errorCode = (error as NSError).code
                emit(ForkEvent(
                    level: .error, category: category, operation: trace.operation, correlationID: trace.id,
                    step: .error, durationMS: milliseconds(since: start),
                    outcome: error is CancellationError ? .cancelled : .failed,
                    fields: finalFields))
                throw error
            }
        }
    }

    @MainActor
    static func step<T: Sendable>(
        _ step: ForkEvent.Step, category: ForkEvent.Category,
        _ body: @MainActor () async throws -> T
    ) async rethrows -> T {
        let span = begin(context?.operation ?? .selectedText, category: category, step: step)
        do {
            let result = try await body()
            let fields = (result as? String).map { ForkEvent.Fields(length: $0.count) } ?? .init()
            span.end(Task.isCancelled ? .cancelled : .success, fields: fields)
            return result
        } catch {
            if !(error is CancellationError) {
                context?.failure.code.withLock { $0 = (error as NSError).code }
            }
            span.end(error is CancellationError ? .cancelled : .failed,
                     fields: .init(errorCode: (error as NSError).code))
            throw error
        }
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let components = (ContinuousClock.now - start).components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
}
