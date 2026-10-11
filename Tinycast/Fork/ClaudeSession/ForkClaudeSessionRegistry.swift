import Foundation
import Synchronization

final class ForkClaudeSessionRegistry: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let shortID: String
        let sessionID: String
        let transcriptPath: String
        let folder: String
        var readOffset: UInt64 = 0
        var ended: Bool? = nil

        func matchesSession(_ other: Entry) -> Bool {
            shortID == other.shortID && sessionID == other.sessionID
                && transcriptPath == other.transcriptPath && folder == other.folder
        }
    }

    private let cache: Mutex<Result<[String: Entry], Error>>
    private let fileURL: URL
    private let queue: DispatchQueue

    init(directory: URL) {
        let url = directory.appending(path: "registry.json")
        let storageQueue = DispatchQueue(label: "com.tinycast.claude-session-registry", qos: .utility)
        fileURL = url
        queue = storageQueue
        cache = Mutex(storageQueue.sync { Result { try Self.read(url) } })
    }

    func cachedEntry(chatID: UUID) throws -> Entry? {
        try cache.withLock { try $0.get()[chatID.uuidString] }
    }

    func entries() async throws -> [UUID: Entry] {
        try await perform { fileURL in
            let saved = try Self.read(fileURL)
            self.cache.withLock { $0 = .success(saved) }
            var entries: [UUID: Entry] = [:]
            for (key, entry) in saved {
                guard let id = UUID(uuidString: key), entries[id] == nil else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                entries[id] = entry
            }
            return entries
        }
    }

    func entry(chatID: UUID) async throws -> Entry? {
        try cachedEntry(chatID: chatID)
    }

    func register(chatID: UUID, entry: Entry) async throws {
        try await mutate { $0[chatID.uuidString] = entry }
    }

    func updateReadOffset(
        chatID: UUID, offset: UInt64, sessionID: String, transcriptPath: String
    ) async throws {
        try await mutate { entries in
            guard var entry = entries[chatID.uuidString] else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            guard entry.sessionID == sessionID, entry.transcriptPath == transcriptPath,
                entry.ended != true else { return }
            entry.readOffset = offset
            entries[chatID.uuidString] = entry
        }
    }

    func unregister(chatID: UUID) async throws {
        try await mutate { _ = $0.removeValue(forKey: chatID.uuidString) }
    }

    func updateEnded(chatID: UUID, expected: Entry, ended: Bool) async throws -> Bool {
        try await mutate { entries in
            guard var current = entries[chatID.uuidString],
                current.matchesSession(expected),
                current.ended == expected.ended else { return false }
            current.ended = ended
            entries[chatID.uuidString] = current
            return true
        }
    }

    private func mutate<Value: Sendable>(
        _ change: @escaping @Sendable (inout [String: Entry]) throws -> Value
    ) async throws -> Value {
        try await perform { fileURL in
            var entries = try Self.read(fileURL)
            let result = try change(&entries)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try data.write(to: fileURL, options: .atomic)
            self.cache.withLock { $0 = .success(entries) }
            return result
        }
    }

    private static func read(_ fileURL: URL) throws -> [String: Entry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let entries = try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: fileURL))
        guard entries.keys.allSatisfy({ UUID(uuidString: $0)?.uuidString == $0 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return entries
    }

    private func perform<Value: Sendable>(
        _ operation: @escaping @Sendable (URL) throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [fileURL] in
                do { continuation.resume(returning: try operation(fileURL)) } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
