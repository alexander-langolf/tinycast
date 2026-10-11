import Foundation

enum FileNavigatorPath: Equatable, Sendable {
    case folder(String, String)
    case global(String)
    case missing(String)

    static func candidate(_ input: String, home: String) -> (folder: String, filter: String)? {
        guard input.hasPrefix("~") || input.hasPrefix("/") else { return nil }
        if input == "~" { return (home, "") }
        let full = input.hasPrefix("~") ? home + input.dropFirst() : input
        guard let slash = full.lastIndex(of: "/") else { return ("/", full) }
        let directory = slash == full.startIndex ? "/" : String(full[..<slash])
        return (URL(filePath: directory).standardizedFileURL.path, String(full[full.index(after: slash)...]))
    }

    static func parseInput(_ input: String, home: String, folders: Set<String>) -> Self {
        guard let candidate = candidate(input, home: home) else { return .global(input) }
        return folders.contains(candidate.folder)
            ? .folder(candidate.folder, candidate.filter) : .missing(candidate.folder)
    }

    static func parent(_ path: String) -> String {
        URL(filePath: path).deletingLastPathComponent().path
    }

    static func display(_ path: String, home: String) -> String {
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static func directoryInput(_ path: String, home: String) -> String {
        path == "/" ? "/" : display(path, home: home) + "/"
    }

    static func relative(_ path: String, to folder: String) -> String {
        let destination = path.split(separator: "/")
        let origin = folder.split(separator: "/")
        let common = zip(destination, origin).prefix { $0.0 == $0.1 }.count
        let parts =
            Array(repeating: "..", count: origin.count - common)
            + destination.dropFirst(common).map(String.init)
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
