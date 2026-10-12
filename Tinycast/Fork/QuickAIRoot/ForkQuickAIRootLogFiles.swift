import Foundation
import Synchronization

final class ForkQuickAIRootLogFiles: Sendable {
    private let directory: URL
    private struct Policy {
        var enabled = false
        var retention: TimeInterval = 86_400
    }
    private let policy = Mutex(Policy())
    private var logURL: URL { directory.appending(path: "log.jsonl") }
    private var handoffsURL: URL {
        directory.appending(path: "handoffs", directoryHint: .isDirectory)
    }

    init(directory: URL) { self.directory = directory }

    func configure(enabled: Bool, retention: TimeInterval) {
        policy.withLock { $0 = Policy(enabled: enabled, retention: retention) }
    }

    func append(_ entry: ForkQuickAIRootLog.Entry) throws {
        try policy.withLock { policy in
            guard policy.enabled else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(entry)
            data.append(0x0A)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                try data.write(to: logURL, options: .atomic)
                return
            }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }
    }

    func writeHandoff(chat: UUID, text: String) throws -> URL {
        try policy.withLock { policy in
            guard policy.enabled else { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.createDirectory(at: handoffsURL, withIntermediateDirectories: true)
            let url = handoffsURL.appending(path: chat.uuidString.lowercased() + ".md")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    func prune() throws {
        try policy.withLock { policy in
            guard policy.enabled, FileManager.default.fileExists(atPath: directory.path) else { return }
            let cutoff = Date().addingTimeInterval(-policy.retention)
            if FileManager.default.fileExists(atPath: logURL.path) {
                let text = try String(contentsOf: logURL, encoding: .utf8)
                let lines = text.split(separator: "\n").map(String.init)
                let kept = ForkQuickAIRootLog.prune(lines: lines, olderThan: cutoff)
                if kept != lines {
                    let output = kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n"
                    try output.write(to: logURL, atomically: true, encoding: .utf8)
                }
            }
            try removeHandoffs(olderThan: cutoff)
        }
    }

    func pruneFiles(olderThan cutoff: Date) throws {
        try policy.withLock { policy in
            guard policy.enabled else { return }
            try removeHandoffs(olderThan: cutoff)
        }
    }

    private func removeHandoffs(olderThan cutoff: Date) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: handoffsURL.path) else { return }
        let files = try manager.contentsOfDirectory(
            at: handoffsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
        for file in files {
            guard file.pathExtension == "md",
                UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil
            else { continue }
            let values = try file.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                let modified = values.contentModificationDate, modified < cutoff
            else { continue }
            try manager.removeItem(at: file)
        }
    }
}
