import Foundation

struct ForkClaudeSessionTail: Sendable {
    let lines: [Data]
    let offset: UInt64

    @concurrent
    static func read(url: URL, offset: UInt64) async throws -> Self {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Self(lines: [], offset: offset)
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size >= offset else { throw CocoaError(.fileReadCorruptFile) }
        try file.seek(toOffset: offset)
        var pending = Data()
        var lines: [Data] = []
        var consumed = offset
        while let chunk = try file.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            pending.append(chunk)
            while let end = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[..<end])
                consumed += UInt64(line.count + 1)
                lines.append(line)
                pending.removeSubrange(...end)
            }
            guard pending.count <= 8 * 1_048_576 else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        return Self(lines: lines, offset: consumed)
    }
}
