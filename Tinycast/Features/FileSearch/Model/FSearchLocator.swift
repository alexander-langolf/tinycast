import Foundation

enum FSearchLocator {
    /// `~/.local/bin` is where `fsearch install` puts it; a shell's PATH is never consulted.
    static func locate(
        home: URL, path: String, isExecutable: (String) -> Bool
    ) -> URL? {
        let installed = home.appending(path: ".local/bin/fsearch").path
        let candidates =
            [installed]
            + path.split(separator: ":", omittingEmptySubsequences: true).map {
                URL(filePath: String($0)).appending(path: "fsearch").path
            }
        return candidates.first(where: isExecutable).map { URL(filePath: $0) }
    }
}
