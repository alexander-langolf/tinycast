// Search Google's pure layers: suggestion parsing, URL building, history, rows and the session's
// stale-suggestion rules, driven through a fake suggester.

import Foundation

actor Gate {
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var opened: Set<String> = []

    func wait(_ key: String) async {
        if opened.contains(key) { return }
        await withCheckedContinuation { waiters[key] = $0 }
    }

    func open(_ key: String) {
        opened.insert(key)
        waiters.removeValue(forKey: key)?.resume()
    }
}

final class FakeSuggester: GoogleSuggesting {
    let gate = Gate()
    let log = Log()
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
        var value: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }
    func suggestions(for query: String) async -> [GoogleSuggestion] {
        log.add("ask:" + query)
        await gate.wait(query)
        return [
            GoogleSuggestion(text: query + " one", kind: .query),
            GoogleSuggestion(text: query + " two", kind: .query)
        ]
    }
}

final class FakeHistory: ChromeHistoryReading {
    let gate = Gate()
    let discards = Counter()
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func add() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
    func candidates(for query: String) async -> [ChromeHistoryEntry] {
        await gate.wait("h:" + query)
        return [
            ChromeHistoryEntry(
                title: query + " page", url: URL(string: "https://example.com/\(query)")!, visitCount: 1,
                lastVisit: Date())
        ]
    }
    func discardCopy() { discards.add() }
}

@main
@MainActor
struct ChromeGoogleSearchTests {
    static var failures = 0
    static var passes = 0

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)\n  got  \(actual)\n  want \(expected)")
        }
    }

    static func queries(_ texts: String...) -> [GoogleSuggestion] {
        texts.map { GoogleSuggestion(text: $0, kind: .query) }
    }

    static func settle(_ milliseconds: Int = 60) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    static func main() async {
        suggestionParsing()
        history()
        urls()
        rows()
        await sessionRules()
        await historyStore()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func suggestionParsing() {
        func parse(_ json: String, _ typed: String = "tiny", charset: String? = nil) -> [GoogleSuggestion] {
            GoogleSuggestions.parse(Data(json.utf8), charset: charset, typed: typed)
        }
        func texts(_ list: [GoogleSuggestion]) -> [String] { list.map(\.text) }
        let mixed = #"""
            ["gith",["github","https://github.com/","github copilot","www.example.org","x"],
             ["","How people build software","","Example",""],[],
             {"google:suggesttype":["QUERY","NAVIGATION","QUERY","NAVIGATION","ENTITY"]}]
            """#
        let list = parse(mixed, "gith")
        expect(
            texts(list), ["github", "github.com", "github copilot", "example.org"],
            "types kept, unknown dropped")
        expect(list[0].kind, .query, "QUERY is a query")
        expect(list[1].kind, .website(URL(string: "https://github.com/")!), "NAVIGATION is a website")
        expect(list[1].detail, "How people build software", "website description")
        expect(
            list[3].kind, .website(URL(string: "https://www.example.org")!), "scheme-less website gets https")
        expect(
            texts(parse(#"["tiny",["tiny cast","tiny home"]]"#)), ["tiny cast", "tiny home"],
            "no types means queries")
        expect(
            texts(parse(#"["tiny",["Tiny","tiny cast"," ","Tiny Cast"]]"#)), ["tiny cast"],
            "blanks and duplicates drop")
        let many = (0..<20).map { "\"s\($0)\"" }.joined(separator: ",")
        expect(parse("[\"q\",[\(many)]]").count, 8, "capped at eight")
        expect(parse("not json"), [], "malformed input")
        expect(parse(#"["q"]"#), [], "missing list")
        expect(texts(parse(#"["q",[1,null,"ok"]]"#)), ["ok"], "non-strings skipped")
        expect(
            parse(#"["q",["javascript:alert(1)"],[],[],{"google:suggesttype":["NAVIGATION"]}]"#), [],
            "non-http website drops")
        // The live response is ISO-8859-1: "é" arrives as the single byte 0xE9.
        let latin = Data(#"["q",["caf"#.utf8) + Data([0xE9]) + Data(#" menu"]]"#.utf8)
        expect(
            texts(GoogleSuggestions.parse(latin, charset: "ISO-8859-1", typed: "q")), ["café menu"],
            "Latin-1 bytes decode")
        expect(
            texts(GoogleSuggestions.parse(latin, charset: nil, typed: "q")), ["café menu"],
            "Latin-1 is the fallback")
        expect(
            texts(GoogleSuggestions.parse(latin, charset: "no-such-charset", typed: "q")), ["café menu"],
            "unknown charset falls back")
        expect(texts(parse(#"["q",["café"]]"#, charset: "utf-8")), ["café"], "declared UTF-8 is honoured")
        let url = GoogleSuggestions.url(for: "a b&c++", language: "de")?.absoluteString ?? ""
        expect(url.hasPrefix("https://suggestqueries.google.com/complete/search?"), true, "suggestion host")
        expect(url.contains("client=chrome") && url.contains("hl=de"), true, "suggestion params")
        expect(url.hasSuffix("&q=a%20b%26c%2B%2B"), true, "query is escaped, plus included")
    }

    static func urls() {
        let url = GoogleSearchURL.resultsPage(for: "swift observation", language: "en")?.absoluteString
        expect(url, "https://www.google.com/search?q=swift%20observation&hl=en&num=10", "results page URL")
    }

    static func history() {
        var history = GoogleSearchHistory()
        history.record("swift observation")
        history.record(" Swift Concurrency ")
        history.record("SWIFT OBSERVATION")
        expect(
            history.entries, ["SWIFT OBSERVATION", "Swift Concurrency"],
            "recent first, deduplicated ignoring case")
        history.record("  ")
        expect(history.entries.count, 2, "blank is not recorded")
        expect(
            history.matches(for: "swift"), ["SWIFT OBSERVATION", "Swift Concurrency"],
            "matches contain the text")
        expect(history.matches(for: "obs"), ["SWIFT OBSERVATION"], "substring, any case")
        expect(history.matches(for: "swift observation"), [], "the typed text itself is not repeated")
        history.remove("swift concurrency")
        expect(history.entries, ["SWIFT OBSERVATION"], "remove ignores case")
        for index in 0..<60 { history.record("q\(index)") }
        expect(history.entries.count, GoogleSearchHistory.capacity, "capped at 50")
        expect(history.entries.first, "q59", "newest kept")
        expect(history.matches(for: "q").count, GoogleSearchHistory.matchLimit, "match list capped")
        expect(history.matches(for: "").count, GoogleSearchHistory.matchLimit, "empty query lists recents")
        history.clear()
        expect(history.entries, [], "clear")
        expect(
            GoogleSearchHistory(entries: ["a", "A", "b"]).entries, ["a", "b"],
            "init dedupes keeping the first")
    }

    static func rows() {
        let site = GoogleSuggestion(
            text: "github.com", kind: .website(URL(string: "https://github.com/")!), detail: "GitHub")
        let none = GoogleSearchHistory()
        let seen = GoogleSearchHistory(entries: ["tiny cast", "other", "tiny home"])
        expect(
            GoogleSearchRow.rows(suggestions: queries("Tiny", "tiny cast"), typed: "tiny", history: none),
            [.typed("tiny"), .suggestion("tiny cast")], "typed row first, no duplicate of it")
        expect(
            GoogleSearchRow.rows(
                suggestions: queries("tiny cast", "tiny car") + [site], typed: "tiny", history: seen),
            [
                .typed("tiny"), .history("tiny cast"), .history("tiny home"), .suggestion("tiny car"),
                .website(title: "github.com", url: URL(string: "https://github.com/")!, detail: "GitHub")
            ],
            "history after typed, suggestions that repeat it dropped, websites kept")
        expect(
            GoogleSearchRow.rows(suggestions: [], typed: "", history: seen),
            [.history("tiny cast"), .history("other"), .history("tiny home")],
            "empty query lists recent history")
        expect(
            GoogleSearchRow.rows(suggestions: queries("x"), typed: "", history: none).isEmpty, true,
            "empty query, no history")
    }

    static func historyStore() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "gsh-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.json")
        let store = GoogleSearchHistoryStore(fileURL: file)
        expect(store.history.entries, [], "a missing file is an empty history")
        store.record("one")
        store.record("two")
        expect(GoogleSearchHistoryStore(fileURL: file).history.entries, ["two", "one"], "recording persists")
        store.remove("two")
        expect(GoogleSearchHistoryStore(fileURL: file).history.entries, ["one"], "removal persists")
        store.clear()
        expect(GoogleSearchHistoryStore(fileURL: file).history.entries, [], "clear persists")
        try? Data("garbage".utf8).write(to: file)
        expect(
            GoogleSearchHistoryStore(fileURL: file).history.entries, [], "a corrupt file is an empty history")
    }

    static func sessionRules() async {
        // A late suggestion response is discarded.
        do {
            let suggester = FakeSuggester()
            let session = ChromeSearchSession(suggester: suggester, chromeHistory: FakeHistory())
            session.queryChanged("tin")
            await settle()
            session.queryChanged("tiny")
            await settle()
            await suggester.gate.open("tiny")
            await settle()
            await suggester.gate.open("tin")
            await settle()
            expect(session.query, "tiny", "the newest query is kept")
            expect(session.suggestions, Self.queries("tiny one", "tiny two"), "late suggestions discarded")
        }
        // Previous suggestions stay while the next set loads, and a blank query clears them.
        do {
            let suggester = FakeSuggester()
            let session = ChromeSearchSession(suggester: suggester, chromeHistory: FakeHistory())
            session.queryChanged("a")
            await suggester.gate.open("a")
            await settle()
            session.queryChanged("ab")
            expect(session.suggestions, Self.queries("a one", "a two"), "suggestions kept while typing")
            session.queryChanged("  ")
            expect(session.suggestions, [], "blank query clears")
            expect(session.query, "", "blank query is empty")
        }
        // History pages follow the same stale rules and clear on reset, which also drops the copy.
        do {
            let history = FakeHistory()
            let session = ChromeSearchSession(suggester: FakeSuggester(), chromeHistory: history)
            session.queryChanged("tin")
            await settle()
            session.queryChanged("tiny")
            await settle()
            await history.gate.open("h:tiny")
            await settle()
            await history.gate.open("h:tin")
            await settle()
            expect(session.pages.map(\.title), ["tiny page"], "late history pages discarded")
            session.queryChanged("tinyc")
            expect(session.pages.map(\.title), ["tiny page"], "pages kept while typing")
            session.queryChanged("  ")
            expect(session.pages, [], "blank query clears pages")
            session.queryChanged("late")
            await settle()
            session.reset()
            await history.gate.open("h:late")
            await settle()
            expect(session.pages, [], "reset cancels and discards in-flight pages")
            expect(history.discards.value, 1, "reset drops the history copy")
        }
        // No debounce: every keystroke asks at once, and a blank edit asks nothing.
        do {
            let suggester = FakeSuggester()
            let session = ChromeSearchSession(suggester: suggester, chromeHistory: FakeHistory())
            for text in ["  ", "a", "ab"] {
                session.queryChanged(text)
                await settle(5)
            }
            expect(suggester.log.value, ["ask:a", "ask:ab"], "each keystroke asks at once, blanks never")
            session.reset()
            expect(session.query, "", "reset clears the query")
            expect(session.suggestions, [], "reset clears the suggestions")
        }
    }
}
