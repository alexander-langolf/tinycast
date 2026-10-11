import Foundation
import OSLog

@MainActor
final class ForkRipgrepIndex {
    private var engine = ForkFileSearchEngine.spotlight
    private var patterns: [String] = []
    private let home: URL
    private(set) var paths: [String]?
    private var builtAt: ContinuousClock.Instant?
    private var build: Task<[String]?, Never>?
    private var revision = 0
    private var used = false
    private let logger = Logger(subsystem: "com.tinycast.app", category: "ripgrep-search")

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var executable: URL? {
        engine == .ripgrep ? ForkFileSearchEngine.executable() : nil
    }

    func supports(_ policy: FileSearchPolicy) -> Bool {
        let root = home.standardizedFileURL.path
        return executable != nil && policy.homeDirectory.standardizedFileURL == home.standardizedFileURL
            && policy.directRoots.allSatisfy { $0.path.hasPrefix(root + "/") }
    }

    func prepare() {
        used = true
        if paths == nil { refreshIfNeeded() }
    }

    func paletteOpened() {
        guard used else { return }
        refreshIfNeeded()
    }

    func configure(engine: ForkFileSearchEngine, patterns: [String]) {
        guard engine != self.engine || patterns != self.patterns else { return }
        self.engine = engine
        self.patterns = patterns
        stop()
        paths = nil
        builtAt = nil
        if used { refreshIfNeeded() }
    }

    func stop() {
        revision &+= 1
        build?.cancel()
        build = nil
    }

    isolated deinit { build?.cancel() }

    func readyPaths() async -> [String]? {
        if let paths { return paths }
        return await build?.value
    }

    private func refreshIfNeeded() {
        guard build == nil, let executable else { return }
        if let builtAt, builtAt.duration(to: .now) < .seconds(120) { return }
        let revision = revision
        let home = home
        let patterns = patterns
        build = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                try await Self.load(executable: executable, home: home, patterns: patterns)
            }
            do {
                let paths = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { @Sendable in
                    worker.cancel()
                }
                guard let self, self.revision == revision, !Task.isCancelled else { return nil }
                self.paths = paths
                self.builtAt = .now
                self.build = nil
                return paths
            } catch {
                guard let self, self.revision == revision, !Task.isCancelled else { return nil }
                self.logger.error("ripgrep index failed: \(error.localizedDescription, privacy: .public)")
                self.build = nil
                return nil
            }
        }
    }

    @concurrent
    private static func load(executable: URL, home: URL, patterns: [String]) async throws -> [String] {
        let runner = ForkRipgrepProcess(
            executable: executable, directory: home,
            arguments: ForkRipgrepPolicy.arguments(patterns: patterns, home: home.path, subtree: false))
        return try await withTaskCancellationHandler {
            defer { runner.finish() }
            try Task.checkCancellation()
            try runner.start()
            let ignore = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults + patterns)
            var paths: [String] = []
            var directories = Set<String>()
            while let batch = try runner.next() {
                for relative in batch {
                    try Task.checkCancellation()
                    let url = home.appending(path: relative).standardizedFileURL
                    let path = url.path
                    guard path.hasPrefix(home.path + "/"),
                        !path.hasPrefix(home.path + "/Library/"),
                        !ForkRipgrepPolicy.excludes(path, ignore: ignore, home: home.path)
                    else { continue }
                    paths.append(path)
                    var directory = url.deletingLastPathComponent()
                    while directory.path != home.path, directory.path.hasPrefix(home.path + "/") {
                        let path = directory.path + "/"
                        guard directories.insert(path).inserted else { break }
                        paths.append(path)
                        directory.deleteLastPathComponent()
                    }
                }
            }
            try Task.checkCancellation()
            return paths
        } onCancel: { @Sendable in
            runner.cancel()
        }
    }
}
