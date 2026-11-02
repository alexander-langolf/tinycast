import Foundation
import Darwin

@MainActor
final class ForkLlamaServer: ForkProcessControl {
    static let defaultModel = "~/github/local-lyra/bench/models/gemma-3n-E2B-it-Q4_K_M.gguf"
    private let pidFile: URL
    private let session: URLSession
    private var child: Process?
    private struct Record: Codable, Equatable, Sendable {
        let pid: Int32
        let seconds: UInt64
        let microseconds: UInt64
        let executable: String
    }

    init(bundleID: String = Bundle.main.bundleIdentifier ?? "com.tinycast.app") {
        pidFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: bundleID).appending(path: "Lyra/server.pid")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    func healthy() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8765/health")!)
        request.timeoutInterval = 1
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            return body["status"] as? String == "ok"
        } catch { return false }
    }

    func recordedPID() async -> Int32? { await Self.validRecordedPID(at: pidFile) }

    func isRunning(_ pid: Int32) -> Bool {
        guard let recorded = Self.record(at: pidFile), recorded.pid == pid else { return false }
        return Self.identity(pid) == recorded
    }

    func launch(modelPath: String) throws -> Int32 {
        let path = (modelPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { throw ForkProcessSupervisor.Failure.missingModel }
        let process = Process()
        process.executableURL = URL(filePath: "/opt/homebrew/bin/llama-server")
        process.arguments = ["-m", path, "--host", "127.0.0.1", "--port", "8765", "--parallel", "1", "--ctx-size", "4096"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try FileManager.default.createDirectory(at: pidFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try process.runObservingExit()
        child = process
        do {
            guard let record = Self.identity(process.processIdentifier) else { throw ForkProcessSupervisor.Failure.exited }
            try JSONEncoder().encode(record).write(to: pidFile, options: .atomic)
        } catch {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            child = nil
            throw error
        }
        return process.processIdentifier
    }

    func stop(_ pid: Int32) async {
        guard let record = Self.record(at: pidFile), record.pid == pid,
            Self.identity(pid) == record else { return }
        kill(pid, SIGTERM)
        let deadline = ContinuousClock.now + .seconds(5)
        while Self.identity(pid) == record, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        if Self.identity(pid) == record { kill(pid, SIGKILL) }
        if child?.processIdentifier == pid { child = nil }
        if Self.record(at: pidFile) == record { try? FileManager.default.removeItem(at: pidFile) }
    }

    func portIsFree() -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(8765).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    @concurrent
    private static func validRecordedPID(at file: URL) async -> Int32? {
        guard let record = record(at: file), identity(record.pid) == record,
            URL(filePath: record.executable).resolvingSymlinksInPath()
                == URL(filePath: "/opt/homebrew/bin/llama-server").resolvingSymlinksInPath()
        else { return nil }
        let pid = record.pid
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-p", String(pid), "-iTCP:8765", "-sTCP:LISTEN", "-t"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard let exit = try? process.runObservingExit() else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        exit.wait()
        guard process.terminationStatus == 0,
            String(decoding: data, as: UTF8.self).split(whereSeparator: { $0.isWhitespace }).contains(Substring(String(pid)))
        else { return nil }
        return pid
    }

    private nonisolated static func record(at file: URL) -> Record? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private nonisolated static func identity(_ pid: Int32) -> Record? {
        guard pid > 0, kill(pid, 0) == 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return Record(pid: pid, seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec, executable: path)
    }

}
