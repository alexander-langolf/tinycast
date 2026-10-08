import Foundation

enum ForkFileSearchService {
    nonisolated static func search(
        query: String, policy: FileSearchPolicy, filter: FileSearchFilter,
        onPartial: @escaping @MainActor @Sendable ([FileSearchResult]) -> Void
    ) async throws -> [FileSearchResult] {
        async let fast = candidates(query: query, policy: policy, filter: filter, fuzzy: false)
        async let fuzzy = candidates(query: query, policy: policy, filter: filter, fuzzy: true)
        let initial = try await fast
        try Task.checkCancellation()
        await onPartial(FileSearchQuery.rank(initial, for: query, ignoring: policy.ignore))
        let additional = (try? await fuzzy) ?? []
        try Task.checkCancellation()
        return FileSearchQuery.rank(
            ForkSearch.mergePaths(initial, additional, id: { $0.id }), for: query, ignoring: policy.ignore)
    }

    nonisolated private static func candidates(
        query: String, policy: FileSearchPolicy, filter: FileSearchFilter, fuzzy: Bool
    ) async throws -> [FileSearchResult] {
        let worker = Task.detached(priority: .userInitiated) {
            try FileSearchService.search(
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
