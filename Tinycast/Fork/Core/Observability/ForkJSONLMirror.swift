import Foundation
import os

final class ForkJSONLMirror: Sendable {
    static let maximumBytes = 5 * 1024 * 1024
    static let retainedFiles = 3

    let directory: URL
    private let limitBytes: Int
    private let queue = DispatchQueue(label: "com.tinycast.diagnostics", qos: .utility)
    private static let logger = Logger(subsystem: "com.tinycast", category: "Diagnostics")

    init(directory: URL, maximumBytes: Int = ForkJSONLMirror.maximumBytes) {
        self.directory = directory
        limitBytes = maximumBytes
    }

    func append(_ event: ForkEvent) {
        queue.async { [self] in
            do { try write(event) }
            catch { Self.logger.error("Diagnostics mirror write failed; unified logging remains active") }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    private func write(_ event: ForkEvent) throws {
        let data = try event.line()
        let manager = FileManager.default
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let url = directory.appending(path: "events.jsonl")
        let bytes = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if bytes > 0, bytes + data.count > limitBytes { try rotate(url) }
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            else { throw CocoaError(.fileWriteUnknown) }
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func rotate(_ url: URL) throws {
        let manager = FileManager.default
        func numbered(_ index: Int) -> URL { directory.appending(path: "events.\(index).jsonl") }
        let oldest = numbered(Self.retainedFiles)
        if manager.fileExists(atPath: oldest.path) { try manager.removeItem(at: oldest) }
        for index in stride(from: Self.retainedFiles - 1, through: 1, by: -1) {
            let source = numbered(index)
            if manager.fileExists(atPath: source.path) {
                try manager.moveItem(at: source, to: numbered(index + 1))
            }
        }
        try manager.moveItem(at: url, to: numbered(1))
    }
}
