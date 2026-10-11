import Foundation

enum DirectoryLister {
    struct Request: Sendable {
        let folder: String
        let home: String
        let showHidden: Bool
        let ignore: FileSearchIgnoreList
        let pickedPaths: [String]
    }

    struct Batch: Sendable {
        var rows: [FileSearchResult] = []
        var vanished: Set<String> = []
        var isFinal = false
    }

    enum Failure: Error, Sendable {
        case missing(String)
        case denied(String)
        case unreadable(String)
    }

    nonisolated static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey, .isPackageKey,
        .contentModificationDateKey, .fileSizeKey
    ]

    @concurrent
    static func list(
        _ request: Request, receive: @MainActor @Sendable (Batch) async -> Void
    ) async throws {
        try Task.checkCancellation()
        let manager = FileManager.default
        let folder = URL(filePath: request.folder)
        try validateFolder(folder)
        let children: [URL]
        do { children = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) } catch
        { throw failure(error, folder: request.folder) }
        var batch = Batch()
        for child in children {
            try Task.checkCancellation()
            if let row = try entry(child, request: request) { batch.rows.append(row) }
            if batch.rows.count == 500 {
                await receive(batch)
                batch = Batch()
            }
        }
        for path in request.pickedPaths {
            try Task.checkCancellation()
            if isVanished(path) { batch.vanished.insert(path) }
        }
        batch.isFinal = true
        try Task.checkCancellation()
        await receive(batch)
    }

    @concurrent
    static func rank(_ rows: [FileSearchResult], filter: String) async throws -> [FileSearchResult] {
        try Task.checkCancellation()
        let ranked = FileNavigatorState.ranked(rows, filter: filter, shouldStop: { Task.isCancelled })
        try Task.checkCancellation()
        return ranked
    }

    nonisolated static func validateFolder(_ folder: URL) throws {
        let values: URLResourceValues
        do {
            values = try folder.resolvingSymlinksInPath().resourceValues(forKeys: [
                .isDirectoryKey, .isPackageKey
            ])
        } catch { throw failure(error, folder: folder.path) }
        guard values.isDirectory == true, values.isPackage != true,
            !["app", "pkg"].contains(folder.pathExtension.lowercased())
        else { throw Failure.missing(folder.path) }
        try checkLoop(folder)
    }

    @concurrent
    static func recoveryFolder(from folder: String, home: String) async throws -> String {
        try Task.checkCancellation()
        let recovery: String
        do {
            try validateFolder(URL(filePath: folder))
            recovery = folder
        } catch Failure.missing(_) {
            recovery = home
        } catch {
            recovery = folder
        }
        try Task.checkCancellation()
        return recovery
    }

    nonisolated static func entry(
        _ url: URL, request: Request, recursive: Bool = false
    ) throws -> FileSearchResult? {
        let values: URLResourceValues
        do { values = try url.resourceValues(forKeys: Set(keys)) } catch {
            if (error as NSError).code == NSFileReadNoSuchFileError { return nil }
            throw error
        }
        if recursive {
            guard !ForkRipgrepPolicy.excludes(
                url.path, ignore: request.ignore, home: request.home, packages: false)
            else { return nil }
        } else if !request.showHidden {
            guard values.isHidden != true, !url.lastPathComponent.hasPrefix("."),
                !request.ignore.excludes(path: url.path)
            else { return nil }
        }
        var target = values
        if values.isSymbolicLink == true {
            do {
                target = try url.resolvingSymlinksInPath().resourceValues(forKeys: [
                    .isDirectoryKey, .isPackageKey
                ])
            } catch {
                if isVanished(url.resolvingSymlinksInPath().path) { return nil }
                throw error
            }
        }
        let package = target.isPackage == true || ["app", "pkg"].contains(url.pathExtension.lowercased())
        return FileSearchResult(
            url: url, isDirectory: target.isDirectory == true && !package,
            homeDirectory: URL(filePath: request.home))
    }

    nonisolated static func isVanished(_ path: String) -> Bool {
        do { _ = try URL(filePath: path).resourceValues(forKeys: [.isDirectoryKey]); return false } catch {
            let error = error as NSError
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            return error.code == NSFileReadNoSuchFileError
                || (error.domain == NSPOSIXErrorDomain && error.code == 2)
                || (underlying?.domain == NSPOSIXErrorDomain && underlying?.code == 2)
        }
    }

    nonisolated static func checkLoop(_ folder: URL) throws {
        let canonical = folder.resolvingSymlinksInPath().path
        var parent = folder.deletingLastPathComponent()
        guard folder.path != "/" else { return }
        while true {
            if parent.resolvingSymlinksInPath().path == canonical {
                throw Failure.unreadable("Symlink loop at " + folder.path)
            }
            if parent.path == "/" { return }
            parent.deleteLastPathComponent()
        }
    }

    nonisolated static func failure(_ error: any Error, folder: String) -> Failure {
        let error = error as NSError
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        if error.code == NSFileReadNoSuchFileError { return .missing(folder) }
        if error.code == NSFileReadNoPermissionError
            || underlying?.code == 1 || underlying?.code == 13
            || (error.domain == NSPOSIXErrorDomain && [1, 13].contains(error.code))
        {
            return .denied(folder)
        }
        return .unreadable(error.localizedDescription)
    }
}
