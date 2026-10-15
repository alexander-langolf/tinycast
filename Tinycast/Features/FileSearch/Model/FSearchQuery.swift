import Foundation

/// Turns a typed query and its policy into fsearch's query string, and its hits into rows.
enum FSearchQuery {
    static let pageLimit = 400
    static let expandedLimit = 2_000

    /// `nil` when nothing could match: blank words, or a cleared scope list.
    static func text(words: String, filter: FileSearchFilter, policy: FileSearchPolicy) -> String? {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let roots = policy.scopeRoots
        guard !words.isEmpty, !roots.isEmpty else { return nil }
        var parts = [words]
        if let type = filter.fsearchType { parts.append("type:\(type)") }
        // A path word is a fuzzy term to fsearch, and it reorders results, so scopes stay local.
        return parts.joined(separator: " ")
    }

    struct Rows {
        let results: [FileSearchResult]
        /// A full page that filtering emptied below the cap may hide rows past it.
        let mayHaveMore: Bool
    }

    /// fsearch's order is kept; rows are only ever dropped.
    static func rows(
        from hits: [FSearchHit], requested: Int, policy: FileSearchPolicy, filter: FileSearchFilter
    ) -> Rows {
        var results: [FileSearchResult] = []
        for hit in hits
        where policy.admits(path: hit.path) && filter.admits(isDirectory: hit.isDirectory)
            && !FileSearchQuery.isExcludedPath(
                hit.path, ignoring: policy.ignore, showsHidden: policy.showsHidden)
        {
            results.append(
                FileSearchResult(
                    url: URL(fileURLWithPath: hit.path), isDirectory: hit.isDirectory,
                    homeDirectory: policy.homeDirectory))
            if results.count == FileSearchQuery.resultLimit { break }
        }
        let short = results.count < FileSearchQuery.resultLimit
        return Rows(results: results, mayHaveMore: short && hits.count >= requested)
    }
}
