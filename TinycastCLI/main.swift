import Foundation
import Security

setvbuf(stdout, nil, _IOLBF, 0)
signal(SIGPIPE, SIG_IGN)

enum Channel: String {
    case dev, stable, beta

    var bundleIdentifier: String {
        switch self {
        case .dev: "com.tinycast.app.dev"
        case .stable: "com.tinycast.app"
        case .beta: "com.tinycast.app.beta"
        }
    }

    var port: Int {
        switch self {
        case .dev: 43312
        case .stable: 43311
        case .beta: 43313
        }
    }

    var appName: String {
        switch self {
        case .dev: "Tinycast Dev"
        case .stable: "Tinycast"
        case .beta: "Tinycast Beta"
        }
    }

    static var defaultChannel: Channel {
        #if DEBUG
            .dev
        #else
            .stable
        #endif
    }
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data("tinycast: \(message)\n".utf8))
}

func fail(_ message: String) -> Never {
    warn(message)
    exit(1)
}

struct Options {
    var channel =
        Channel(rawValue: ProcessInfo.processInfo.environment["TINYCAST_CHANNEL"] ?? "")
        ?? Channel.defaultChannel
    var client = ProcessInfo.processInfo.environment["TINYCAST_CLIENT"]
    var stdio = false
}

func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var iterator = arguments.makeIterator()
    guard iterator.next() == "mcp" else {
        fail("usage: tinycast mcp --stdio [--client <id>] [--channel dev|stable|beta]")
    }
    while let argument = iterator.next() {
        switch argument {
        case "--stdio": options.stdio = true
        case "--client":
            guard let value = iterator.next() else { fail("--client needs a value") }
            options.client = value
        case "--channel":
            guard let value = iterator.next(), let channel = Channel(rawValue: value) else {
                fail("--channel must be dev, stable or beta")
            }
            options.channel = channel
        default: fail("unknown option \(argument)")
        }
    }
    guard options.stdio else { fail("only --stdio is supported") }
    return options
}

enum Credentials {
    static func token(service: String, client: String?) -> String {
        let account = client ?? onlyAccount(service: service)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        query[kSecUseDataProtectionKeychain as String] = false
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
            let token = String(bytes: data, encoding: .utf8)
        else {
            fail("no token for client \(account) in the Keychain (service \(service), status \(status))")
        }
        return token
    }

    private static func onlyAccount(service: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let items = (result as? [[String: Any]]) ?? []
        let accounts = items.compactMap { $0[kSecAttrAccount as String] as? String }
        guard status == errSecSuccess, !accounts.isEmpty else {
            fail("no automation client exists yet: create one in Settings → General → Automation")
        }
        guard accounts.count == 1 else {
            fail("several clients exist; pass --client <id> (\(accounts.sorted().joined(separator: ", ")))")
        }
        return accounts[0]
    }
}

// Mutable state and output are locked; configuration stays immutable after initialization.
final class Bridge: @unchecked Sendable {
    private let endpoint: URL
    private let token: String
    private let session: URLSession
    private let lock = NSLock()
    private var inFlight: [String: Task<Void, Never>] = [:]
    private var listening: [String: Task<Void, Never>] = [:]
    private var unanswered: [UUID: Task<Void, Never>] = [:]
    private var legacyVersion: String?
    private let appName: String

    init(port: Int, token: String, appName: String) {
        endpoint = URL(string: "http://127.0.0.1:\(port)/mcp")!
        self.token = token
        self.appName = appName
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 86_400
        session = URLSession(configuration: configuration)
    }

    func run() async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { dispatch(trimmed) }
            }
        } catch {
            warn("stdin failed: \(error.localizedDescription)")
        }
        await drain()
    }

    /// A piped client closes stdin right after writing, so what it already sent is still answered.
    private func drain() async {
        let (streams, pending) = lock.withLock {
            (Array(listening.values), Array(inFlight.values) + Array(unanswered.values))
        }
        for stream in streams { stream.cancel() }
        for task in pending { await task.value }
    }

    private func dispatch(_ line: String) {
        guard let data = line.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            emit(errorMessage(id: nil, code: -32700, text: "Parse error"))
            return
        }
        let method = object["method"] as? String
        let id = object["id"]
        if method == "notifications/cancelled" {
            if let requestID = (object["params"] as? [String: Any])?["requestId"] {
                cancel(key(of: requestID))
            }
            return
        }
        guard let method else {
            warn("ignoring a response from the client: this server sends no requests")
            return
        }
        let request = Request(body: data, method: method, params: object["params"] as? [String: Any])
        // Registered under the lock before the task can finish and remove itself.
        lock.lock()
        defer { lock.unlock() }
        guard let id else {
            let token = UUID()
            unanswered[token] = Task { [weak self] in
                guard let self else { return }
                await self.post(request, id: nil)
                _ = self.lock.withLock { self.unanswered.removeValue(forKey: token) }
            }
            return
        }
        let identifier = key(of: id)
        guard method == "subscriptions/listen" else {
            inFlight[identifier] = Task { [weak self] in
                guard let self else { return }
                await self.post(request, id: id)
                _ = self.lock.withLock { self.inFlight.removeValue(forKey: identifier) }
            }
            return
        }
        listening[identifier] = Task { [weak self] in
            guard let self else { return }
            await self.post(request, id: id)
            _ = self.lock.withLock { self.listening.removeValue(forKey: identifier) }
        }
    }

    private func cancel(_ identifier: String) {
        lock.withLock {
            inFlight.removeValue(forKey: identifier) ?? listening.removeValue(forKey: identifier)
        }?.cancel()
    }

    private func key(of id: Any) -> String {
        if let number = id as? NSNumber { return "n:\(number)" }
        return "s:\(id)"
    }

    struct Request {
        let body: Data
        let method: String
        let params: [String: Any]?
    }

    private func post(_ request: Request, id: Any?) async {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        mirrorHeaders(for: request, into: &urlRequest)
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let isStream =
                http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true
            if isStream {
                try await forwardEvents(bytes)
            } else {
                var body = Data()
                for try await byte in bytes { body.append(byte) }
                forward(body, status: http.statusCode, id: id, method: request.method)
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch let error as URLError where error.code == .cannotConnectToHost {
            guard let id else { return }
            emit(
                errorMessage(
                    id: id, code: -32603,
                    text: "\(appName) is not listening. Open it and turn on Settings → General → Automation.")
            )
        } catch {
            guard let id else { return warn("request failed: \(error.localizedDescription)") }
            emit(errorMessage(id: id, code: -32603, text: "Request failed: \(error.localizedDescription)"))
        }
    }

    private func mirrorHeaders(for request: Request, into urlRequest: inout URLRequest) {
        let meta = request.params?["_meta"] as? [String: Any]
        if let version = meta?["io.modelcontextprotocol/protocolVersion"] as? String {
            urlRequest.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version")
            urlRequest.setValue(request.method, forHTTPHeaderField: "Mcp-Method")
            let named: String?
            switch request.method {
            case "tools/call", "prompts/get": named = request.params?["name"] as? String
            case "resources/read": named = request.params?["uri"] as? String
            default: named = nil
            }
            if let named { urlRequest.setValue(encodeHeader(named), forHTTPHeaderField: "Mcp-Name") }
        } else if request.method != "initialize", let version = lock.withLock({ legacyVersion }) {
            urlRequest.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version")
        }
    }

    private func encodeHeader(_ value: String) -> String {
        let plain = value.utf8.allSatisfy { (0x20...0x7E).contains($0) }
        let trimmed = value == value.trimmingCharacters(in: .whitespaces)
        let sentinel = value.hasPrefix("=?base64?") && value.hasSuffix("?=")
        guard plain, trimmed, !sentinel else {
            return "=?base64?\(Data(value.utf8).base64EncodedString())?="
        }
        return value
    }

    private func forwardEvents(_ bytes: URLSession.AsyncBytes) async throws {
        var line = [UInt8]()
        var data = ""
        func finish(_ line: [UInt8]) {
            var text = String(decoding: line, as: UTF8.self)
            if text.hasSuffix("\r") { text.removeLast() }
            if text.isEmpty {
                if !data.isEmpty { emit(data) }
                data = ""
            } else if text.hasPrefix("data:") {
                let payload = text.dropFirst(5)
                data += payload.hasPrefix(" ") ? payload.dropFirst() : payload
            }
        }
        for try await byte in bytes {
            if byte == 0x0A {
                finish(line)
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(byte)
            }
        }
        if !line.isEmpty { finish(line) }
        if !data.isEmpty { emit(data) }
    }

    private func forward(_ body: Data, status: Int, id: Any?, method: String) {
        if status == 202 || body.isEmpty && id == nil { return }
        if var object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
            if object["id"] == nil || object["id"] is NSNull, let id { object["id"] = id }
            if method == "initialize", let result = object["result"] as? [String: Any],
                let version = result["protocolVersion"] as? String
            {
                lock.withLock { legacyVersion = version }
            }
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                let text = String(bytes: data, encoding: .utf8)
            {
                emit(text)
                return
            }
        }
        guard let id else { return }
        emit(errorMessage(id: id, code: -32603, text: "The server answered HTTP \(status) without JSON"))
    }

    private func errorMessage(id: Any?, code: Int, text: String) -> String {
        let object: [String: Any] = [
            "jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": text]
        ]
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private let output = NSLock()

    private func emit(_ line: String) {
        output.withLock {
            guard let data = (line.replacingOccurrences(of: "\n", with: " ") + "\n").data(using: .utf8)
            else { return }
            FileHandle.standardOutput.write(data)
        }
    }
}

await Task.detached {
    let options = parse(Array(CommandLine.arguments.dropFirst()))
    let token = Credentials.token(
        service: "\(options.channel.bundleIdentifier).automation-clients", client: options.client)
    let bridge = Bridge(
        port: options.channel.port, token: token, appName: options.channel.appName)
    warn("bridging stdio to 127.0.0.1:\(options.channel.port) as \(options.channel.rawValue)")
    await bridge.run()
}.value
