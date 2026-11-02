// Times clipboard search over a 1,000-item corpus against the 5 ms warm budget. JSON on stdout.
import Foundation

@main
enum ForkSearchPerformance {
    static let budgetMilliseconds = 5.0
    static let warmRuns = 9

    static func milliseconds(_ start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
    }

    static func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    static func main() throws {
        ForkSearch.setEnabled(true)
        let raws = ForkSearchCorpus.items(count: 1_000, seed: 20_260_617)
        let prepareStart = ContinuousClock.now
        let prepared = raws.map(ForkSearch.ClipboardText.init)
        let coldPrepareMilliseconds = milliseconds(prepareStart)

        var checksum = 0
        var results: [[String: Any]] = []
        var overBudget: [String] = []
        for text in ForkSearchCorpus.queries {
            let query = ForkSearch.Query(text, profile: .fuzzy)
            var warm: [Double] = []
            for _ in 0..<warmRuns {
                let start = ContinuousClock.now
                for candidate in prepared {
                    checksum &+= ForkSearch.clipboardScore(query, candidate) ?? 0
                }
                warm.append(milliseconds(start))
            }

            let coldStart = ContinuousClock.now
            for raw in raws {
                checksum &+= ForkSearch.clipboardScore(query, ForkSearch.ClipboardText(raw)) ?? 0
            }
            let coldMilliseconds = milliseconds(coldStart)

            let warmMedian = median(warm)
            results.append([
                "query": text, "warm_median_ms": warmMedian, "cold_ms": coldMilliseconds
            ])
            if warmMedian > budgetMilliseconds { overBudget.append(text) }
        }

        let output: [String: Any] = [
            "items": raws.count, "cold_prepare_ms": coldPrepareMilliseconds,
            "budget_ms": budgetMilliseconds, "queries": results, "checksum": checksum
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data + Data([10]))

        if !overBudget.isEmpty {
            let list = overBudget.map { "\"\($0)\"" }.joined(separator: ", ")
            FileHandle.standardError.write(Data("warm median over \(budgetMilliseconds) ms: \(list)\n".utf8))
            exit(1)
        }
    }
}
