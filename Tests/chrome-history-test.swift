// Chrome history results: profile lookup, ranking, host icons, row order and the reader against a
// fixture History database.

import Foundation
import SQLite3

@main
struct ChromeHistoryTests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)\n  got  \(actual)\n  want \(expected)")
        }
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func entry(
        _ title: String, _ url: String, visits: Int = 1, daysAgo: Double = 1
    ) -> ChromeHistoryEntry {
        ChromeHistoryEntry(
            title: title, url: URL(string: url)!, visitCount: visits,
            lastVisit: now.addingTimeInterval(-daysAgo * 86_400))
    }

    static func main() async {
        epoch()
        profileLocation()
        ranking()
        hostIcons()
        rows()
        await reader()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func epoch() {
        expect(
            ChromeHistoryEntry.date(webKitMicroseconds: 11_644_473_600 * 1_000_000),
            Date(timeIntervalSince1970: 0), "WebKit epoch starts in 1601")
        expect(
            ChromeHistoryEntry.date(webKitMicroseconds: (11_644_473_600 + 1_500_000_000) * 1_000_000),
            Date(timeIntervalSince1970: 1_500_000_000), "WebKit microseconds convert to a Date")
    }

    static func profileLocation() {
        let root = URL(filePath: "/chrome", directoryHint: .isDirectory)
        func locate(_ json: String, exists: Bool = true) -> String? {
            ChromeProfileLocator.profileDirectory(
                localState: Data(json.utf8), userDataDirectory: root, exists: { _ in exists })?
                .lastPathComponent
        }
        expect(locate(#"{"profile":{"last_used":"Profile 1"}}"#), "Profile 1", "last_used names the profile")
        expect(locate(#"{"profile":{"last_used":"Profile 1"}}"#, exists: false), nil, "unknown profile")
        expect(locate(#"{"profile":{}}"#), nil, "no last_used")
        expect(locate("not json"), nil, "malformed Local State")
        expect(locate(#"{"profile":{"last_used":"../x"}}"#), nil, "path escape rejected")
    }

    static func ranking() {
        func titles(_ entries: [ChromeHistoryEntry], _ query: String) -> [String] {
            ChromeHistoryRanking.rank(entries, query: query, now: now).map(\.title)
        }
        let both = [
            entry("Docs for tinycast", "https://a.example/docs", visits: 500),
            entry("Tinycast", "https://b.example/", visits: 1)
        ]
        expect(
            titles(both, "tinycast"), ["Tinycast", "Docs for tinycast"],
            "prefix beats substring whatever the visits")
        let issues = [
            entry("Tinycast issues", "https://github.com/acme/tinycast/issues"),
            entry("Tinycast", "https://github.com/acme/tinycast")
        ]
        expect(titles(issues, "tinycast issues"), ["Tinycast issues"], "every word must match")
        expect(titles(issues, "TINYCAST"), titles(issues, "tinycast"), "case-insensitive")
        let tie = [
            entry("Notes", "https://a.example/n", visits: 2, daysAgo: 300),
            entry("Notes", "https://b.example/n", visits: 40, daysAgo: 2)
        ]
        expect(
            ChromeHistoryRanking.rank(tie, query: "notes", now: now).map(\.url.host),
            ["b.example", "a.example"],
            "visits and recency break ties")
        let forward = ChromeHistoryRanking.rank(tie, query: "notes", now: now)
        expect(
            forward, ChromeHistoryRanking.rank(tie.reversed(), query: "notes", now: now),
            "ranking is deterministic")
        let many = (0..<20).map { entry("Page \($0)", "https://x.example/\($0)") }
        expect(
            ChromeHistoryRanking.rank(many, query: "page", now: now).count, ChromeHistoryRanking.limit,
            "cut to five")
        expect(ChromeHistoryRanking.rank(many, query: "  ", now: now), [], "blank query ranks nothing")
        expect(titles([entry("", "https://github.com/x")], "github"), [""], "URL-only match")
    }

    static func hostIcons() {
        func asset(_ url: String) -> String? { ChromeSearchHostIcon.asset(for: URL(string: url)!) }
        expect(asset("https://github.com/acme"), "BrandGitHub", "github.com")
        expect(asset("https://gist.github.com/x"), "BrandGitHub", "subdomain")
        expect(asset("https://GitHub.com/"), "BrandGitHub", "host case")
        expect(asset("https://notgithub.com/"), nil, "lookalike suffix")
        expect(asset("https://github.com.example.org/"), nil, "lookalike prefix")
        expect(asset("https://example.com/"), nil, "other host")
    }

    static func rows() {
        let site = GoogleSuggestion(
            text: "github.com", kind: .website(URL(string: "https://github.com/acme/tinycast")!),
            detail: "GitHub")
        let page = entry("Tinycast", "https://github.com/acme/tinycast")
        let blank = entry("", "https://example.com/x")
        let seen = GoogleSearchHistory(entries: ["tiny cast"])
        expect(
            GoogleSearchRow.rows(
                suggestions: [GoogleSuggestion(text: "tiny car", kind: .query), site], pages: [page, blank],
                typed: "tiny", history: seen),
            [
                .typed("tiny"), .history("tiny cast"),
                .page(title: "Tinycast", url: page.url, detail: "github.com"),
                .page(title: "example.com", url: blank.url, detail: ""), .suggestion("tiny car")
            ],
            "order: typed, history, pages, suggestions; a duplicate website drops; blank title falls back to host"
        )
        expect(
            GoogleSearchRow.rows(suggestions: [], pages: [page], typed: "", history: GoogleSearchHistory()),
            [],
            "an empty field lists no pages")
    }

    static func makeProfile(_ root: URL, rows: [(String, String, Int, Int64, Int)]) -> URL {
        let profile = root.appending(path: "Profile 1", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try? Data(#"{"profile":{"last_used":"Profile 1"}}"#.utf8).write(
            to: root.appending(path: "Local State"))
        var db: OpaquePointer?
        sqlite3_open(profile.appending(path: "History").path, &db)
        sqlite3_exec(
            db,
            """
            CREATE TABLE urls(id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR,
                visit_count INTEGER, last_visit_time INTEGER, hidden INTEGER DEFAULT 0)
            """, nil, nil, nil)
        for (url, title, visits, time, hidden) in rows {
            let escaped = { (text: String) in text.replacingOccurrences(of: "'", with: "''") }
            let insert = """
                INSERT INTO urls(url,title,visit_count,last_visit_time,hidden)
                VALUES('\(escaped(url))','\(escaped(title))',\(visits),\(time),\(hidden))
                """
            sqlite3_exec(db, insert, nil, nil, nil)
        }
        sqlite3_close(db)
        return profile
    }

    static func reader() async {
        let base = FileManager.default.temporaryDirectory.appending(
            path: "chrome-history-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appending(path: "Chrome", directoryHint: .isDirectory)
        let copies = base.appending(path: "copy", directoryHint: .isDirectory)
        let profile = makeProfile(
            root,
            rows: [
                ("https://github.com/acme/tinycast", "Tinycast · GitHub", 9, 13_300_000_000_000_000, 0),
                ("https://example.com/100%_real", "Percent", 1, 13_300_000_000_000_000, 0),
                ("https://example.com/other", "Other", 1, 13_300_000_000_000_000, 0),
                ("https://hidden.example/tinycast", "Hidden tinycast", 1, 13_300_000_000_000_000, 1),
                ("chrome://settings/tinycast", "Not a page tinycast", 1, 13_300_000_000_000_000, 0)
            ])
        let reader = ChromeHistoryReader(userDataDirectory: root, copyDirectory: copies)
        let found = await reader.candidates(for: "tinycast")
        expect(
            found.map(\.title), ["Tinycast · GitHub"],
            "matches title or URL, skipping hidden rows and non-web URLs")
        expect(found.first?.visitCount, 9, "visit count read")
        expect(await reader.candidates(for: "100%_").map(\.title), ["Percent"], "LIKE wildcards are escaped")
        expect(await reader.candidates(for: "tinycast github").count, 1, "every word must match")
        expect(await reader.candidates(for: "  ").count, 0, "blank query reads nothing")
        expect(
            FileManager.default.fileExists(atPath: copies.appending(path: "History").path), true,
            "a private copy exists")
        let copyDate = try? copies.appending(path: "History").resourceValues(forKeys: [.creationDateKey])
            .creationDate
        _ = await reader.candidates(for: "other")
        expect(
            (try? copies.appending(path: "History").resourceValues(forKeys: [.creationDateKey]).creationDate)
                == copyDate,
            true, "an unchanged source is not copied again")
        reader.discardCopy()
        expect(FileManager.default.fileExists(atPath: copies.path), false, "discarding removes the copy")
        expect(await reader.candidates(for: "other").count, 1, "reading again recopies")
        try? FileManager.default.removeItem(at: profile.appending(path: "History"))
        reader.discardCopy()
        expect(await reader.candidates(for: "other").count, 0, "a missing History yields nothing")
        try? Data("garbage".utf8).write(to: profile.appending(path: "History"))
        expect(await reader.candidates(for: "other").count, 0, "an unreadable History yields nothing")
        let missing = ChromeHistoryReader(
            userDataDirectory: base.appending(path: "none"), copyDirectory: copies)
        expect(await missing.candidates(for: "x").count, 0, "no Chrome yields nothing")
    }
}
