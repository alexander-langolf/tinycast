import Foundation

/// Owns one `fsearch stdio` child and pairs each reply with the request that asked for it.
@MainActor
final class FSearchClient {
    enum Failure: Error {
        case unavailable
        case exited
        case rejected(String)
    }

    private let executable: () -> URL?
    private var process: Process?
    private var input: FileHandle?
    private var reader: Task<Void, Never>?
    private var pending: [Int: CheckedContinuation<[FSearchHit], any Error>] = [:]
    private var nextID = 0

    init(executable: @escaping () -> URL? = FSearchClient.installedExecutable) {
        self.executable = executable
    }

    nonisolated static func installedExecutable() -> URL? {
        FSearchLocator.locate(
            home: FileManager.default.homeDirectoryForCurrentUser,
            path: ProcessInfo.processInfo.environment["PATH"] ?? "",
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    /// `nil` when fsearch is missing or its status cannot be read.
    @concurrent nonisolated static func fullDiskAccess() async -> Bool? {
        guard let url = installedExecutable() else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = url
        process.arguments = ["status"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let status = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return status?["full_disk_access"] as? Bool
    }

    /// Rows for typed words, or `[]` when the policy leaves nothing to ask.
    func search(
        query: String, filter: FileSearchFilter, policy: FileSearchPolicy
    ) async throws -> [FileSearchResult] {
        guard let text = FSearchQuery.text(words: query, filter: filter, policy: policy) else {
            return []
        }
        var limit = FSearchQuery.pageLimit
        var hits = try await fetchHits(for: text, limit: limit)
        var rows = FSearchQuery.rows(from: hits, requested: limit, policy: policy, filter: filter)
        if rows.mayHaveMore {
            limit = FSearchQuery.expandedLimit
            hits = try await fetchHits(for: text, limit: limit)
            rows = FSearchQuery.rows(from: hits, requested: limit, policy: policy, filter: filter)
        }
        return rows.results
    }

    func fetchHits(for query: String, limit: Int) async throws -> [FSearchHit] {
        try launchIfNeeded()
        nextID += 1
        let id = nextID
        guard let line = FSearchProtocol.requestLine(id: id, query: query, limit: limit) else {
            throw Failure.rejected("unencodable query")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try input?.write(contentsOf: line)
            } catch {
                pending[id] = nil
                continuation.resume(throwing: Failure.exited)
            }
        }
    }

    func stop() {
        reader?.cancel()
        reader = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        input = nil
        failAll(Failure.exited)
    }

    private func launchIfNeeded() throws {
        if let process, process.isRunning { return }
        guard let url = executable() else { throw Failure.unavailable }
        let child = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        child.executableURL = url
        child.arguments = ["stdio"]
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] exited in
            Task { @MainActor in self?.didExit(exited) }
        }
        do { try child.run() } catch { throw Failure.unavailable }
        reader?.cancel()
        process = child
        input = stdin.fileHandleForWriting
        reader = Task { [weak self] in
            do {
                for try await line in stdout.fileHandleForReading.bytes.lines {
                    self?.receive(line)
                }
            } catch {}
        }
    }

    private func receive(_ line: String) {
        switch FSearchProtocol.decode(Data(line.utf8)) {
        case .hits(let id, let hits)?:
            pending.removeValue(forKey: id)?.resume(returning: hits)
        case .failure(let id?, let message)?:
            pending.removeValue(forKey: id)?.resume(throwing: Failure.rejected(message))
        case .failure(nil, _)?, nil:
            // An unattributable line cannot say which request it answers, so the oldest one fails.
            if let id = pending.keys.min() {
                pending.removeValue(forKey: id)?.resume(throwing: Failure.rejected("undecodable"))
            }
        }
    }

    private func didExit(_ exited: Process) {
        guard process === exited else { return }
        process = nil
        input = nil
        failAll(Failure.exited)
    }

    private func failAll(_ error: Failure) {
        let waiting = pending
        pending = [:]
        for continuation in waiting.values { continuation.resume(throwing: error) }
    }
}
