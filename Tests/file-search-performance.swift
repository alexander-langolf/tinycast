import Foundation

@main
struct FileSearchPerformance {
    @MainActor static func main() async throws {
        let client = FSearchClient()
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let arguments = Array(CommandLine.arguments.dropFirst())
        let queries = arguments.isEmpty ? ["a", "e", "swift", "pdf", "project"] : arguments
        // The second list is deliberately heavy, so the run prices pattern matching.
        let policies = [
            (
                "shipped",
                FileSearchPolicy(
                    scopes: FileSearchScope.defaultScopes, ignorePatterns: [],
                    homeDirectory: homeDirectory)
            ),
            (
                "+patterns",
                FileSearchPolicy(
                    scopes: FileSearchScope.defaultScopes,
                    ignorePatterns: ["*.tmp", "*.log", "**/[Cc]ache/**", "**/Logs/**", "vendor"],
                    homeDirectory: homeDirectory)
            )
        ]

        print(
            "File search latency (recents: Spotlight, typed queries: fsearch); the palette adds a 120 ms debounce"
        )
        print("Home: \(homeDirectory.path)")
        for (label, policy) in policies {
            // The empty query is the blank screen's own list, and its latency is the one felt most.
            for query in [""] + queries {
                try await measure(query: query, policy: policy, label: label, client: client)
            }
        }
    }

    @MainActor private static func measure(
        query: String, policy: FileSearchPolicy, label: String, client: FSearchClient
    ) async throws {
        var samples: [Double] = []
        var first = 0.0
        var resultCount = 0
        for run in 0..<6 {
            let start = ContinuousClock.now
            let results =
                query.isEmpty
                ? try FileSearchService.recents(policy: policy)
                : try await client.search(query: query, filter: .all, policy: policy)
            let elapsed = milliseconds(start.duration(to: .now))
            if run == 0 {
                first = elapsed
            } else {
                samples.append(elapsed)
            }
            resultCount = results.count
        }
        let ordered = samples.sorted()
        let name = "\(label) \(query.isEmpty ? "(recents)" : query)"
            .padding(toLength: 22, withPad: " ", startingAt: 0)
        let metrics = String(
            format: "first %7.2f ms  repeat median %7.2f ms  max %7.2f ms  %3d results",
            first, ordered[ordered.count / 2], ordered.last ?? 0, resultCount)
        print("\(name) \(metrics)")
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
