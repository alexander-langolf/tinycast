import Darwin
import Foundation
import Synchronization
import os

/// Append-only JSONL, one event per line, written under a lock so lines never interleave.
/// Same-user tampering is out of scope: the file is 0600 in a 0700 folder, not tamper-evident.
final class AutomationAuditLog: Sendable {
    struct Failure: Error, Sendable {
        let reason: String
    }

    private struct State {
        var descriptor: Int32 = -1
        var bytes = 0
        var healthy = true
    }

    static let maximumBytes = 5 * 1024 * 1024
    static let retainedFiles = 3

    private let url: URL
    private let state = Mutex(State())
    private let encoder = AutomationAuditEvent.makeEncoder()
    private static let logger = Logger(subsystem: "com.tinycast", category: "Automation")

    init(directory: URL) {
        url = directory.appending(path: "audit.jsonl", directoryHint: .notDirectory)
    }

    static func standard() -> AutomationAuditLog {
        AutomationAuditLog(
            directory: AppPaths.applicationSupport().appending(
                path: "Automation", directoryHint: .isDirectory))
    }

    /// False after a write failed, until one succeeds. Privileged effects check it.
    var isHealthy: Bool { state.withLock { $0.healthy } }

    func append(_ event: AutomationAuditEvent) throws {
        let line = try event.line(encoder: encoder)
        let outcome: Result<Void, Failure> = state.withLock { state in
            do {
                try openIfNeeded(&state)
                if state.bytes + line.count > Self.maximumBytes { try rotate(&state) }
                try write(line, to: state.descriptor)
                state.bytes += line.count
                state.healthy = true
                return .success(())
            } catch let failure as Failure {
                state.healthy = false
                if state.descriptor >= 0 {
                    close(state.descriptor)
                    state.descriptor = -1
                }
                return .failure(failure)
            } catch {
                state.healthy = false
                return .failure(Failure(reason: error.localizedDescription))
            }
        }
        if case .failure(let failure) = outcome {
            Self.logger.error("Audit write failed: \(failure.reason, privacy: .public)")
            throw failure
        }
    }

    private func openIfNeeded(_ state: inout State) throws {
        guard state.descriptor < 0 else { return }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Failure(reason: String(cString: strerror(errno))) }
        fchmod(descriptor, 0o600)
        var info = stat()
        state.bytes = fstat(descriptor, &info) == 0 ? Int(info.st_size) : 0
        state.descriptor = descriptor
    }

    private func rotate(_ state: inout State) throws {
        close(state.descriptor)
        state.descriptor = -1
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        func numbered(_ index: Int) -> URL {
            directory.appending(path: "audit.\(index).jsonl", directoryHint: .notDirectory)
        }
        try? manager.removeItem(at: numbered(Self.retainedFiles))
        for index in stride(from: Self.retainedFiles - 1, through: 1, by: -1) {
            try? manager.moveItem(at: numbered(index), to: numbered(index + 1))
        }
        try manager.moveItem(at: url, to: numbered(1))
        try openIfNeeded(&state)
    }

    private func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(
                    descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw Failure(reason: String(cString: strerror(errno)))
                }
                offset += written
            }
        }
    }
}
