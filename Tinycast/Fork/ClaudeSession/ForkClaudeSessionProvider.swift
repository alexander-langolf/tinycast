import Foundation

struct ForkClaudeSessionProvider: AIProvider {
    private let reader: ForkClaudeSessionReader
    private let writer: ForkClaudeSessionWriter

    @MainActor
    init(reader: ForkClaudeSessionReader, writer: ForkClaudeSessionWriter) {
        self.reader = reader
        self.writer = writer
    }

    func stream(_ request: AIRequest) -> AIProviderStream {
        AIProviderStream { continuation in
            let task = Task { @MainActor in
                guard let message = request.messages.last(where: { $0.role == .user }),
                    !message.text.isEmpty else {
                    continuation.finish(throwing: AIProviderError.unavailable(
                        "There is no user message to send."))
                    return
                }
                guard message.images.isEmpty, message.documents.isEmpty else {
                    continuation.finish(throwing: AIProviderError.unavailable(
                        "Claude session chat currently accepts text messages only."))
                    return
                }
                let token = UUID()
                let events = reader.events(token: token)
                defer { reader.release(token: token) }
                switch await writer.send(message.text, token: token) {
                case .delivered:
                    do {
                        for try await event in events {
                            try Task.checkCancellation()
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch { continuation.finish(throwing: error) }
                case .notDelivered(let reason):
                    continuation.finish(throwing: AIProviderError.responseFailed(
                        "Not delivered. \(reason) Retry to send it again."))
                case .cancelled: continuation.finish(throwing: CancellationError())
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
