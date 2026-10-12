import Foundation

@MainActor
final class ForkClaudeSessionWriter {
    enum Delivery {
        case delivered
        case notDelivered(String)
        case cancelled
    }

    var isAttachTerminalOpen = false
    private(set) var queuedCount = 0

    private let entry: ForkClaudeSessionRegistry.Entry
    private let host: ForkClaudeSessionHost
    private let reader: ForkClaudeSessionReader
    private var process: TerminalProcess?
    private var processGeneration = 0
    private var pasteReady = false
    private var outputTask: Task<Void, Never>?
    private var exitTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var queue: [UUID] = []
    private var sending = false
    private var stopped = false

    init(
        entry: ForkClaudeSessionRegistry.Entry,
        host: ForkClaudeSessionHost, reader: ForkClaudeSessionReader
    ) {
        self.entry = entry
        self.host = host
        self.reader = reader
    }

    isolated deinit {
        outputTask?.cancel()
        exitTask?.cancel()
        idleTask?.cancel()
        process?.terminate()
    }

    func stop() {
        stopped = true
        dropClient()
    }

    private func dropClient() {
        processGeneration += 1
        outputTask?.cancel()
        outputTask = nil
        exitTask?.cancel()
        exitTask = nil
        idleTask?.cancel()
        idleTask = nil
        process?.terminate()
        process = nil
        pasteReady = false
    }

    func send(_ text: String, token: UUID) async -> Delivery {
        queue.append(token)
        queuedCount = queue.count
        defer {
            queue.removeAll { $0 == token }
            queuedCount = queue.count
        }
        do {
            while true {
                try checkActive()
                try await reader.refresh()
                if queue.first == token, !sending, canWrite { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            sending = true
            idleTask?.cancel()
            defer {
                sending = false
                scheduleIdleDrop()
            }
            try await attach()
            while true {
                try checkActive()
                try await reader.refresh()
                if canWrite { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard let process, pasteReady else {
                return .notDelivered("Claude Code’s attach terminal is no longer ready for a paste.")
            }
            let generation = processGeneration
            reader.arm(token: token, text: text)
            process.send("\u{1B}[200~" + text + "\u{1B}[201~")
            do {
                try await Task.sleep(for: .milliseconds(300))
                try await reader.refresh()
                try checkActive()
                guard canWrite, processGeneration == generation else {
                    dropClient()
                    return .notDelivered("The session became busy before Return could be sent.")
                }
            } catch {
                dropClient()
                throw error
            }
            process.send("\r")
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while ContinuousClock.now < deadline {
                try checkActive()
                try await reader.refresh()
                if reader.delivered(token: token) { return .delivered }
                guard processGeneration == generation else { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            return .notDelivered("Claude Code did not confirm this message within 5 seconds.")
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .notDelivered(error.localizedDescription)
        }
    }

    private func checkActive() throws {
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
    }

    private var canWrite: Bool {
        !reader.isTurnRunning && !reader.isApprovalWaiting && !isAttachTerminalOpen
    }

    private func attach() async throws {
        if process == nil {
            let executable = try await host.resolveExecutable()
            try checkActive()
            var environment = ForkClaudeSessionHost.environment(running: executable)
            environment["TERM"] = "xterm-256color"
            let generation = processGeneration
            let spawned = await Self.spawn(
                executable: executable, id: entry.shortID,
                environment: environment, directory: entry.folder)
            guard !Task.isCancelled, !stopped, generation == processGeneration else {
                spawned?.terminate()
                throw CancellationError()
            }
            guard let spawned else {
                throw AIProviderError.unavailable("Claude Code’s attach terminal could not be started.")
            }
            process = spawned
            pasteReady = false
            outputTask = Task { [weak self, output = spawned.rawOutput] in
                var suffix = ""
                for await bytes in output {
                    guard !Task.isCancelled else { return }
                    let text = suffix + String(decoding: bytes, as: UTF8.self)
                    let enabled = text.range(of: "\u{1B}[?2004h", options: .backwards)
                    let disabled = text.range(of: "\u{1B}[?2004l", options: .backwards)
                    if let enabled {
                        self?.pasteReady = disabled.map { enabled.lowerBound > $0.lowerBound } ?? true
                    } else if disabled != nil {
                        self?.pasteReady = false
                    }
                    suffix = String(text.suffix(16))
                }
            }
            exitTask = Task { [weak self, events = spawned.events] in
                for await event in events {
                    guard !Task.isCancelled else { return }
                    if case .exited = event, self?.processGeneration == generation {
                        self?.dropClient()
                        return
                    }
                }
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !pasteReady {
            try checkActive()
            guard process != nil, ContinuousClock.now < deadline else {
                dropClient()
                throw AIProviderError.unavailable("Claude Code’s attach terminal is not ready for a paste.")
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func scheduleIdleDrop() {
        guard process != nil else { return }
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(600)) } catch { return }
            guard let self, !self.sending else { return }
            self.dropClient()
        }
    }

    @concurrent
    private static func spawn(
        executable: URL, id: String, environment: [String: String], directory: String
    ) async -> TerminalProcess? {
        guard !Task.isCancelled else { return nil }
        return TerminalProcess.spawn(
            executable: executable.path, arguments: ["attach", id],
            environment: environment, directory: directory, columns: 120, rows: 40)
    }
}
