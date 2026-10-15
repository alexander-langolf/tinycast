import Foundation

/// Reads and writes the edited file off the main actor; the page never touches the disk.
enum MonacoFileIO {
    struct Loaded: Sendable {
        let document: MonacoDocument
        let text: String
    }

    @concurrent
    static func load(path: String) async -> Result<Loaded, MonacoDocument.Failure> {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let size = values.fileSize, let modified = values.contentModificationDate
        else { return .failure(.unreadable) }
        guard size <= MonacoDocument.sizeLimit else {
            return .failure(.tooLarge(bytes: size, limit: MonacoDocument.sizeLimit))
        }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        return MonacoDocument.decode(data).map {
            Loaded(document: MonacoDocument(path: path, modified: modified), text: $0)
        }
    }

    /// Writes through a symlink to its target and keeps the file's permissions; returns the new date.
    @concurrent
    static func save(text: String, path: String) async throws -> Date {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let permissions = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        try Data(text.utf8).write(to: url, options: .atomic)
        if let permissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
        return try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            ?? Date()
    }

    static func modificationDate(path: String) -> Date? {
        try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }
}
