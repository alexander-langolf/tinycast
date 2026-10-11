import Foundation
import UniformTypeIdentifiers

enum ForkRipgrepQuery {
    private struct Word: Sendable {
        let term: ForkSearch.Term
        let bytes: [UInt8]?
        let maximumScore: Int

        init(_ term: ForkSearch.Term) {
            self.term = term
            maximumScore =
                ForkFzf.scoreMatch * term.text.count
                + ForkFzf.bonusDelimiter * (term.text.count + 1)
            bytes =
                term.text.allSatisfy { $0.asciiValue != nil }
                ? term.text.map { $0.asciiValue! } : nil
        }
    }

    private struct Candidate: Sendable {
        let path: String
        let score: Int
        let pathname: Int
        let length: Int
        let offset: Int

        func precedes(_ other: Candidate) -> Bool {
            if score != other.score { return score > other.score }
            if pathname != other.pathname { return pathname < other.pathname }
            if length != other.length { return length < other.length }
            return offset < other.offset
        }
    }

    nonisolated static func search(
        paths: [String], query: String, policy: FileSearchPolicy, filter: FileSearchFilter
    ) throws -> [FileSearchResult] {
        try search(
            paths: paths, query: query, policy: policy, filter: filter,
            candidateLimit: FileSearchQuery.resultLimit)
    }

    nonisolated private static func search(
        paths: [String], query: String, policy: FileSearchPolicy, filter: FileSearchFilter,
        candidateLimit: Int
    ) throws -> [FileSearchResult] {
        try Task.checkCancellation()
        let words = ForkSearch.terms(query, profile: .fuzzy).map(Word.init)
        let positive = words.filter { !$0.term.negated }
        guard !positive.isEmpty else { return [] }
        let maximumScore = positive.reduce(0) { $0 + $1.maximumScore }
        let home = policy.homeDirectory.standardizedFileURL.path
        let roots = policy.directRoots.map { $0.standardizedFileURL.path }
        let homePrefix = Array((home + "/").utf8)
        var workspace = ForkFzf.PathWorkspace()
        var heap: [Candidate] = []
        heap.reserveCapacity(candidateLimit)
        for (offset, indexedPath) in paths.enumerated() {
            if offset.isMultiple(of: 128) { try Task.checkCancellation() }
            switch filter {
            case .all: break
            case .folders: if !indexedPath.hasSuffix("/") { continue }
            default: break
            }
            let candidate =
                indexedPath.utf8.withContiguousStorageIfAvailable { bytes in
                    score(
                        path: indexedPath, bytes: bytes, words: words, homePrefix: homePrefix,
                        offset: offset, maximumScore: maximumScore,
                        minimumScore: heap.count == candidateLimit ? heap[0].score : 0,
                        workspace: &workspace)
                }
                ?? Array(indexedPath.utf8).withUnsafeBufferPointer { bytes in
                    score(
                        path: indexedPath, bytes: bytes, words: words, homePrefix: homePrefix,
                        offset: offset, maximumScore: maximumScore,
                        minimumScore: heap.count == candidateLimit ? heap[0].score : 0,
                        workspace: &workspace)
                }
            guard let candidate,
                heap.count < candidateLimit || candidate.precedes(heap[0]),
                contains(candidate.path, home: home, roots: roots, includesHome: policy.includesHome),
                !ForkRipgrepPolicy.excludes(candidate.path, ignore: policy.ignore, home: home)
            else { continue }
            insert(candidate, into: &heap, limit: candidateLimit)
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
        if results.count < FileSearchQuery.resultLimit, heap.count == candidateLimit,
            candidateLimit < FileSearchQuery.candidateLimit
        {
            return try search(
                paths: paths, query: query, policy: policy, filter: filter,
                candidateLimit: FileSearchQuery.candidateLimit)
        }
        return results
    }

    nonisolated private static func contains(
        _ path: String, home: String, roots: [String], includesHome: Bool
    ) -> Bool {
        if includesHome && (path == home || path.hasPrefix(home + "/")) { return true }
        return roots.contains { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }
    }

    nonisolated private static func score(
        path: String, bytes: UnsafeBufferPointer<UInt8>, words: [Word], homePrefix: [UInt8],
        offset: Int, maximumScore: Int, minimumScore: Int, workspace: inout ForkFzf.PathWorkspace
    ) -> Candidate? {
        let insideHome =
            bytes.count >= homePrefix.count
            && homePrefix.withUnsafeBufferPointer {
                memcmp(bytes.baseAddress!, $0.baseAddress!, homePrefix.count) == 0
            }
        let start = insideHome ? homePrefix.count : 0
        let end = bytes.count - (bytes.last == 47 ? 1 : 0)
        guard start < end else { return nil }
        let text = UnsafeBufferPointer(rebasing: bytes[start..<end])
        var folded: [UInt8]?
        for word in words where !word.term.negated {
            guard let term = word.bytes else { continue }
            switch asciiSubsequence(term, in: text) {
            case false?: return nil
            case nil:
                if folded == nil {
                    folded = Array(FuzzyMatch.normalized(String(decoding: text, as: UTF8.self)).utf8)
                }
                guard folded!.withUnsafeBufferPointer({ asciiSubsequence(term, in: $0) == true })
                else { return nil }
            default: break
            }
        }
        let separator = text.lastIndex(of: 47) ?? -1
        let dotStart = text[separator + 1] == 46 ? separator + 2 : nil
        let ascii = isASCII(text)
        var total = 0
        var begin = Int.max
        var remaining = maximumScore
        for word in words {
            if !word.term.negated {
                remaining -= word.maximumScore
            }
            let hit: ForkFzf.PathHit?
            if ascii, let term = word.bytes {
                hit = workspace.match(
                    term, in: text, exact: word.term.exact, prefix: word.term.prefix,
                    suffix: word.term.suffix,
                    dotStart: !word.term.prefix && term.first != 46 ? dotStart : nil,
                    minimumScore: word.term.negated ? 0 : minimumScore - total - remaining)
            } else {
                let relative = String(decoding: text, as: UTF8.self)
                hit = ForkSearch.hit(word.term, in: relative, scheme: .path).map {
                    ForkFzf.PathHit(score: $0.score, start: $0.positions.first ?? 0)
                }
            }
            if word.term.negated {
                if hit != nil { return nil }
            } else {
                guard let hit else { return nil }
                total += hit.score
                if total + remaining < minimumScore { return nil }
                begin = min(begin, hit.start)
            }
        }
        let pathname =
            begin >= separator
            ? begin - separator - (dotStart != nil && begin >= dotStart! ? 1 : 0) : Int.max
        return Candidate(
            path: end == bytes.count ? path : String(path.dropLast()), score: total,
            pathname: pathname,
            length: ascii ? text.count : String(decoding: text, as: UTF8.self).unicodeScalars.count,
            offset: offset)
    }

    nonisolated private static func asciiSubsequence(
        _ word: [UInt8], in text: UnsafeBufferPointer<UInt8>
    ) -> Bool? {
        let end = text.baseAddress! + text.count
        var cursor = text.baseAddress!
        for byte in word {
            let remaining = end - cursor
            let lower = memchr(cursor, Int32(byte), remaining)?.assumingMemoryBound(to: UInt8.self)
            let upper =
                (97...122).contains(byte)
                ? memchr(cursor, Int32(byte - 32), remaining)?.assumingMemoryBound(to: UInt8.self) : nil
            let found: UnsafePointer<UInt8>?
            switch (lower, upper) {
            case let (lower?, upper?): found = UnsafePointer(min(lower, upper))
            case let (lower?, nil): found = UnsafePointer(lower)
            case let (nil, upper?): found = UnsafePointer(upper)
            case (nil, nil): return isASCII(text) ? false : nil
            }
            cursor = found! + 1
        }
        return true
    }

    nonisolated private static func isASCII(_ text: UnsafeBufferPointer<UInt8>) -> Bool {
        var index = 0
        while index + 8 <= text.count {
            let block = UnsafeRawPointer(text.baseAddress! + index).loadUnaligned(as: UInt64.self)
            if block & 0x8080_8080_8080_8080 != 0 { return false }
            index += 8
        }
        return text[index...].allSatisfy { $0 < 128 }
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
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey]),
            values.isApplication != true
        else { return nil }
        let isDirectory = values.isDirectory == true
        switch filter {
        case .all: break
        case .folders: if !isDirectory { return nil }
        default:
            let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
            guard filter.accepts(contentType: contentType, isDirectory: isDirectory) else { return nil }
        }
        return FileSearchResult(
            url: url, isDirectory: isDirectory, homeDirectory: policy.homeDirectory)
    }
}
