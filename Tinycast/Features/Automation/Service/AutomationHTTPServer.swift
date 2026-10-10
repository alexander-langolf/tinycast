import Foundation
import Network
import Observation
import os

/// The loopback HTTP listener. It frames and authenticates requests; everything after that is the
/// MCP handler's. Bound to 127.0.0.1 only, bounded in connections, sizes and time.
@MainActor
@Observable
final class AutomationHTTPServer {
    enum Status: Equatable {
        case stopped
        case listening(UInt16)
        case failed(String)
    }

    static let maximumConnections = 16
    static let readDeadline: Duration = .seconds(10)
    static let handlerDeadline: Duration = .seconds(180)

    private(set) var status: Status = .stopped
    let port: UInt16
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let handler: AutomationMCPHandler
    @ObservationIgnored private let authenticate: (String) -> AutomationClient?
    @ObservationIgnored private let onRefused: (String) -> Void
    @ObservationIgnored private var failedAuth = AutomationRateLimiter(capacity: 10, perSecond: 1)
    @ObservationIgnored private var openConnections = 0
    private nonisolated static let logger = Logger(subsystem: "com.tinycast", category: "Automation")

    init(
        port: UInt16, handler: AutomationMCPHandler,
        authenticate: @escaping (String) -> AutomationClient?,
        onRefused: @escaping (String) -> Void
    ) {
        self.port = port
        self.handler = handler
        self.authenticate = authenticate
        self.onRefused = onRefused
    }

    isolated deinit { task?.cancel() }

    func start() {
        guard task == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let listener: NetworkListener<TCP>
        do {
            listener = try NetworkListener(
                using: .parameters { TCP() }
                    .localEndpoint(.hostPort(host: .ipv4(.loopback), port: endpointPort)))
        } catch {
            status = .failed("Could not listen on port \(port)")
            return
        }
        status = .listening(port)
        task = Task { [weak self] in
            do {
                try await listener.onStateUpdate { [weak self] _, state in
                    switch state {
                    case .waiting, .failed:
                        self?.status = .failed("Port \(self?.port ?? 0) is unavailable")
                    case .cancelled:
                        self?.status = .failed("The listener stopped")
                    case .ready:
                        self?.status = .listening(self?.port ?? 0)
                    default: break
                    }
                }.run { [weak self] connection in
                    await self?.accept(connection)
                }
                guard !Task.isCancelled else { return }
                self?.status = .failed("The listener stopped")
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed("The listener stopped: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        status = .stopped
    }

    // MARK: - Connection

    private final class Cancellation {
        var action: (@Sendable () -> Void)?
        var watcher: Task<Void, Never>?
        var requested = false
        func cancel() {
            requested = true
            action?()
        }
    }

    /// A cap on connections open at once; `newConnectionLimit` would count every one ever accepted.
    private func accept(_ connection: NetworkConnection<TCP>) async {
        guard openConnections < Self.maximumConnections else {
            let busy = AutomationHTTPResponse.rejected(
                AutomationHTTPRejection(
                    status: 503, reason: "Too many open connections", headers: ["Retry-After": "1"]))
            try? await write(busy, to: connection, cancellation: Cancellation())
            return
        }
        openConnections += 1
        defer { openConnections -= 1 }
        await serve(connection)
    }

    private func serve(_ connection: NetworkConnection<TCP>) async {
        let cancellation = Cancellation()
        defer { cancellation.watcher?.cancel() }
        let response: AutomationHTTPResponse
        do {
            response = try await respond(on: connection, cancellation: cancellation)
        } catch let rejection as AutomationHTTPRejection {
            response = .rejected(rejection)
        } catch {
            return
        }
        do {
            try await write(response, to: connection, cancellation: cancellation)
        } catch {
            Self.logger.debug("Connection closed before the response finished")
        }
    }

    private func respond(
        on connection: NetworkConnection<TCP>, cancellation: Cancellation
    ) async throws -> AutomationHTTPResponse {
        let (head, buffer) = try await readHead(connection)
        if let rejection = AutomationHTTPGate.check(head, port: port) { throw rejection }
        guard let token = AutomationHTTPGate.bearer(in: head), let client = authenticate(token) else {
            guard failedAuth.take(at: Date()) else {
                throw AutomationHTTPRejection(status: 429, reason: "Too many failed attempts")
            }
            onRefused("Missing, unknown, revoked or expired bearer token")
            throw AutomationHTTPRejection(
                status: 401, reason: "Unauthorized",
                headers: ["WWW-Authenticate": "Bearer realm=\"tinycast\""])
        }
        guard AutomationHTTPGate.contentTypeIsJSON(head) else {
            throw AutomationHTTPRejection(status: 415, reason: "Content-Type must be application/json")
        }
        let body = try await readBody(head, buffer: buffer, from: connection)
        // Only now: a second reader earlier would swallow the request's own bytes.
        cancellation.watcher = Task { @MainActor in
            _ = try? await connection.receive(atLeast: 1, atMost: 1)
            cancellation.cancel()
        }
        switch AutomationMCPCall.parse(body: body, headers: head.headers) {
        case .failure(let error):
            return .init(
                status: error.httpStatus, body: .json(AutomationRPCMessage.error(id: nil, error)))
        case .success(let call):
            let caller = AutomationCaller.client(client)
            let acceptsStream = AutomationHTTPGate.acceptsEventStream(head)
            let handler = handler
            let work = Task { @MainActor in
                await handler.handle(call, caller: caller, acceptsEventStream: acceptsStream)
            }
            cancellation.action = { work.cancel() }
            if cancellation.requested { work.cancel() }
            let deadline = Task {
                try? await Task.sleep(for: Self.handlerDeadline)
                if !Task.isCancelled { work.cancel() }
            }
            defer { deadline.cancel() }
            return await work.value
        }
    }

    private func readHead(
        _ connection: NetworkConnection<TCP>
    ) async throws -> (AutomationHTTPHead, Data) {
        try await withDeadline(Self.readDeadline) {
            var buffer = Data()
            while true {
                let message = try await connection.receive(atLeast: 1, atMost: 8192)
                buffer.append(message.content)
                switch AutomationHTTPParser.parseHead(buffer) {
                case .failure(let rejection): throw rejection
                case .success(.head(let head)): return (head, buffer)
                case .success(.incomplete):
                    if message.metadata.endOfStream {
                        throw AutomationHTTPRejection(status: 400, reason: "Incomplete request")
                    }
                }
            }
        }
    }

    private func readBody(
        _ head: AutomationHTTPHead, buffer: Data, from connection: NetworkConnection<TCP>
    ) async throws -> Data {
        try await withDeadline(Self.readDeadline) {
            var body = Data(buffer.dropFirst(head.bodyStart))
            while body.count < head.contentLength {
                let message = try await connection.receive(
                    atLeast: 1, atMost: head.contentLength - body.count)
                body.append(message.content)
                if message.metadata.endOfStream, body.count < head.contentLength {
                    throw AutomationHTTPRejection(status: 400, reason: "Incomplete body")
                }
            }
            return body.prefix(head.contentLength)
        }
    }

    private func withDeadline<T: Sendable>(
        _ duration: Duration, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw AutomationHTTPRejection(status: 408, reason: "Request timed out")
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }

    private func write(
        _ response: AutomationHTTPResponse, to connection: NetworkConnection<TCP>,
        cancellation: Cancellation
    ) async throws {
        switch response.body {
        case .empty:
            try await connection.send(response.head(), endOfStream: true)
        case .json(let data):
            try await connection.send(response.head() + data, endOfStream: true)
        case .stream(let stream):
            try await connection.send(response.head())
            let writer = Task { @MainActor in
                for await chunk in stream {
                    try await connection.send(chunk)
                }
            }
            cancellation.action = { writer.cancel() }
            if cancellation.requested { writer.cancel() }
            try await writer.value
            try await connection.send(Data(), endOfStream: true)
        }
    }
}
