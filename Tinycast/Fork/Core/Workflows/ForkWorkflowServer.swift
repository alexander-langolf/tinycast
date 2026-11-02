import AppKit
import Darwin

@MainActor
final class ForkWorkflowServer: ForkProcessControl {
    private unowned let core: AppCore
    private let directory: URL
    private let support: URL
    private let port: UInt16
    private let session: URLSession
    private var child: Process?
    private var token = ""
    private var environment: [String: String] = [:]
    private var lifecycle: Task<Void, Never>?
    private var teardown: Task<Void, Never>?
    private var linkRuns: [UUID: Task<Void, Never>] = [:]
    private var generation = 0
    private(set) var actionCount = 0
    private(set) lazy var supervisor = ForkProcessSupervisor(name: "workflow-server", control: self)

    init(core: AppCore, defaults: UserDefaults = .standard) {
        self.core = core
        directory = URL(filePath: ((defaults.string(forKey: "fork.server.directory")
            ?? "~/github/tinycast/server") as NSString).expandingTildeInPath)
        support = AppPaths.applicationSupport()
        port = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? 43322
            : Bundle.main.bundleIdentifier?.hasSuffix(".beta") == true ? 43323 : 43321
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    func start() {
        #if DEBUG
        guard lifecycle == nil, core.automation.isEnabled else { return }
        generation += 1
        let mine = generation
        let cleanup = teardown
        lifecycle = Task { [weak self] in
            await cleanup?.value
            guard let self, !Task.isCancelled, generation == mine else { return }
            defer { if generation == mine { lifecycle = nil } }
            do {
                let clientToken = try await core.automation.clients.ensureWorkflowsClient()
                try Task.checkCancellation()
                guard generation == mine else { return }
                token = AutomationClientStore.makeToken(for: UUID())
                try await Self.writeToken(token, support: support)
                try Task.checkCancellation()
                guard generation == mine else { return }
                environment = ForkWorkflowEnvironment.values(
                    inherited: ProcessInfo.processInfo.environment, token: token, clientToken: clientToken,
                    tinycastPort: AutomationEndpoint.port(bundleIdentifier: Bundle.main.bundleIdentifier),
                    serverPort: port, diagnostics: support.appending(path: "Diagnostics").path)
                var attempts: [Date] = []
                while !Task.isCancelled, generation == mine {
                    do {
                        try await ForkTrace.run(.workflow, category: .workflows) {
                            try await supervisor.start(modelPath: directory.path, timeout: .seconds(10))
                        }
                        while !Task.isCancelled, generation == mine, await healthy() {
                            try await Task.sleep(for: .seconds(2))
                        }
                    } catch is CancellationError { throw CancellationError() }
                    catch { ForkTrace.begin(.workflow, category: .workflows, step: .readiness).end(.failed) }
                    try Task.checkCancellation()
                    guard generation == mine else { return }
                    await supervisor.stop()
                    actionCount = 0
                    attempts = attempts.filter { Date().timeIntervalSince($0) < 600 }
                    guard attempts.count < 3 else {
                        ForkTrace.begin(.workflow, category: .workflows, step: .gaveUp).end(.gaveUp)
                        return
                    }
                    attempts.append(Date())
                    try await Task.sleep(for: .seconds(2))
                }
            } catch {
                if !(error is CancellationError) {
                    ForkTrace.begin(.workflow, category: .workflows, step: .readiness).end(.failed)
                }
            }
        }
        #endif
    }

    func stop() {
        generation += 1
        let mine = generation
        let previous = lifecycle
        lifecycle = nil
        previous?.cancel()
        for task in linkRuns.values { task.cancel() }
        linkRuns.removeAll()
        actionCount = 0
        let cleanup = teardown
        teardown = Task { [weak self] in
            await previous?.value
            await cleanup?.value
            await self?.supervisor.stop()
            if self?.generation == mine { self?.teardown = nil }
        }
        core.forkPrimitives.stop()
    }

    func stopForTermination() async {
        stop()
        await teardown?.value
        await core.forkPrimitives.stopForTermination()
    }

    func healthy() async -> Bool {
        let mine = generation
        guard !token.isEmpty, let child, child.isRunning else { return false }
        do {
            let value = try await request("health", timeout: 1)
            guard !Task.isCancelled, generation == mine, child.isRunning,
                value.objectValue?["status"]?.stringValue == "ok",
                case .number(let count)? = value.objectValue?["actionCount"],
                count.isFinite, count >= 0, count <= 10_000 else { return false }
            actionCount = Int(count)
            return true
        } catch { return false }
    }

    func handleLink(_ url: URL) -> Bool {
        guard let name = ForkWorkflowRoute.action(url, scheme: Bundle.main.bundleIdentifier) else { return false }
        let target = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let mine = generation
        let id = UUID()
        linkRuns[id] = Task { [weak self] in
            guard let self else { return }
            defer { linkRuns[id] = nil }
            await ForkTrace.run(.workflow, category: .workflows) {
                do {
                    guard core.automation.isEnabled, await healthy() else { throw Failure.unavailable }
                    let catalog = try await request("actions", timeout: 2)
                    try Task.checkCancellation()
                    guard generation == mine, ForkWorkflowRoute.permits(name, catalog: catalog) else {
                        throw Failure.unavailable
                    }
                    try await run(name, target: target, fromLink: true)
                } catch {
                    guard !Task.isCancelled else { return }
                    ForkTrace.context?.failure.code.withLock { $0 = -1 }
                    core.showMessage(String(localized: "The workflow could not be completed."), tone: .danger)
                }
            }
        }
        return true
    }

    func run(_ name: String, target: String?, fromLink: Bool = false) async throws {
        guard ForkWorkflowRoute.validName(name), core.automation.isEnabled else { throw Failure.unavailable }
        let mine = generation
        var body: [String: JSONValue] = [:]
        if let target { body["target"] = .string(target) }
        let result = try await request("actions/\(name)", body: .object(body), fromLink: fromLink, timeout: 600)
        if result.objectValue?["applied"]?.boolValue == false { throw Failure.unavailable }
        try Task.checkCancellation()
        guard mine == generation else { throw CancellationError() }
    }

    private func request(
        _ path: String, body: JSONValue? = nil, fromLink: Bool = false, timeout: TimeInterval
    ) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(path)")!)
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let id = ForkTrace.context?.id {
            request.setValue(id.uuidString, forHTTPHeaderField: "X-Tinycast-Correlation")
        }
        if fromLink { request.setValue("link", forHTTPHeaderField: "X-Tinycast-Source") }
        if let body { request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body.jsonObject) }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, let value = JSONValue(data: data) else {
            throw Failure.unavailable
        }
        return value
    }

    func recordedPID() async -> Int32? { nil }
    func isRunning(_ pid: Int32) -> Bool { child?.processIdentifier == pid && child?.isRunning == true }

    func launch(modelPath: String) throws -> Int32 {
        guard !environment.isEmpty else { throw Failure.unavailable }
        let process = Process()
        process.executableURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".bun/bin/bun")
        process.arguments = ["run", "src/main.ts"]
        process.currentDirectoryURL = URL(filePath: modelPath)
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        _ = try process.runObservingExit()
        child = process
        return process.processIdentifier
    }

    func stop(_ pid: Int32) async {
        guard let process = child, process.processIdentifier == pid else { return }
        if process.isRunning { process.terminate() }
        let deadline = ContinuousClock.now + .seconds(5)
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        if process.isRunning { kill(pid, SIGKILL) }
        if child === process { child = nil }
    }

    func portIsFree() -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    @concurrent
    private static func writeToken(_ token: String, support: URL) async throws {
        let directory = support.appending(path: "Workflows")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let temporary = directory.appending(path: UUID().uuidString)
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw Failure.unavailable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: Data(token.utf8))
        guard Darwin.rename(temporary.path, directory.appending(path: "server-token").path) == 0 else {
            throw Failure.unavailable
        }
    }

    private enum Failure: Error { case unavailable }
}
