import Foundation

enum RipgrepSubtreeScanner {
    @concurrent
    static func scan(
        _ request: DirectoryLister.Request, executable: URL, patterns: [String],
        receive: @MainActor @Sendable (DirectoryLister.Batch) async -> Void
    ) async throws {
        try Task.checkCancellation()
        let root = URL(filePath: request.folder)
        try DirectoryLister.validateFolder(root)
        do { _ = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: []) } catch
        { throw DirectoryLister.failure(error, folder: request.folder) }
        let traversal = DirectoryLister.Request(
            folder: request.folder, home: request.home, showHidden: false,
            ignore: request.ignore, pickedPaths: request.pickedPaths)
        guard try DirectoryLister.entry(root, request: traversal) != nil,
            !ForkRipgrepPolicy.excludes(root.path, ignore: request.ignore)
        else { await receive(.init(isFinal: true)); return }
        let runner = ForkRipgrepProcess(
            executable: executable, directory: root,
            arguments: ForkRipgrepPolicy.arguments(
                patterns: patterns, home: root.path, subtree: true,
                depthLimit: SubtreeWalker.depthLimit) + ["--", root.path])
        try await withTaskCancellationHandler {
            defer { runner.finish() }
            try Task.checkCancellation()
            try runner.start()
            var folders: [String: Bool] = [root.path: true]
            var batch = DirectoryLister.Batch()
            var count = 0
            scanning: while let paths = try runner.next() {
                for path in paths {
                    try Task.checkCancellation()
                    guard path.hasPrefix(root.path == "/" ? "/" : root.path + "/"),
                        !ForkRipgrepPolicy.excludes(path, ignore: request.ignore, packages: false)
                    else { continue }
                    let url = URL(filePath: path)
                    var ancestors: [URL] = []
                    var parent = url.deletingLastPathComponent()
                    while parent.path != root.path {
                        ancestors.append(parent)
                        parent.deleteLastPathComponent()
                    }
                    var accepted = true
                    for folder in ancestors.reversed() {
                        if let visible = folders[folder.path] {
                            if !visible { accepted = false; break }
                            continue
                        }
                        let row = try DirectoryLister.entry(folder, request: traversal)
                        let visible = row?.isDirectory == true
                        folders[folder.path] = visible
                        guard let row else { accepted = false; break }
                        batch.rows.append(row)
                        count += 1
                        if batch.rows.count == 500 { await receive(batch); batch = .init() }
                        if count == SubtreeWalker.entryLimit { break scanning }
                        if !visible { accepted = false; break }
                    }
                    guard accepted, let row = try DirectoryLister.entry(url, request: traversal) else {
                        continue
                    }
                    batch.rows.append(row)
                    count += 1
                    if batch.rows.count == 500 { await receive(batch); batch = .init() }
                    if count == SubtreeWalker.entryLimit { break scanning }
                }
            }
            runner.finish()
            for path in request.pickedPaths {
                try Task.checkCancellation()
                if DirectoryLister.isVanished(path) { batch.vanished.insert(path) }
            }
            batch.isFinal = true
            try Task.checkCancellation()
            await receive(batch)
        } onCancel: { @Sendable in
            runner.cancel()
        }
    }
}
