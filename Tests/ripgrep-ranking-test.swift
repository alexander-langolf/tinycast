// Pins the ripgrep index ranking: a fuzzy query that spans folder and filename still lists the file.
import Foundation

@main
struct RipgrepRankingTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ description: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)  \(detail())"); failures += 1
        }
    }

    static let home = FileManager.default.temporaryDirectory
        .appending(path: "ripgrep-ranking-\(UUID().uuidString)").resolvingSymlinksInPath()
    static let components = home.path + "/work/stardust-design-system/packages/react/src/components"
    static let button = components + "/button/button.tsx"

    static var paths: [String] {
        [
            button,
            components + "/card/card-button.tsx",
            components + "/card/card-button.test.tsx",
            home.path
                + "/work/stardust-design-system/packages/phoenix/test/stardust_phoenix/buttons_test.exs",
            home.path + "/work/user_home/src/app/_components/RunSeedsButton.tsx",
            home.path + "/github/tinycast/Tinycast/Palette/PaletteWindowController.swift"
        ] + (0..<300).map { home.path + "/work/app\($0)/src/components/Item\($0).tsx" }
    }

    /// Results are resolved against disk, so the fixture has to exist.
    static func materialize() throws {
        for path in paths {
            let url = URL(filePath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
    }

    static func ids(_ query: String, scopes: [String]) throws -> [String] {
        let policy = FileSearchPolicy(scopes: scopes, ignorePatterns: [], homeDirectory: home)
        return try ForkRipgrepQuery.search(paths: paths, query: query, policy: policy, filter: .all).map(\.id)
    }

    static func main() throws {
        try materialize()
        defer { try? FileManager.default.removeItem(at: home) }
        let scopeSets = [["~"], ["~/LangolfVault", "~/work", "~/github", "~/Downloads"]]
        // The second query is the one that returned "No files found": s-t-a-r-d-u-s-t / b-u-t-t-o-n / t-s-x.
        for query in ["strdbtntsx", "strdstbtntsx", "stardust/button.tsx", "strdst btn tsx"] {
            for scopes in scopeSets {
                let found = try ids(query, scopes: scopes)
                check(
                    "\(query) lists stardust button.tsx in \(scopes.count) scope(s)", found.contains(button),
                    "\(found.prefix(5))")
            }
        }
        let on = ForkRipgrepPolicy.arguments(patterns: [], home: home.path, subtree: false)
        let off = ForkRipgrepPolicy.arguments(patterns: [], home: home.path, subtree: false, hidden: false)
        check("hidden files are listed by default", on.contains("--hidden"))
        check(
            "turning hidden off drops --hidden but keeps the .git exclusion",
            !off.contains("--hidden") && off.contains("!.git/") && on.count == off.count + 1)
        check("an unrelated query lists nothing", try ids("zzqqxx", scopes: ["~"]).isEmpty)
        if failures > 0 {
            print("\(failures) FAILED"); try? FileManager.default.removeItem(at: home); exit(1)
        }
    }
}
