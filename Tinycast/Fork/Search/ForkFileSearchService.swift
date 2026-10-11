import Foundation

@MainActor
final class ForkFileSearchService {
    private var supplement: Task<Void, Never>?
    private var revision = 0
    var index: ForkRipgrepIndex?
    /// Rows trashed after the first batch published; the merged batch must not bring them back.
    private var removed = Set<String>()

    isolated deinit { supplement?.cancel() }

    func remove(_ id: String) { removed.insert(id) }

    func cancel() {
        revision &+= 1
        removed = []
        supplement?.cancel()
        supplement = nil
    }

    /// True while the index is the only source that can answer, so older rows must not stand in for it.
    func awaitsIndex(policy: FileSearchPolicy) -> Bool {
        index?.supports(policy) == true && index?.paths == nil
    }

    func handles(_ query: String, policy: FileSearchPolicy) -> Bool {
        !query.isEmpty && (index?.supports(policy) == true || ForkSearch.fileNeedsGlob(query))
    }

    func search(
        query: String, policy: FileSearchPolicy, filter: FileSearchFilter,
        publish: @escaping @MainActor @Sendable ([FileSearchResult]) -> Void
    ) async throws {
        cancel()
        let currentRevision = revision
        let index = index.flatMap { $0.supports(policy) ? $0 : nil }
        index?.prepare()
        if let paths = index?.paths {
            supplement = Task {
                guard
                    let results = try? await Self.indexed(
                        paths: paths, query: query, policy: policy, filter: filter),
                    !Task.isCancelled, revision == currentRevision
                else { return }
                publish(results.filter { !removed.contains($0.id) })
            }
            return
        }
        let initial = try await Self.candidates(
            query: query, policy: policy, filter: filter, fuzzy: false)
        try Task.checkCancellation()
        guard revision == currentRevision else { return }
        let ranked = FileSearchQuery.rank(initial, for: query, ignoring: policy.ignore)
        // An empty answer while the index builds would read as "No files found"; the index answers next.
        if !(ranked.isEmpty && index != nil) { publish(ranked) }
        supplement = Task {
            if ForkSearch.fileNeedsGlob(query),
                let additional = try? await Self.candidates(
                    query: query, policy: policy, filter: filter, fuzzy: true),
                !Task.isCancelled, revision == currentRevision
            {
                let merged = ForkSearch.mergePaths(initial, additional, id: { $0.id })
                let ranked = FileSearchQuery.rank(
                    merged.filter { !self.removed.contains($0.id) },
                    for: query, ignoring: policy.ignore)
                if !(ranked.isEmpty && index != nil) { publish(ranked) }
            }
            guard let paths = await index?.readyPaths(), !Task.isCancelled,
                revision == currentRevision,
                let results = try? await Self.indexed(
                    paths: paths, query: query, policy: policy, filter: filter),
                !Task.isCancelled, revision == currentRevision
            else { return }
            publish(results.filter { !removed.contains($0.id) })
        }
    }

    nonisolated private static func indexed(
        paths: [String], query: String, policy: FileSearchPolicy, filter: FileSearchFilter
    ) async throws -> [FileSearchResult] {
        let worker = Task.detached(priority: .userInitiated) {
            try ForkRipgrepQuery.search(paths: paths, query: query, policy: policy, filter: filter)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { @Sendable in
            worker.cancel()
        }
    }

    nonisolated private static func candidates(
        query: String, policy: FileSearchPolicy, filter: FileSearchFilter, fuzzy: Bool
    ) async throws -> [FileSearchResult] {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try FileSearchService.search(
                query: query, policy: policy, filter: filter,
                forkFuzzy: fuzzy, forkCandidates: true)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { @Sendable in
            worker.cancel()
        }
    }
}
