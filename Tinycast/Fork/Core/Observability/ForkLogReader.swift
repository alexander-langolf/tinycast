import Darwin
import Foundation

struct ForkLogFilter: Sendable {
    var correlationID: UUID?
    var operation: ForkEvent.Operation?
    var level: ForkEvent.Level?
    var since: Date?

    func accepts(_ event: ForkEvent) -> Bool {
        (correlationID == nil || event.correlationID == correlationID)
            && (operation == nil || event.operation == operation)
            && (level == nil || event.level == level)
            && (since == nil || event.time >= since!)
    }
}

struct ForkLogReader {
    private struct Identity: Hashable {
        let inode: UInt64
        let birthSeconds: Int
        let birthNanoseconds: Int
    }

    let directory: URL
    var filter = ForkLogFilter()
    private var offsets: [Identity: UInt64] = [:]

    init(directory: URL, filter: ForkLogFilter = .init()) {
        self.directory = directory
        self.filter = filter
    }

    mutating func read() throws -> [String] {
        let manager = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result: [(time: Date, line: String)] = []
        let names = ["events", "server"].flatMap { name in
            ["\(name).3.jsonl", "\(name).2.jsonl", "\(name).1.jsonl", "\(name).jsonl"]
        }
        for name in names {
            let url = directory.appending(path: name)
            guard manager.fileExists(atPath: url.path) else { continue }
            let handle: FileHandle
            do { handle = try FileHandle(forReadingFrom: url) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
            defer { try? handle.close() }
            var info = stat()
            guard fstat(handle.fileDescriptor, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
            let identity = Identity(
                inode: UInt64(info.st_ino), birthSeconds: info.st_birthtimespec.tv_sec,
                birthNanoseconds: info.st_birthtimespec.tv_nsec)
            let size = try handle.seekToEnd()
            var offset = offsets[identity] ?? 0
            if size < offset { offset = 0 }
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            var start = data.startIndex
            for end in data.indices where data[end] == 10 {
                let line = data[start..<end]
                if let event = try? decoder.decode(ForkEvent.self, from: Data(line)), filter.accepts(event) {
                    result.append((event.time, String(decoding: line, as: UTF8.self)))
                }
                offset += UInt64(end - start + 1)
                start = end + 1
            }
            offsets[identity] = offset
        }
        return result.enumerated().sorted { left, right in
            let leftTime = left.element.time
            let rightTime = right.element.time
            return leftTime == rightTime ? left.offset < right.offset : leftTime < rightTime
        }.map { $0.element.line }
    }
}
