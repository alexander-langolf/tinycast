import Foundation

/// The lock serializes start/cancel; stdout and its parsing buffer have one off-main reader.
final class ForkRipgrepProcess: @unchecked Sendable {
    private let process = Process()
    private let pipe = Pipe()
    private let lock = NSLock()
    private var cancelled = false
    private var exit: ProcessExit?
    private var pending = Data()
    private var reachedEnd = false
    private var emittedPaths = false

    init(executable: URL, directory: URL, arguments: [String]) {
        process.executableURL = executable
        process.currentDirectoryURL = directory
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
    }

    func start() throws {
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            exit = try process.runObservingExit()
        }
        try pipe.fileHandleForWriting.close()
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if process.isRunning { process.terminate() }
        }
    }

    func next() throws -> [String]? {
        try Task.checkCancellation()
        guard !reachedEnd else { return nil }
        var paths: [String] = []
        while paths.isEmpty {
            if let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
                pending.append(chunk)
                var start = pending.startIndex
                for end in pending.indices where pending[end] == 0 {
                    try Task.checkCancellation()
                    if let path = String(data: pending[start..<end], encoding: .utf8) {
                        paths.append(path)
                        emittedPaths = true
                    }
                    start = pending.index(after: end)
                }
                pending = Data(pending[start...])
            } else {
                reachedEnd = true
                exit?.wait()
                try Task.checkCancellation()
                guard
                    process.terminationStatus == 0 || process.terminationStatus == 1
                        || (process.terminationStatus == 2 && emittedPaths)
                else {
                    throw Failure.exit(process.terminationStatus)
                }
                return paths.isEmpty ? nil : paths
            }
        }
        return paths
    }

    func finish() {
        cancel()
        exit?.wait()
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
    }

    enum Failure: Error { case exit(Int32) }
}
