import Foundation

@MainActor
final class ForkFileSearchService {
    private var supplement: Task<Void, Never>?
    private var revision = 0
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

    func search(
        query: String, policy: FileSearchPolicy, filter: FileSearchFilter,
        publish: @escaping @MainActor @Sendable ([FileSearchResult]) -> Void
    ) async throws {
        cancel()
        let currentRevision = revision
        let initial = try await Self.candidates(
            query: query, policy: policy, filter: filter, fuzzy: false)
        try Task.checkCancellation()
        guard revision == currentRevision else { return }
        publish(FileSearchQuery.rank(initial, for: query, ignoring: policy.ignore))
        supplement = Task {
            guard
                let additional = try? await Self.candidates(
                    query: query, policy: policy, filter: filter, fuzzy: true), !Task.isCancelled
            else { return }
            let merged = ForkSearch.mergePaths(initial, additional, id: { $0.id })
            publish(
                FileSearchQuery.rank(
                    merged.filter { !self.removed.contains($0.id) },
                    for: query, ignoring: policy.ignore))
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
        } onCancel: {
            worker.cancel()
        }
    }
}
