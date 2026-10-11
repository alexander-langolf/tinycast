import Foundation
import OSLog

@MainActor
final class ForkRipgrepIndex {
    private var engine = ForkFileSearchEngine.spotlight
    private var hidden = false
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

    /// The first open after launch or a settings change builds the index while the query is still being typed.
    func paletteOpened() {
        guard used || paths == nil else { return }
        refreshIfNeeded()
    }

    func configure(engine: ForkFileSearchEngine, patterns: [String], hidden: Bool = false) {
        guard engine != self.engine || patterns != self.patterns || hidden != self.hidden else { return }
        self.engine = engine
        self.patterns = patterns
        self.hidden = hidden
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
        let hidden = hidden
        build = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                try await Self.load(executable: executable, home: home, patterns: patterns, hidden: hidden)
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
    private static func load(
        executable: URL, home: URL, patterns: [String], hidden: Bool
    ) async throws -> [String] {
        let runner = ForkRipgrepProcess(
            executable: executable, directory: home,
            arguments: ForkRipgrepPolicy.arguments(
                patterns: patterns, home: home.path, subtree: false, hidden: hidden))
        return try await withTaskCancellationHandler {
            defer { runner.finish() }
            try Task.checkCancellation()
            try runner.start()
            let ignore = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults + patterns)
            var paths: [String] = []
            var directories = Set<String>()
            let homePath = home.standardizedFileURL.path + "/"
            let homeEnd = homePath.index(before: homePath.endIndex)
            let libraryPrefix = homePath + "Library/"
            while let batch = try runner.next() {
                for relative in batch {
                    try Task.checkCancellation()
                    // ripgrep prints clean paths relative to `home`, so string joins replace URL round trips.
                    let path = homePath + relative
                    guard !path.hasPrefix(libraryPrefix),
                        !ForkRipgrepPolicy.excludes(path, ignore: ignore, home: home.path)
                    else { continue }
                    paths.append(path)
                    var end = path.endIndex
                    while let slash = path[..<end].lastIndex(of: "/"), slash > homeEnd {
                        let directory = String(path[...slash])
                        guard directories.insert(directory).inserted else { break }
                        paths.append(directory)
                        end = slash
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
