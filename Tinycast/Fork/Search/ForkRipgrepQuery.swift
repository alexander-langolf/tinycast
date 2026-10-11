import Foundation
import UniformTypeIdentifiers

enum ForkRipgrepQuery {
    private struct Word: Sendable {
        let term: ForkSearch.Term
        let bytes: [UInt8]?

        init(_ term: ForkSearch.Term) {
            self.term = term
            bytes =
                term.text.allSatisfy { $0.asciiValue != nil }
                ? term.text.map { $0.asciiValue! } : nil
        }
    }

    private struct Candidate: Sendable {
        let path: String
        let score: Int
        let nameLength: Int
        let offset: Int

        func precedes(_ other: Candidate) -> Bool {
            if score != other.score { return score > other.score }
            if nameLength != other.nameLength { return nameLength < other.nameLength }
            return offset < other.offset
        }
    }

    nonisolated static func search(
        paths: [String], query: String, policy: FileSearchPolicy, filter: FileSearchFilter
    ) throws -> [FileSearchResult] {
        try Task.checkCancellation()
        let words = ForkSearch.terms(query, profile: .fuzzy).map(Word.init)
        let positive = words.filter { !$0.term.negated }
        guard !positive.isEmpty else { return [] }
        let home = policy.homeDirectory.standardizedFileURL.path
        let roots = policy.directRoots.map { $0.standardizedFileURL.path }
        var heap: [Candidate] = []
        heap.reserveCapacity(FileSearchQuery.candidateLimit)
        for (offset, indexedPath) in paths.enumerated() {
            if offset.isMultiple(of: 128) { try Task.checkCancellation() }
            let isDirectory = indexedPath.hasSuffix("/")
            switch filter {
            case .all: break
            case .folders: if !isDirectory { continue }
            default: break
            }
            let path = isDirectory ? String(indexedPath.dropLast()) : indexedPath
            guard prefilter(positive, path: path),
                contains(path, home: home, roots: roots, includesHome: policy.includesHome),
                !FileSearchQuery.isExcludedPath(path, ignoring: policy.ignore),
                let candidate = score(path: path, words: words, home: home, offset: offset)
            else { continue }
            insert(candidate, into: &heap, limit: FileSearchQuery.candidateLimit)
        }
        try Task.checkCancellation()
        var results: [FileSearchResult] = []
        results.reserveCapacity(FileSearchQuery.resultLimit)
        for candidate in heap.sorted(by: { $0.precedes($1) }) {
            try Task.checkCancellation()
            guard let result = resolve(candidate.path, policy: policy, filter: filter) else {
                continue
            }
            results.append(result)
            if results.count == FileSearchQuery.resultLimit { break }
        }
        return results
    }

    nonisolated private static func prefilter(_ words: [Word], path: String) -> Bool {
        var folded: [Character]?
        for word in words {
            if let bytes = word.bytes, let matches = asciiSubsequence(bytes, in: path) {
                guard matches else { return false }
                continue
            }
            if folded == nil { folded = Array(FuzzyMatch.normalized(path)) }
            guard subsequence(word.term.text, in: folded!) else { return false }
        }
        return true
    }

    nonisolated private static func asciiSubsequence(_ word: [UInt8], in path: String) -> Bool? {
        var next = 0
        var needsFold = false
        for byte in path.utf8 {
            if byte >= 128 { needsFold = true }
            let folded = (65...90).contains(byte) ? byte + 32 : byte
            if folded == word[next] {
                next += 1
                if next == word.count { return true }
            }
        }
        return needsFold ? nil : false
    }

    nonisolated private static func subsequence(_ word: [Character], in path: [Character]) -> Bool {
        var next = 0
        for character in path where character == word[next] {
            next += 1
            if next == word.count { return true }
        }
        return false
    }

    nonisolated private static func contains(
        _ path: String, home: String, roots: [String], includesHome: Bool
    ) -> Bool {
        if includesHome && (path == home || path.hasPrefix(home + "/")) { return true }
        return roots.contains { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }
    }

    nonisolated private static func score(
        path: String, words: [Word], home: String, offset: Int
    ) -> Candidate? {
        guard let separator = path.lastIndex(of: "/") else { return nil }
        let name = String(path[path.index(after: separator)...])
        let parent = String(path[..<separator])
        let folder =
            parent == home
            ? "~"
            : parent.hasPrefix(home + "/") ? "~" + parent.dropFirst(home.count) : parent
        var total = 0
        for word in words {
            let filename = ForkSearch.hit(word.term, in: name, scheme: .path)
            if word.term.negated {
                if filename != nil { return nil }
                continue
            }
            let directory = ForkSearch.hit(word.term, in: folder, scheme: .path)
            guard filename != nil || directory != nil else { return nil }
            total += max(
                filename?.score ?? Int.min, directory.map { Int(Double($0.score) * 0.6) } ?? Int.min)
        }
        return Candidate(path: path, score: total, nameLength: name.count, offset: offset)
    }

    nonisolated private static func insert(
        _ candidate: Candidate, into heap: inout [Candidate], limit: Int
    ) {
        if heap.count == limit {
            guard candidate.precedes(heap[0]) else { return }
            heap[0] = candidate
            var index = 0
            while index * 2 + 1 < heap.count {
                let left = index * 2 + 1
                let right = left + 1
                let worse = right < heap.count && heap[left].precedes(heap[right]) ? right : left
                guard heap[index].precedes(heap[worse]) else { break }
                heap.swapAt(index, worse)
                index = worse
            }
            return
        }
        heap.append(candidate)
        var index = heap.count - 1
        while index > 0 {
            let parent = (index - 1) / 2
            guard heap[parent].precedes(heap[index]) else { break }
            heap.swapAt(parent, index)
            index = parent
        }
    }

    nonisolated private static func resolve(
        _ path: String, policy: FileSearchPolicy, filter: FileSearchFilter
    ) -> FileSearchResult? {
        let url = URL(fileURLWithPath: path)
        guard
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .isHiddenKey, .contentTypeKey
            ]), values.isHidden != true, values.contentType?.conforms(to: .application) != true,
            filter.accepts(contentType: values.contentType, isDirectory: values.isDirectory == true)
        else { return nil }
        return FileSearchResult(
            url: url, isDirectory: values.isDirectory == true, homeDirectory: policy.homeDirectory)
    }
}
