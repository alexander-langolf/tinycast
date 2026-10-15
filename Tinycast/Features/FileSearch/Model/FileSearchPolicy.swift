import Foundation

/// Decides what a configured scope list means: which roots are searched, and what to drop.
struct FileSearchPolicy: Sendable, Equatable {
    let homeDirectory: URL
    /// Home is held apart because `~/Library` can never be a scope, so it is expanded.
    let directRoots: [URL]
    let includesHome: Bool
    let ignore: FileSearchIgnoreList
    let showsHidden: Bool

    init(
        scopes: [String], ignorePatterns: [String], homeDirectory: URL, showsHidden: Bool = false
    ) {
        self.homeDirectory = homeDirectory
        self.showsHidden = showsHidden
        let home = homeDirectory.standardizedFileURL.path
        let roots = FileSearchScope.roots(for: scopes, homeDirectory: homeDirectory)
        directRoots = roots.filter { $0.path != home }
        includesHome = roots.count != directRoots.count
        ignore = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults + ignorePatterns)
    }

    var scopeRoots: [URL] {
        (includesHome ? [homeDirectory.standardizedFileURL] : []) + directRoots
    }

    /// Inside a scope, and not in `~/Library` unless the user named a folder there themselves.
    func admits(path: String) -> Bool {
        func within(_ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }
        if directRoots.contains(where: { within($0.path) }) { return true }
        let home = homeDirectory.standardizedFileURL.path
        guard includesHome, within(home) else { return false }
        guard within(home + "/Library") else { return true }
        return within(home + "/Library/CloudStorage")
            || within(home + "/Library/Mobile Documents/com~apple~CloudDocs")
    }
}
