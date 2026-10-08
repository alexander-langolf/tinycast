// Pins the fork's fzf matcher: scoring shape, syntax, profiles and the hook adapters.
import Foundation

@main
struct ForkSearchTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ description: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)  \(detail())"); failures += 1
        }
    }

    static func main() {
        scorer()
        syntax()
        tiered()
        launcher()
        contains()
        clipboardFTS()
        clipboardRank()
        clipboardFuzzy()
        clipboardScan()
        files()
        fileRegressions()
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func hit(_ term: String, _ text: String, exact: Bool = false) -> ForkFzf.Hit? {
        ForkFzf.match(Array(FuzzyMatch.normalized(term)), in: text, exact: exact)
    }

    static func scorer() {
        check(
            "initials land on word starts", hit("vsc", "Visual Studio Code")?.positions == [0, 7, 14],
            "\(String(describing: hit("vsc", "Visual Studio Code")))")
        check(
            "exact term found contiguously",
            hit("fork", "ForkTypography.swift", exact: true)?.positions == [0, 1, 2, 3])
        check("exact rejects scattered letters", hit("slk", "Slack", exact: true) == nil)
        check("fuzzy accepts scattered letters", hit("slk", "Slack") != nil)
        check("no match is nil", hit("xyz", "Slack") == nil)
        check("diacritics fold", hit("resume", "Résumé photo.jpg") != nil)
        for exact in [false, true] {
            check(
                "expanded fold keeps source positions (exact: \(exact))",
                hit("straße", "Straße", exact: exact)?.positions == Array(0...5))
            check(
                "expanded ligature keeps source positions (exact: \(exact))",
                hit("file", "ﬁle", exact: exact)?.positions == [0, 1, 2])
            check(
                "expanded sharp s deduplicates positions (exact: \(exact))",
                hit("ss", "ß", exact: exact)?.positions == [0])
        }
        check(
            "hump after an expanded fold uses its source index",
            (ForkFzf.match(Array("sx"), in: "ßx", exact: false, humps: [1])?.score ?? 0)
                > (hit("sx", "ßx")?.score ?? 0))
        check(
            "camelCase hump scores as a boundary",
            (hit("ft", "ForkTypography")?.score ?? 0) > (hit("ft", "Forkfootnote")?.score ?? 0))
        check(
            "consecutive beats scattered",
            (hit("abc", "abc def")?.score ?? 0) > (hit("abc", "a b c")?.score ?? 0))
        check(
            "word start beats mid-word",
            (hit("set", "System Settings")?.score ?? 0) > (hit("set", "Closet")?.score ?? 0))
        check(
            "exact picks the best-bonus occurrence",
            hit("inv", "Hi — attaching the invoice for March", exact: true)?.positions.first == 19)
    }

    static func syntax() {
        let invoice = "Hi Rawling — attaching the invoice for March, net 30 as agreed."
        check(
            "words in any order",
            ForkSearch.match("march invoice", fields: [invoice], profile: .accurate) != nil)
        check(
            "accurate rejects scattered letters",
            ForkSearch.match("inv mrch", fields: [invoice], profile: .accurate) == nil)
        check(
            "accurate rejects a typo",
            ForkSearch.match("pasword", fields: ["Password reset link"], profile: .accurate) == nil)
        check(
            "fuzzy allows skipped letters",
            ForkSearch.match("ariel pkg", fields: ["package.json", "~/work/ariel/"], profile: .fuzzy) != nil)
        check(
            "!word excludes",
            ForkSearch.match("stardust !bump", fields: ["Stardust 5.20.0 bump complete"], profile: .fuzzy)
                == nil)
        check(
            "!word keeps others",
            ForkSearch.match("stardust !bump", fields: ["{\"name\":\"stardust\"}"], profile: .fuzzy) != nil)
        check(
            "^prefix anchors",
            ForkSearch.match("^git", fields: ["git push origin main"], profile: .fuzzy) != nil
                && ForkSearch.match("^push", fields: ["git push origin main"], profile: .fuzzy) == nil)
        check(
            "suffix$ anchors",
            ForkSearch.match("json$", fields: ["package.json"], profile: .fuzzy) != nil
                && ForkSearch.match("json$", fields: ["package.json.bak"], profile: .fuzzy) == nil)
        check(
            "'exact in the fuzzy profile",
            ForkSearch.match("'pkg", fields: ["package.json"], profile: .fuzzy) == nil)
        check(
            "best field wins and positions follow it",
            ForkSearch.match("ariel", fields: ["package.json", "~/work/ariel/"], profile: .fuzzy)?.positions[
                1
            ].isEmpty == false)
        check(
            "short query rule",
            ForkSearch.isShort("st") && ForkSearch.isShort(" a ") && !ForkSearch.isShort("sta"))
        check("disabled by default", !ForkSearch.isEnabled)
    }

    static func tiered() {
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        let exact = FuzzyMatch.match(query: "notes", candidate: "Notes")
        check("exact tier kept", exact?.tier == .exact)
        check(
            "prefix tier kept", FuzzyMatch.match(query: "sys", candidate: "System Settings")?.tier == .prefix)
        check(
            "any-order words now match",
            FuzzyMatch.match(query: "settings system", candidate: "System Settings") != nil)
        check(
            "initials match as subsequence",
            FuzzyMatch.match(query: "sysset", candidate: "System Settings")?.tier == .subsequence)
        check("no typo tolerance", FuzzyMatch.match(query: "sytsem", candidate: "System Settings") == nil)
        let tight = FuzzyMatch.match(query: "gh", candidate: "github")
        let scattered = FuzzyMatch.match(query: "gh", candidate: "gxxxxh")
        check("subsequence tier kept", tight?.tier == .subsequence)
        check(
            "subsequence spread stays below the reference",
            tight.map { $0.spread < FuzzyMatch.referenceSpread(2) } == true)
        check(
            "tighter subsequence has larger spread",
            tight != nil && scattered != nil && tight!.spread > scattered!.spread)
    }

    static func launcher() {
        func accepted(_ q: String, _ t: String, _ level: String = "medium") -> Bool {
            guard let s = ForkSearch.launcherScore(q, in: t) else { return false }
            // LauncherOrder passes the whole typed length, spaces and syntax included
            return s == .max || ForkSearch.accepts(score: s, letters: q.utf16.count, level: level)
        }
        check("vsc → Visual Studio Code", accepted("vsc", "Visual Studio Code"))
        check("slk → Slack", accepted("slk", "Slack"))
        check("saf → Safari", accepted("saf", "Safari"))
        check("negated word does not raise the bar", accepted("ariel !pkg", "ariel docs"))
        check("negated word still rejects", !accepted("ariel !docs", "ariel docs"))
        check("two words with a space", accepted("vs code", "Visual Studio Code"))
        check("exact is max", ForkSearch.launcherScore("slack", in: "slack") == .max)
        check("scattered junk rejected at medium", !accepted("lnd", "alexander-langolf"))
        check("low accepts anything matched", accepted("lnd", "alexander-langolf", "low"))
        check(
            "camel hump honoured",
            (ForkSearch.launcherScore("gh", in: "github", humps: [3]) ?? 0)
                > (ForkSearch.launcherScore("gh", in: "github") ?? 0))
        check("medium includes threshold", ForkSearch.accepts(score: 56, letters: 3, level: "medium"))
        check("medium rejects below threshold", !ForkSearch.accepts(score: 55, letters: 3, level: "medium"))
        check("high includes threshold", ForkSearch.accepts(score: 72, letters: 3, level: "high"))
        check("high rejects below threshold", !ForkSearch.accepts(score: 71, letters: 3, level: "high"))
    }

    static func contains() {
        ForkSearch.setEnabled(false)
        check(
            "disabled filter keeps case-insensitive substring",
            ForkSearch.contains("MAIL", in: "Email signature"))
        check("disabled filter rejects scattered letters", !ForkSearch.contains("eml", in: "Email signature"))
        check("missing snippet keyword does not match", !ForkSearch.contains("mail", in: nil))
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        check("snippet name accepts scattered letters", ForkSearch.contains("eml", in: "Email signature"))
        check("snippet keyword accepts scattered letters", ForkSearch.contains("sig", in: ";signature"))
        check(
            "quicklink name accepts any-order words",
            ForkSearch.contains("issues github", in: "GitHub Issues"))
        check("filter honours exclusions", !ForkSearch.contains("github !issues", in: "GitHub Issues"))
        check("filter rejects a typo", !ForkSearch.contains("gihtub", in: "GitHub Issues"))
        check("enabled missing keyword does not match", !ForkSearch.contains("mail", in: nil))
        let foldedPairs = [("straße", "Straße"), ("strasse", "Straße"), ("file", "ﬁle"), ("ss", "ß")]
        for profile in [ForkSearch.Profile.fuzzy, .accurate] {
            for (query, text) in foldedPairs {
                check(
                    "expanded fold: \(query) in \(text) (\(profile))",
                    ForkSearch.contains(query, in: text, profile: profile))
            }
            for token in ["!", "'", "^", "$"] {
                check(
                    "lone syntax is literal: \(token) (\(profile))",
                    ForkSearch.contains(token, in: "hey" + token, profile: profile))
                check(
                    "lone syntax is an exact positive term: \(token) (\(profile))",
                    ForkSearch.terms(token, profile: profile)
                        == [
                            ForkSearch.Term(
                                text: Array(token), exact: true, prefix: false, suffix: false,
                                negated: false)
                        ])
            }
        }
        check("only exclusions match nothing", !ForkSearch.contains("!foo !bar", in: "hey!"))
        check(
            "pinned OCR accepts any-order fuzzy words",
            ForkSearch.clipboardScore("march invoice", "invoice for March") != nil)
        check(
            "short OCR query matches",
            ForkSearch.clipboardScore("gh", "gh pr create --fill") != nil)
        check("missing OCR text rejects", ForkSearch.clipboardScore("gh", nil) == nil)
        ForkSearch.setEnabled(false)
        check(
            "off: OCR keeps upstream substring matching",
            ForkSearch.clipboardScore("INVOICE", "invoice for March") != nil
                && ForkSearch.clipboardScore("march invoice", "invoice for March") == nil)
    }

    static func clipboardFTS() {
        ForkSearch.setEnabled(false)
        check("off: upstream phrase", ForkSearch.clipboardFTS("march invoice") == "\"march invoice\"")
        check("off: short query falls back", ForkSearch.clipboardFTS("gh") == nil)
        check("off: quotes escaped", ForkSearch.clipboardFTS("say\"hi") == "\"say\"\"hi\"")
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        check("words ANDed", ForkSearch.clipboardFTS("march invoice") == "\"march\" AND \"invoice\"")
        // Short words cannot use the trigram index.
        check("short words left to the filter", ForkSearch.clipboardFTS("gh pr create") == "\"create\"")
        check("all short words fall back", ForkSearch.clipboardFTS("gh pr") == nil)
        check("raw short query falls back", ForkSearch.clipboardFTS("gh") == nil)
        check("syntax stripped from long words", ForkSearch.clipboardFTS("^gh create") == "\"create\"")
        check("short word with exclusion", ForkSearch.clipboardFTS("ab !cd efg") == "\"efg\"")
        check(
            "any order with short words",
            ForkSearch.clipboardScore("create pr gh", "gh pr create") != nil)
        check("!word becomes NOT", ForkSearch.clipboardFTS("stardust !bump") == "\"stardust\" NOT \"bump\"")
        check("plain exclusion becomes NOT", ForkSearch.clipboardFTS("foo !bar") == "\"foo\" NOT \"bar\"")
        for excluded in ["!bar$", "!^bar", "!!foo", "!'bar", "!gh"] {
            check(
                "exclusion stays in memory: \(excluded)",
                ForkSearch.clipboardFTS("foo " + excluded) == "\"foo\"")
        }
        check("only exclusions have no FTS positives", ForkSearch.clipboardFTS("!foo !bar") == nil)
        check("exclusion keeps subsequence tier", ForkSearch.tiered("gb !x", "github") != nil)
        check("suffix keeps subsequence tier", ForkSearch.tiered("g b$", "gxb") != nil)
        check("phrase run keeps word start", ForkSearch.tiered("bar baz", "foo bar baz")?.tier == .wordStart)
        check(
            "phrase run keeps word start (2)",
            ForkSearch.tiered("open recent", "file open recent")?.tier == .wordStart)
        check("phrase run keeps substring", ForkSearch.tiered("ar baz", "a bar baz")?.tier == .substring)
        check(
            "reversed words stay subsequence",
            ForkSearch.tiered("baz bar", "foo bar baz")?.tier == .subsequence)
        check("contiguous run wins the tier", ForkSearch.tiered("ar", "a bar")?.tier == .substring)
        check("contiguous run wins the tier (2)", ForkSearch.tiered("sa", "ssa")?.tier == .substring)
        check("suffix after expansion", !ForkSearch.contains("ss$", in: "ßa"))
        check("prefix after expansion", !ForkSearch.contains("^ss", in: "xß"))
        check("prefix through expansion", ForkSearch.contains("^ss", in: "ßa"))
        check("quotes escaped", ForkSearch.clipboardFTS("say\"hi") == "\"say\"\"hi\"")
        check(
            "fuzzy item filter with exact-word override",
            ForkSearch.clipboardScore("inv mrch", "invoice for March") != nil
                && ForkSearch.clipboardScore("inv 'mrch", "invoice for March") == nil)
    }

    static func clipboardRank() {
        let newestFirst = ["March 2026 invoice total", "attaching the invoice for March", "unrelated"]
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        let ranked = ForkSearch.rankClipboard(newestFirst, query: "invoice march") { $0 }
        check("non-matches dropped", ranked.count == 2)
        check("best match first", ranked.first == "March 2026 invoice total")
        check(
            "short query keeps newest-first",
            ForkSearch.rankClipboard(newestFirst, query: "in") { $0 }
                == newestFirst.filter { $0.contains("in") })
        let differentScores = ["preinvoice premarch", "invoice march"]
        check(
            "higher score beats recency",
            ForkSearch.rankClipboard(differentScores, query: "invoice march") { $0 }
                == Array(differentScores.reversed()))
        check(
            "short query keeps order despite different scores",
            ForkSearch.rankClipboard(differentScores, query: "in") { $0 } == differentScores)
        let equalScores = ["invoice march newer", "invoice march older"]
        check(
            "equal scores keep incoming newest-first",
            ForkSearch.rankClipboard(equalScores, query: "invoice march") { $0 } == equalScores)
        ForkSearch.setEnabled(false)
        check(
            "off: input unchanged",
            ForkSearch.rankClipboard(newestFirst, query: "invoice march") { $0 } == newestFirst)
    }

    static func clipboardFuzzy() {
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        let link = "https://multiverseio.slack.com/archives/C123/p123456"
        check("clipboard ml skips letters in a URL", ForkSearch.clipboardScore("ml", link) != nil)
        check("clipboard quote keeps exact text", ForkSearch.clipboardScore("'ml", link) == nil)
        let junk = "m" + String(repeating: "x", count: 80) + "l"
        check("scattered junk has a fuzzy alignment", hit("ml", junk) != nil)
        check("clipboard rejects scattered junk", ForkSearch.clipboardScore("ml", junk) == nil)
        check(
            "every positive word must clear medium",
            ForkSearch.clipboardScore("invoice ml", "invoice " + junk) == nil)
        check(
            "rank uses the same threshold",
            ForkSearch.rankClipboard([junk, link], query: "ml") { $0 } == [link])
        let old = (id: 1, date: Date(timeIntervalSince1970: 1), text: "multiverse link")
        let new = (id: 2, date: Date(timeIntervalSince1970: 2), text: link)
        let merged = ForkSearch.clipboardUnion(
            [old, new], resident: [new], id: { $0.id }, createdAt: { $0.date })
        check("clipboard union deduplicates IDs", merged.map(\.id) == [2, 1])
        check(
            "short union query stays newest first",
            ForkSearch.rankClipboard(merged, query: "ml") { $0.text }.map(\.id) == [2, 1])
        ForkSearch.setEnabled(false)
        check("off clipboard remains substring", ForkSearch.clipboardScore("ml", link) == nil)
        check(
            "off union retains hits exactly",
            ForkSearch.clipboardUnion([old, new], resident: [new], id: { $0.id }, createdAt: { $0.date }).map(
                \.id) == [1, 2])
    }

    static func clipboardScan() {
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        let boundary = String(repeating: "x", count: 4092) + " abc"
        let beyond = String(repeating: "x", count: 4096) + " abc"
        let beyondFuzzy = String(repeating: "x", count: 4096) + " alpha beta charlie"
        check("clipboard includes the 4096th character", ForkSearch.clipboardScore("abc", boundary) != nil)
        check("clipboard ignores fuzzy text beyond cap", ForkSearch.clipboardScore("abc", beyondFuzzy) == nil)
        check(
            "clipboard ignores literal text beyond cap in memory",
            ForkSearch.clipboardScore("abc", beyond) == nil)
        let graphemes = String(repeating: "👩‍💻", count: 4092) + " abc"
        check("clipboard cap counts characters", ForkSearch.clipboardScore("abc", graphemes) != nil)
        let rows = [(id: 1, text: beyond), (id: 2, text: boundary), (id: 3, text: beyondFuzzy)]
        var scored = [Int: Int]()
        let result = ForkSearch.clipboardResults(
            [rows[0]], resident: rows, query: "abc", id: { $0.id },
            text: {
                scored[$0.id, default: 0] += 1
                return $0.text
            }, createdAt: { Date(timeIntervalSince1970: Double($0.id)) },
            pinnedAt: { $0.id == 2 ? Date(timeIntervalSince1970: 1) : nil })
        check("union scores each item once including pins and duplicates", scored == [1: 1, 2: 1, 3: 1])
        check("full-text FTS survives cap and pins stay first", result.map(\.id) == [2, 1])
        check("long literal word still uses full-text FTS", ForkSearch.clipboardFTS("abc") == "\"abc\"")
        ForkSearch.setEnabled(false)
        check("off clipboard has no scan cap", ForkSearch.clipboardScore("abc", beyond) != nil)
    }

    static func fileRegressions() {
        let home = URL(fileURLWithPath: "/Users/test")
        let ignore = FileSearchIgnoreList(patterns: [])
        func result(_ path: String) -> FileSearchResult {
            FileSearchResult(url: URL(fileURLWithPath: path), isDirectory: false, homeDirectory: home)
        }
        var candidates = (0..<999).map { result("/Users/test/Docs/zz_\($0)_go_long_name.txt") }
        candidates.insert(result("/Users/test/go"), at: 800)
        ForkSearch.setEnabled(false)
        let upstream = FileSearchQuery.rank(candidates, for: "go", ignoring: ignore)
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        let ranked = FileSearchQuery.rank(candidates, for: "go", ignoring: ignore)
        check("short file query keeps exact hit beyond display cap", ranked.first?.name == "go")
        check("short file query uses upstream rank", ranked.map(\.id) == upstream.map(\.id))
        check("short file query retains display cap", ranked.count == FileSearchQuery.resultLimit)
        let single = candidates.map { result($0.id.replacingOccurrences(of: "go", with: "g")) }
        check(
            "single-character file query keeps exact hit beyond display cap",
            FileSearchQuery.rank(single, for: "g", ignoring: ignore).first?.name == "g")
        let junk = "m" + String(repeating: "x", count: 80) + "d"
        check(
            "file root filter rejects below-medium alignment",
            !FileSearchQuery.matches(filename: junk, query: "md"))
        check(
            "file root filter applies threshold per word",
            !FileSearchQuery.matches(filename: "report " + junk, query: "report md"))
        check(
            "file root filter accepts literal short word",
            FileSearchQuery.matches(filename: "readme.md", query: "md"))
        check(
            "file root filter shares clipboard medium bar",
            FileSearchQuery.matches(filename: "ChroMe-Debug", query: "md")
                == (ForkSearch.clipboardScore("md", "ChroMe-Debug") != nil))
        let paths = [result("/Users/test/work/report.txt"), result("/Users/test/Docs/report-work.txt")]
        check(
            "file exclusions ignore folder names",
            FileSearchQuery.rank(paths, for: "report !work", ignoring: ignore).map(\.id) == [paths[0].id])
        check(
            "file root exclusion uses filename",
            FileSearchQuery.matches(filename: "report.txt", query: "report !work"))
        check(
            "fast batch excludes filename without searching negated literal",
            FileSearchQuery.expression(for: "report !work")
                == #"kMDItemFSName == "*report*"cd && kMDItemFSName != "*work*"cd"#)
        ForkSearch.setEnabled(false)
        check(
            "off fast batch keeps literal upstream terms",
            FileSearchQuery.expression(for: "report !work")
                == #"kMDItemFSName == "*report*"cd && kMDItemFSName == "*!work*"cd"#)
        check(
            "off file root filter has no fuzzy matching",
            !FileSearchQuery.matches(filename: "ChroMe-Debug", query: "md"))
    }

    static func files() {
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        check(
            "glob interleaves letters",
            ForkSearch.spotlightNameClause("fork") == #"kMDItemFSName == "*f*o*r*k*"cd"#)
        check(
            "quote stays substring",
            ForkSearch.spotlightNameClause("'fork") == #"kMDItemFSName == "*fork*"cd"#)
        check(
            "prefix is exact and anchored",
            ForkSearch.spotlightNameClause("^fork") == #"kMDItemFSName == "fork*"cd"#)
        check(
            "suffix is exact and anchored",
            ForkSearch.spotlightNameClause("swift$") == #"kMDItemFSName == "*swift"cd"#)
        check(
            "both anchors reject longer filenames",
            ForkSearch.match("^fork$", fields: ["fork.txt"], profile: .fuzzy) == nil)
        check(
            "both anchors reject repeated words",
            ForkSearch.match("^fork$", fields: ["forkfork"], profile: .fuzzy) == nil)
        check(
            "both anchors are exact",
            ForkSearch.spotlightNameClause("^fork$") == #"kMDItemFSName == "fork"cd"#)
        check(
            "glob metacharacters escaped",
            ForkSearch.spotlightNameClause("a*b") == #"kMDItemFSName == "*a*\**b*"cd"#)
        check(
            "negated word is NOT clause",
            ForkSearch.spotlightNameClause("!bak") == #"kMDItemFSName != "*bak*"cd"#)
        check(
            "negated anchor is preserved",
            ForkSearch.spotlightNameClause("!^bak") == #"kMDItemFSName != "bak*"cd"#)
        check(
            "lone syntax stays literal", ForkSearch.spotlightNameClause("'") == #"kMDItemFSName == "*'*"cd"#)
        check("three letters start supplemental query", ForkSearch.fileNeedsGlob("pkg"))
        check("two letters keep only fast query", !ForkSearch.fileNeedsGlob("ml"))
        check("syntax is not a scoring letter", !ForkSearch.fileNeedsGlob("^ml"))
        check("exclusion alone starts no supplemental query", !ForkSearch.fileNeedsGlob("!fork"))
        check(
            "path union deduplicates stably",
            ForkSearch.mergePaths(["a", "b"], ["b", "c"], id: { $0 }) == ["a", "b", "c"])
        check(
            "fast expression stays upstream substring",
            FileSearchQuery.expression(for: "fork") == #"kMDItemFSName == "*fork*"cd"#)
        check(
            "supplemental expression uses glob",
            FileSearchQuery.expression(for: "fork", forkFuzzy: true) == #"kMDItemFSName == "*f*o*r*k*"cd"#)
        check(
            "root filenames also skip letters",
            FileSearchQuery.matches(filename: "ForkTypography.swift", query: "fkty"))
        check(
            "glob retains ignored-name clauses",
            FileSearchQuery.expression(for: "fork", excluding: ["*.tmp"], forkFuzzy: true)
                == #"kMDItemFSName == "*f*o*r*k*"cd && kMDItemFSName != "*.tmp"cd"#)
        let pairs = [
            (name: "package-lock.json", folder: "~/work/ariel/js/"),
            (name: "package.json", folder: "~/work/ariel/")
        ]
        check("folder words count", ForkSearch.rankPaths(pairs, query: "ariel pkg").count == 2)
        check("tighter name first", ForkSearch.rankPaths(pairs, query: "ariel pkg").first == 1)
        check(
            "filename outranks folder",
            ForkSearch.rankPaths([("other.txt", "~/fork/"), ("fork.txt", "~/other/")], query: "fork") == [
                1, 0
            ])
        check(
            "shorter name breaks score ties",
            ForkSearch.rankPaths([("fork-long.txt", "~"), ("fork.txt", "~")], query: "fork") == [1, 0])
        check(
            "index breaks remaining ties",
            ForkSearch.rankPaths([("fork.txt", "~/a"), ("fork.txt", "~/b")], query: "fork") == [0, 1])
        check(
            "path scorer ranks short names when called directly",
            ForkSearch.rankPaths([("prefork.txt", "~"), ("fork.txt", "~")], query: "fo") == [1, 0])
        check(
            "path nonmatches dropped", ForkSearch.rankPaths([("other.txt", "~/else/")], query: "fork").isEmpty
        )
        ForkSearch.setEnabled(false)
        check(
            "off supplemental flag retains upstream expression",
            FileSearchQuery.expression(for: "fork", forkFuzzy: true) == #"kMDItemFSName == "*fork*"cd"#)
        check(
            "off root matching remains substring",
            !FileSearchQuery.matches(filename: "ForkTypography.swift", query: "fkty"))
    }
}
