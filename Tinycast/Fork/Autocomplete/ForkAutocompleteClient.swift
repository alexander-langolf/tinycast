import Foundation
import Darwin

struct ForkAutocompleteRequest: Encodable, Sendable {
    let op: String
    var context: [String] = ["<s>", "<s>"]
    var prefix = ""
    var word: String?
    var client: String?
    var event: String?
}

struct ForkAutocompleteReply: Decodable, Sendable {
    let ok: Bool
    let words: [String]?
    let confidence: Double?
}

@MainActor
final class ForkAutocompleteClient {
    private var child: Process?
    private var childExit: ProcessExit?
    private var pending: Task<ForkAutocompleteReply?, Never>?
    private var teardown: Task<Void, Never>?
    private var generation = 0
    private let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
    private var path: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/\(bundleID)/ac.sock").path
    }

    func start() async -> Bool {
        await teardown?.value
        let version = generation
        if await request(.init(op: "health"), recover: false)?.ok == true { return true }
        guard !Task.isCancelled, generation == version else { return false }
        if child?.isRunning != true {
            guard let script = Bundle.main.url(forResource: "service", withExtension: "py",
                                               subdirectory: "AutocompleteService") else { return false }
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/env")
            process.arguments = ["python3", "-B", script.path, "--serve", "--bundle-id", bundleID]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                childExit = try process.runObservingExit()
                child = process
            } catch { return false }
        }
        let deadline = ContinuousClock.now + .seconds(90)
        while generation == version, !Task.isCancelled, ContinuousClock.now < deadline {
            if await request(.init(op: "health"), recover: false)?.ok == true { return true }
            if let child, !child.isRunning, child.terminationStatus != 0 { return false }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return false }
        }
        return false
    }

    func request(_ request: ForkAutocompleteRequest, recover: Bool = true) async -> ForkAutocompleteReply? {
        guard let payload = try? JSONEncoder().encode(request) else { return nil }
        let previous = pending
        let version = generation
        let path = path
        let task = Task { [weak self] in
            _ = await previous?.value
            guard let self, !Task.isCancelled, generation == version else { return nil as ForkAutocompleteReply? }
            return await Self.exchange(path: path, payload: payload)
        }
        pending = task
        let reply = await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
        guard !Task.isCancelled, generation == version else { return nil }
        if let reply { return reply }
        guard recover, request.op != "health", await start(),
              !Task.isCancelled, generation == version else { return nil }
        return await self.request(request, recover: false)
    }

    func stop() {
        generation += 1
        pending?.cancel()
        pending = nil
        if let child, child.isRunning { child.terminate() }
    }

    func stopForTermination() async {
        if let teardown { await teardown.value; return }
        stop()
        let process = child
        let exit = childExit
        child = nil
        childExit = nil
        let task = Task {
            let deadline = ContinuousClock.now + .seconds(3)
            while process?.isRunning == true, ContinuousClock.now < deadline {
                do { try await Task.sleep(for: .milliseconds(25)) } catch { break }
            }
            if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
            if let exit { await Self.wait(exit) }
        }
        teardown = task
        await task.value
        teardown = nil
    }

    @concurrent
    private static func wait(_ exit: ProcessExit) async { exit.wait() }

    @concurrent
    private static func exchange(path: String, payload: Data) async -> ForkAutocompleteReply? {
        guard !Task.isCancelled else { return nil }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var timeout = timeval(tv_sec: 0, tv_usec: 750_000)
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: bytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard connected, !Task.isCancelled else { return nil }
        let frame = payload + Data([10])
        let sent = frame.withUnsafeBytes { data -> Bool in
            guard let base = data.baseAddress else { return false }
            var offset = 0
            while offset < data.count {
                let count = Darwin.send(descriptor, base.advanced(by: offset), data.count - offset, 0)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard sent else { return nil }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while result.count <= 32768, !Task.isCancelled {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.recv(descriptor, $0.baseAddress, $0.count, 0)
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return nil }
            result.append(contentsOf: buffer.prefix(count))
            guard result.count <= 32768 else { return nil }
            if result.last == 10 { return try? JSONDecoder().decode(ForkAutocompleteReply.self, from: result) }
        }
        return nil
    }
}
