import Foundation

enum FileSearchQuery {
    static let candidateLimit = 1_000
    static let resultLimit = 200
    /// A blank screen is a shortlist, not a browser: enough rows to reach, never to scroll far.
    static let recentLimit = 20

    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \Character.isWhitespace).map(String.init)
    }

    /// Both, because macOS stamps `kMDItemLastUsedDate` on few opens now, and Spotlight sorts on one.
    enum RecentStamp: String, CaseIterable, Sendable {
        case changed = "kMDItemFSContentChangeDate"
        case used = "kMDItemLastUsedDate"

        /// Spotlight's own literal, so no clock is injected; editing is constant, so it is shorter.
        var window: String {
            switch self {
            case .changed: return "$time.now(-259200)"
            case .used: return "$time.now(-2592000)"
            }
        }
    }

    static func recentExpression(
        stamp: RecentStamp, excluding exclusions: [String] = [], filter: FileSearchFilter = .all
    ) -> String {
        let touched = "\(stamp.rawValue) > \(stamp.window)"
        let types = filter.spotlightClause.map { [$0] } ?? []
        let excludes = exclusions.map { "kMDItemFSName != \"\(escapeGlob($0))\"cd" }
        return ([touched] + types + excludes).joined(separator: " && ")
    }

    /// Hidden paths and bundle contents are what keep File Search permission-free.
    static func isExcludedPath(
        _ path: String, ignoring ignore: FileSearchIgnoreList, showsHidden: Bool = false
    ) -> Bool {
        let structural = path.split(separator: "/").contains { component in
            let hidden = component.hasPrefix(".") && component != "." && component != ".."
            let alwaysExcluded = component == ".git" || component == ".Trash"
            return (hidden && (!showsHidden || alwaysExcluded))
                || component.lowercased().hasSuffix(".app")
        }
        return structural || ignore.excludes(path: path)
    }

    /// A user pattern keeps its `*`, since that is the one wildcard Spotlight evaluates.
    private static func escapeGlob(_ pattern: String) -> String {
        quoting(pattern, escaping: ["\\", "\""])
    }

    private static func quoting(_ text: String, escaping characters: Set<Character>) -> String {
        var escaped = ""
        for character in text {
            if characters.contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
}
