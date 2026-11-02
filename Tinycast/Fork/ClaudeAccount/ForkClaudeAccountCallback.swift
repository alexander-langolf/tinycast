import Foundation
import Network

@MainActor
final class ForkClaudeAccountCallback {
    private var task: Task<Void, Never>?
    private var ready: CheckedContinuation<UInt16, Error>?
    private var reply: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var accepted = false

    isolated deinit { task?.cancel() }

    func start(port: NWEndpoint.Port) async throws -> UInt16 {
        let listener = try NetworkListener(
            using: .parameters { TCP() }
                .localEndpoint(.hostPort(host: .ipv4(.loopback), port: port)))
        listener.newConnectionLimit = 16
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                task = Task { [weak self] in
                    do {
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask { [weak self] in try await self?.run(listener) }
                            group.addTask {
                                try await Task.sleep(for: .seconds(300))
                                throw ForkClaudeAccountLogin.Failure.listener
                            }
                            defer { group.cancelAll() }
                            _ = try await group.next()
                        }
                    } catch { self?.finish(.failure(error)) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func code() async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if let result { return try result.get() }
            return try await withCheckedThrowingContinuation { reply = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<String, Error>) {
        guard self.result == nil else { return }
        self.result = result
        ready?.resume(throwing: ForkClaudeAccountLogin.Failure.listener)
        ready = nil
        reply?.resume(with: result)
        reply = nil
        task?.cancel()
        task = nil
    }

    private func run(_ listener: NetworkListener<TCP>) async throws {
        try await listener.onStateUpdate { [weak self] _, state in
            switch state {
            case .ready:
                if let port = listener.port {
                    self?.ready?.resume(returning: port.rawValue)
                    self?.ready = nil
                }
            case .waiting, .failed:
                self?.finish(.failure(ForkClaudeAccountLogin.Failure.listener))
            default: break
            }
        }.run { [weak self] connection in
            await self?.receive(connection)
        }
    }

    private func receive(_ connection: NetworkConnection<TCP>) async {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in try await self?.read(connection) }
                group.addTask { try await Task.sleep(for: .seconds(5)) }
                defer { group.cancelAll() }
                _ = try await group.next()
            }
        } catch { return }
    }

    private func read(_ connection: NetworkConnection<TCP>) async throws {
        var bytes = Data()
        while bytes.count < 8192 {
            let message = try await connection.receive(atLeast: 1, atMost: 8192 - bytes.count)
            bytes.append(message.content)
            if bytes.range(of: Data("\r\n\r\n".utf8)) != nil { break }
            if message.metadata.endOfStream { return }
        }
        guard !accepted, let request = String(data: bytes, encoding: .utf8),
            request.contains("\r\n\r\n") else { return }
        let parts = (request.components(separatedBy: "\r\n").first ?? "").split(separator: " ")
        guard parts.count == 3, parts[0] == "GET",
            let url = URLComponents(string: "http://localhost" + String(parts[1])),
            url.path == "/callback"
        else { return }
        let items = url.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value ?? ""
        let state = items.first { $0.name == "state" }?.value ?? ""
        accepted = true
        let page = String(localized: "Return to Tinycast. You can close this tab.")
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\nContent-Length: \(page.utf8.count)\r\n\r\n\(page)"
        defer { finish(.success("\(code)#\(state)")) }
        try await connection.send(Data(response.utf8), endOfStream: true)
    }
}
