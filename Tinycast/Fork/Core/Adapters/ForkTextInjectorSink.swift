import AppKit
import Synchronization

@MainActor
struct ForkTextInjectorSink: ForkTextSink {
    let injector: TextInjector

    func replaceSelection(in app: NSRunningApplication, with text: String) async -> Bool {
        let waiter = Waiter()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard waiter.install(continuation), !app.isTerminated else {
                    waiter.finish(false)
                    return
                }
                injector.replaceSelection(
                    with: text, in: app, isValid: { waiter.isActive && !app.isTerminated },
                    onDelivered: { waiter.finish(true) }, onFailed: { waiter.finish(false) })
            }
        } onCancel: {
            waiter.cancel()
        }
    }

    private nonisolated final class Waiter: Sendable {
        private struct State: Sendable {
            var cancelled = false
            var continuation: CheckedContinuation<Bool, Never>?
        }

        private let state = Mutex(State())

        var isActive: Bool { state.withLock { !$0.cancelled && $0.continuation != nil } }

        func install(_ continuation: CheckedContinuation<Bool, Never>) -> Bool {
            let installed = state.withLock {
                guard !$0.cancelled else { return false }
                $0.continuation = continuation
                return true
            }
            if !installed { continuation.resume(returning: false) }
            return installed
        }

        func finish(_ delivered: Bool) {
            let continuation = state.withLock {
                let continuation = $0.continuation
                $0.continuation = nil
                return continuation
            }
            continuation?.resume(returning: delivered)
        }

        func cancel() {
            let continuation = state.withLock {
                $0.cancelled = true
                let continuation = $0.continuation
                $0.continuation = nil
                return continuation
            }
            continuation?.resume(returning: false)
        }
    }
}
