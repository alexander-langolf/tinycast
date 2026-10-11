import Foundation

enum SubtreeWalker {
    nonisolated static let depthLimit = 8
    nonisolated static let entryLimit = 50_000

    @concurrent
    static func walk(
        _ request: DirectoryLister.Request,
        receive: @MainActor @Sendable (DirectoryLister.Batch) async -> Void
    ) async throws {
        try Task.checkCancellation()
        let manager = FileManager.default
        let root = URL(filePath: request.folder)
        try DirectoryLister.validateFolder(root)
        do { _ = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: []) } catch {
            throw DirectoryLister.failure(error, folder: request.folder)
        }
        guard
            let enumerator = manager.enumerator(
                at: root, includingPropertiesForKeys: DirectoryLister.keys,
                options: [.skipsPackageDescendants])
        else { throw DirectoryLister.Failure.unreadable("Couldn’t read this folder") }
        let visibleRoot = try DirectoryLister.entry(root, request: request, recursive: true) != nil
        var canonicalFolders: Set<String> = [root.resolvingSymlinksInPath().path]
        var batch = DirectoryLister.Batch()
        var count = 0
        while visibleRoot, let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            count += 1
            if count > entryLimit { break }
            guard let row = try DirectoryLister.entry(url, request: request, recursive: true) else {
                enumerator.skipDescendants()
                continue
            }
            batch.rows.append(row)
            if !row.isDirectory {
                enumerator.skipDescendants()
            } else {
                let canonical = url.resolvingSymlinksInPath().path
                if enumerator.level >= depthLimit || !canonicalFolders.insert(canonical).inserted {
                    enumerator.skipDescendants()
                }
            }
            if batch.rows.count == 500 {
                await receive(batch)
                batch = DirectoryLister.Batch()
            }
        }
        for path in request.pickedPaths {
            try Task.checkCancellation()
            if DirectoryLister.isVanished(path) { batch.vanished.insert(path) }
        }
        batch.isFinal = true
        try Task.checkCancellation()
        await receive(batch)
    }
}
