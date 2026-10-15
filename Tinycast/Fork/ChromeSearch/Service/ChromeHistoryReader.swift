import Foundation
import SQLite3
import Synchronization

protocol ChromeHistoryReading: Sendable {
    /// Unranked matches for every word of `query`; empty on any failure, so history fails quietly.
    func candidates(for query: String) async -> [ChromeHistoryEntry]
    func discardCopy()
}

/// Reads Chrome's `History` from a private copy, since Chrome keeps the original locked while it runs.
final class ChromeHistoryReader: ChromeHistoryReading {
    private struct Copy {
        var sourceModified: Date?
    }

    private let userDataDirectory: URL
    private let copyDirectory: URL
    private let state = Mutex(Copy())

    init(
        userDataDirectory: URL = .applicationSupportDirectory.appending(path: "Google/Chrome"),
        copyDirectory: URL = FileManager.default.temporaryDirectory
            .appending(path: "tinycast-chrome-history-\(UUID().uuidString)")
    ) {
        self.userDataDirectory = userDataDirectory
        self.copyDirectory = copyDirectory
    }

    @concurrent
    func candidates(for query: String) async -> [ChromeHistoryEntry] {
        let words = ChromeHistoryRanking.words(in: query)
        guard !words.isEmpty, let database = refreshedCopy() else { return [] }
        return Self.select(from: database, words: words)
    }

    func discardCopy() {
        state.withLock { copy in
            try? FileManager.default.removeItem(at: copyDirectory)
            copy.sourceModified = nil
        }
    }

    /// Copies again only when Chrome has written since the last copy.
    private func refreshedCopy() -> URL? {
        let fileManager = FileManager.default
        guard let localState = try? Data(contentsOf: userDataDirectory.appending(path: "Local State")),
            let profile = ChromeProfileLocator.profileDirectory(
                localState: localState, userDataDirectory: userDataDirectory,
                exists: { fileManager.fileExists(atPath: $0.path) })
        else { return nil }
        let source = profile.appending(path: "History")
        let log = profile.appending(path: "History-wal")
        guard let modified = Self.latestModification(of: [source, log]) else { return nil }
        let target = copyDirectory.appending(path: "History")
        return state.withLock { copy in
            if copy.sourceModified == modified, fileManager.fileExists(atPath: target.path) { return target }
            try? fileManager.removeItem(at: copyDirectory)
            copy.sourceModified = nil
            do {
                try fileManager.createDirectory(
                    at: copyDirectory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                try fileManager.copyItem(at: source, to: target)
                if fileManager.fileExists(atPath: log.path) {
                    try fileManager.copyItem(at: log, to: copyDirectory.appending(path: "History-wal"))
                }
            } catch {
                try? fileManager.removeItem(at: copyDirectory)
                return nil
            }
            copy.sourceModified = modified
            return target
        }
    }

    private static func latestModification(of files: [URL]) -> Date? {
        let dates = files.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        return dates.max()
    }

    private static func select(from file: URL, words: [String]) -> [ChromeHistoryEntry] {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        let clauses = words.indices.map {
            "(title LIKE ?\($0 + 1) ESCAPE '\\' OR url LIKE ?\($0 + 1) ESCAPE '\\')"
        }
        let sql = """
            SELECT title, url, visit_count, last_visit_time FROM urls
            WHERE hidden = 0 AND url LIKE 'http%' AND \(clauses.joined(separator: " AND "))
            ORDER BY visit_count DESC, last_visit_time DESC LIMIT \(ChromeHistoryRanking.candidateLimit)
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        for (index, word) in words.enumerated() {
            let escaped = word.replacing("\\", with: "\\\\").replacing("%", with: "\\%")
                .replacing("_", with: "\\_")
            sqlite3_bind_text(statement, Int32(index + 1), "%" + escaped + "%", -1, sqliteTransient)
        }
        var entries: [ChromeHistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard !Task.isCancelled else { return [] }
            guard let urlText = sqlite3_column_text(statement, 1),
                let url = URL(string: String(cString: urlText))
            else { continue }
            let title = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            entries.append(
                ChromeHistoryEntry(
                    title: title, url: url, visitCount: Int(sqlite3_column_int64(statement, 2)),
                    lastVisit: ChromeHistoryEntry.date(webKitMicroseconds: sqlite3_column_int64(statement, 3))
                ))
        }
        return entries
    }
}

// Spelled as the C macro in sqlite3.h, which isn't imported into Swift.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
