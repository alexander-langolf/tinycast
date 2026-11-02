import Foundation
import Synchronization

struct ForkClaudeAccountProvider: AIProvider {
    let account: ForkClaudeAccount
    let sessionID: UUID
    let model: ForkClaudeCatalog.Model
    let effort: String
    let title: Bool
    private let turn = TurnState()

    private final class TurnState: Sendable {
        struct Value {
            var user: AIMessage?
            var userIndex: Int?
            var thinking: [String: [JSONValue]] = [:]
            var text = ""
        }
        let value = Mutex(Value())
    }

    init(account: ForkClaudeAccount, sessionID: UUID, model: ForkClaudeCatalog.Model, effort: String, title: Bool) {
        self.account = account
        self.sessionID = sessionID
        self.model = model
        self.effort = effort
        self.title = title
    }

    func stream(_ request: AIRequest) -> AIProviderStream {
        let traceContext = ForkTrace.context
            ?? ForkTrace.Context(id: UUID(), operation: .claudeRequest, clientID: nil)
        return AIProviderStream { continuation in
            let task = Task.detached {
                await ForkTrace.$context.withValue(traceContext) {
                do {
                    try await run(request, into: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    turn.value.withLock { $0 = TurnState.Value() }
                    continuation.finish()
                } catch let failure as AIProviderError {
                    turn.value.withLock { $0 = TurnState.Value() }
                    continuation.finish(throwing: failure)
                } catch let failure as ForkClaudeAccountLogin.Failure {
                    turn.value.withLock { $0 = TurnState.Value() }
                    continuation.finish(throwing: AIProviderError.unavailable(failure.localizedDescription))
                } catch {
                    turn.value.withLock { $0 = TurnState.Value() }
                    continuation.finish(throwing: AIProviderError.responseFailed(
                        String(localized: "The Claude account request could not complete. Try again.")))
                }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ input: AIRequest, into continuation: AIProviderStream.Continuation) async throws {
        let version = await account.cliVersion()
        try Task.checkCancellation()
        let index = input.messages.lastIndex { $0.role == .user }
        let user = index.map { input.messages[$0] }
        let thinking = turn.value.withLock { state in
            if state.user != user || state.userIndex != index {
                state = TurnState.Value(user: user, userIndex: index)
            }
            return state.thinking
        }
        let transcript = account.transcript
        let body = ForkClaudeRequestBody.make(
            input, model: model, effort: effort, title: title,
            historicalEffort: { transcript.effort(for: $0, conversation: input.conversationID) },
            thinking: thinking)
        let encoded = try JSONSerialization.data(withJSONObject: body)
        for attempt in 0...1 {
            try Task.checkCancellation()
            let token = try await account.accessToken(sessionID: sessionID)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 90)
            request.httpMethod = "POST"
            request.httpBody = encoded
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("claude-cli/\(version)", forHTTPHeaderField: "user-agent")
            request.setValue("cli", forHTTPHeaderField: "x-app")
            request.setValue(
                ForkClaudeRequestBody.betas(model: model, effort: effort, title: title).joined(separator: ","),
                forHTTPHeaderField: "anthropic-beta")
            let sent = ForkTrace.begin(.claudeRequest, category: .claudeAccount, step: .response)
            let headers = (request.allHTTPHeaderFields ?? [:])
                .filter { $0.key.lowercased() != "authorization" }
            ForkTrace.begin(.claudeRequest, category: .claudeAccount, step: .requestHeaders)
                .end(.success, fields: .init(byteCount: encoded.count, headerCount: headers.count))
            let received: (URLSession.AsyncBytes, URLResponse)
            do { received = try await session.bytes(for: request) }
            catch {
                let outcome: ForkEvent.Outcome = error is CancellationError || Task.isCancelled
                    ? .cancelled : (error as? URLError)?.code == .timedOut ? .timeout : .failed
                sent.end(outcome, fields: .init(errorCode: (error as NSError).code))
                throw error
            }
            if Task.isCancelled { sent.end(.cancelled); throw CancellationError() }
            let (bytes, rawResponse) = received
            guard let response = rawResponse as? HTTPURLResponse else {
                sent.end(.failed)
                throw AIProviderError.malformedResponse
            }
            sent.end(response.statusCode == 200 ? .success : .failed,
                     fields: .init(statusCode: response.statusCode))
            if response.statusCode == 401 {
                session.invalidateAndCancel()
                if attempt == 0 {
                    _ = try await account.accessToken(sessionID: sessionID, rejectedToken: token)
                    continue
                }
                await account.invalidate(rejectedToken: token, sessionID: sessionID)
                throw ForkClaudeAccountLogin.Failure.rejected
            }
            guard response.statusCode == 200 else {
                let body = await Self.failureBody(bytes)
                try Task.checkCancellation()
                let message = await failure(response: response, body: body, token: token)
                throw AIProviderError.responseFailed(message)
            }
            try await decode(bytes, input: input, token: token, into: continuation)
            return
        }
    }

    private func decode(
        _ bytes: URLSession.AsyncBytes, input: AIRequest, token: String,
        into continuation: AIProviderStream.Continuation
    ) async throws {
        var decoder = AIStreamDecoder(shape: .anthropic, secrets: [token], requiresCompleteText: input.requiresCompleteText)
        var observer = ForkClaudeStreamObserver()
        var chunk = Data()
        var text = ""
        var calls: [AIToolCall] = []
        func emit(_ events: [AIStreamEvent]) {
            for event in events {
                switch event {
                case .text(let delta):
                    text += delta
                    continuation.yield(event)
                case .toolCallRequested(let call):
                    let mapped = AIToolCall(
                        id: call.id, name: ForkClaudeCodeTools.fromClaudeCodeName(call.name, tools: input.tools),
                        arguments: call.arguments, thoughtSignature: call.thoughtSignature)
                    calls.append(mapped)
                    continuation.yield(.toolCallRequested(mapped))
                case .finished: break
                default: continuation.yield(event)
                }
            }
        }
        for try await byte in bytes {
            try Task.checkCancellation()
            chunk.append(byte)
            if byte == 0x0A {
                observer.feed(chunk)
                emit(try decoder.feed(chunk))
                chunk.removeAll(keepingCapacity: true)
                if decoder.isTerminal { break }
            }
        }
        if !chunk.isEmpty, !decoder.isTerminal {
            observer.feed(chunk)
            emit(try decoder.feed(chunk))
        }
        observer.finish()
        if !decoder.isTerminal { emit(try decoder.finish()) }
        guard decoder.isTerminal else {
            throw AIProviderError.responseFailed(String(localized: "The connection closed before the response completed."))
        }
        try Task.checkCancellation()
        account.transcript.record(
            AIMessage(role: .assistant, text: text, toolCalls: calls),
            conversation: input.conversationID, effort: model.wireEffort(effort))
        let combined = turn.value.withLock { state in
            state.thinking.merge(observer.thinkingByCall) { _, new in new }
            state.text += text
            let combined = state.text
            if calls.isEmpty { state = TurnState.Value() }
            return combined
        }
        if calls.isEmpty {
            account.transcript.record(
                AIMessage(role: .assistant, text: combined), conversation: input.conversationID,
                effort: model.wireEffort(effort))
        }
        continuation.yield(.finished)
    }

    private func failure(response: HTTPURLResponse, body: Data, token: String) async -> String {
        let said = AIProviderFailure.providerMessage(in: body) ?? ""
        var message = AIProviderFailure.description(
            status: response.statusCode, body: body,
            retryAfter: response.value(forHTTPHeaderField: "Retry-After"), secrets: [token])
        if response.statusCode == 404, said.contains(model.id) {
            await account.recordRefusal(model: model.id, effort: nil, sessionID: sessionID)
            message += "\n\n" + String(localized: "This model is now hidden. Refresh the Claude account to restore it.")
        } else if response.statusCode == 400, said.localizedCaseInsensitiveContains("Invalid effort level") {
            await account.recordRefusal(model: model.id, effort: effort, sessionID: sessionID)
            message += "\n\n" + String(localized: "This effort level is now hidden. Refresh the Claude account to restore it.")
        } else if response.statusCode == 429 {
            message += "\n\n" + String(localized: "Try the Claude CLI route in AI Settings.")
        }
        return message
    }

    private static func failureBody(_ bytes: URLSession.AsyncBytes) async -> Data {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                var body = Data()
                var iterator = bytes.makeAsyncIterator()
                while body.count < AIProviderFailure.bodyLimit, let byte = try? await iterator.next() {
                    body.append(byte)
                }
                return body
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            var body = Data()
            for await read in group {
                if let read { body = read }
                group.cancelAll()
            }
            return body
        }
    }
}
