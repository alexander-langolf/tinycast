import Foundation
import Synchronization

final class GhosttyRequestCancellation: Sendable {
    private let value = Mutex(false)
    var isCancelled: Bool { value.withLock { $0 } }
    func cancel() { value.withLock { $0 = true } }
}

enum GhosttySerializedRequest {
    static func run<Value: Sendable>(
        on queue: DispatchQueue, fallback: Value,
        operation: @escaping @Sendable (GhosttyRequestCancellation) -> Value
    ) async -> Value {
        guard !Task.isCancelled else { return fallback }
        let cancelled = GhosttyRequestCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    guard !cancelled.isCancelled else { continuation.resume(returning: fallback); return }
                    continuation.resume(returning: operation(cancelled))
                }
            }
        } onCancel: {
            cancelled.cancel()
        }
    }
}
