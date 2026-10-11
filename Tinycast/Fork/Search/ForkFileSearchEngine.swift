import Foundation

enum ForkFileSearchEngine: String, CaseIterable, Sendable {
    case spotlight
    case ripgrep

    var title: String { self == .spotlight ? "Spotlight" : "ripgrep" }

    nonisolated static func executable(
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> URL? {
        let candidates =
            ["/opt/homebrew/bin/rg", "/usr/local/bin/rg"]
            + path.split(separator: ":", omittingEmptySubsequences: false).map {
                URL(filePath: $0.isEmpty ? "." : String($0)).appending(path: "rg").path
            }
        return candidates.first { candidate in
            var directory: ObjCBool = false
            return FileManager.default.isExecutableFile(atPath: candidate)
                && FileManager.default.fileExists(atPath: candidate, isDirectory: &directory)
                && !directory.boolValue
        }.map { URL(filePath: $0) }
    }
}
