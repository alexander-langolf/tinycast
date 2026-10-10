import Foundation

final class ForkClaudeSessionRegistry: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let shortID: String
        let sessionID: String
        let transcriptPath: String
        let folder: String
        var readOffset: UInt64 = 0
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.tinycast.claude-session-registry", qos: .utility)

    init(directory: URL) {
        fileURL = directory.appending(path: "registry.json")
    }

    func entries() async throws -> [UUID: Entry] {
        try await perform { fileURL in
            let saved = try Self.read(fileURL)
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
        try await perform { try Self.read($0)[chatID.uuidString] }
    }

    func register(chatID: UUID, entry: Entry) async throws {
        try await mutate { $0[chatID.uuidString] = entry }
    }

    func updateReadOffset(chatID: UUID, offset: UInt64) async throws {
        try await mutate { entries in
            guard var entry = entries[chatID.uuidString] else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            entry.readOffset = offset
            entries[chatID.uuidString] = entry
        }
    }

    func unregister(chatID: UUID) async throws {
        try await mutate { $0.removeValue(forKey: chatID.uuidString) }
    }

    private func mutate(
        _ change: @escaping @Sendable (inout [String: Entry]) throws -> Void
    ) async throws {
        try await perform { fileURL in
            var entries = try Self.read(fileURL)
            try change(&entries)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try data.write(to: fileURL, options: .atomic)
        }
    }

    private static func read(_ fileURL: URL) throws -> [String: Entry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        return try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: fileURL))
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
