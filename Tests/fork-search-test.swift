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
        prepared()
        parity()
        emojiFold()
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
                                text: Array(token), units: Array(token).map { ForkSearch.unitCode($0) },
                                exact: true, prefix: false, suffix: false, negated: false)
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
        check("literal word beyond the cap still matches", ForkSearch.clipboardScore("abc", beyond) != nil)
        let long = "invoice header " + String(repeating: "x", count: 5400) + " march footer gh"
        check("exclusion beyond the cap rejects", ForkSearch.clipboardScore("invoice !march", long) == nil)
        check("short word beyond the cap matches", ForkSearch.clipboardScore("gh", long) != nil)
        check("suffix beyond the cap matches", ForkSearch.clipboardScore("gh$", long) != nil)
        check("CRLF text does not crash the tiered matcher", ForkSearch.tiered("b", "a\r\nb")?.offset == 2)
        let graphemes = String(repeating: "👩‍💻", count: 4092) + " abc"
        check("clipboard cap counts characters", ForkSearch.clipboardScore("abc", graphemes) != nil)
        let rows = [(id: 1, text: beyond), (id: 2, text: boundary), (id: 3, text: beyondFuzzy)]
        var scored = [Int: Int]()
        let result = ForkSearch.clipboardResults(
            [rows[0]], resident: rows, query: "abc", id: { $0.id },
            prepared: {
                scored[$0.id, default: 0] += 1
                return ForkSearch.ClipboardText($0.text)
            }, createdAt: { Date(timeIntervalSince1970: Double($0.id)) },
            pinnedAt: { $0.id == 2 ? Date(timeIntervalSince1970: 1) : nil })
        check("union scores each item once including pins and duplicates", scored == [1: 1, 2: 1, 3: 1])
        check("full-text FTS survives cap and pins stay first", result.map(\.id) == [2, 1])
        check("long literal word still uses full-text FTS", ForkSearch.clipboardFTS("abc") == "\"abc\"")
        ForkSearch.setEnabled(false)
        check("off clipboard has no scan cap", ForkSearch.clipboardScore("abc", beyond) != nil)
    }

    /// One fold serves every match: skin tones and variation selectors are ignored everywhere.
    static func emojiFold() {
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        check(
            "skin-tone emoji matches its base query",
            ForkSearch.clipboardScore(
                ForkSearch.Query("great 👍", profile: .fuzzy), ForkSearch.ClipboardText("great 👍🏽 work")) != nil)
        check("variation selector is ignored", ForkSearch.clipboardScore("❤", "I ❤️ it") != nil)
        let long = String(repeating: "x", count: 4096) + " ｶﾀｶﾅ"
        check("half-width text past the cap matches", ForkSearch.clipboardScore("カタカナ", long) != nil)
        let item = (id: 1, text: "great 👍🏽 work")
        for (label, hits, resident) in [("FTS hit", [item], []), ("resident", [], [item])] {
            let result = ForkSearch.clipboardResults(
                hits, resident: resident, query: "great 👍", id: { $0.id },
                prepared: { ForkSearch.ClipboardText($0.text) },
                createdAt: { _ in Date(timeIntervalSince1970: 1) }, pinnedAt: { _ in nil })
            check("clipboardResults returns skin-tone item as \(label)", result.map(\.id) == [1])
        }
    }

    /// Equatable snapshots: `ForkSearch` and `ReferenceSearch` return distinct Result types.
    struct ResultKey: Equatable { let score: Int; let positions: [[Int]] }
    struct TierKey: Equatable {
        let tier: FuzzyMatch.Tier, offset: Int, queryLength: Int, candidateLength: Int, spread: Int
    }

    static func resultKey(_ r: ForkSearch.Result?) -> ResultKey? {
        r.map { ResultKey(score: $0.score, positions: $0.positions) }
    }

    static func referenceKey(_ r: ReferenceSearch.Result?) -> ResultKey? {
        r.map { ResultKey(score: $0.score, positions: $0.positions) }
    }

    static func tierKey(_ m: FuzzyMatch.Match?) -> TierKey? {
        m.map {
            TierKey(
                tier: $0.tier, offset: $0.offset, queryLength: $0.queryLength,
                candidateLength: $0.candidateLength, spread: $0.spread)
        }
    }

    /// Fork and reference agree on every corpus item and query, positions included.
    static func prepared() {
        let plain = ForkSearch.Text("Hello World")
        check("ASCII text has no sources", plain.sources == nil)
        check(
            "ASCII units are lowercased bytes",
            plain.units == Array("hello world".utf8).map(UInt32.init))
        let straße = ForkSearch.Text("Straße")
        check("expanded fold has 6 source characters", straße.length == 6)
        check("expanded fold has 7 units", straße.units.count == 7)
        check("CRLF counts as one source character", ForkSearch.Text("a\r\nb").length == 3)
        let flag = "🇩🇪"
        let flagText = ForkSearch.Text("x\(flag)y")
        let flagTerm = ForkSearch.terms(flag, profile: .fuzzy)[0]
        check(
            "flag encodes to one unit equal to the query's unit",
            flagTerm.units.count == 1 && flagText.units[1] == flagTerm.units[0])
        check(
            "ASCII byte classes match Character classes under both schemes",
            (0..<128).allSatisfy { byte in
                let c = Character(UnicodeScalar(UInt8(byte)))
                return [ForkFzf.Scheme.standard, .path].allSatisfy {
                    ForkFzf.asciiClass(UInt8(byte), scheme: $0) == ForkFzf.charClass(c, scheme: $0)
                }
            })
        var shapeFailures: [String] = []
        for item in ForkSearchCorpus.items(count: 2_000, seed: 0x7E57_C0DE) {
            let text = ForkSearch.Text(String(item.prefix(2_000)))
            if text.units.count != text.bonuses.count
                || (text.sources.map { $0.count != text.units.count } ?? false)
            {
                shapeFailures.append(String(item.prefix(40)).debugDescription)
            }
        }
        check(
            "prepared text has aligned arrays for every corpus item", shapeFailures.isEmpty,
            shapeFailures.prefix(3).joined(separator: " | "))
    }

    /// The fork fold drops these scalars and `ReferenceSearch` keeps them, so parity strips both sides.
    static func stripEmojiModifiers(_ s: String) -> String {
        String(
            String.UnicodeScalarView(
                s.unicodeScalars.filter {
                    !(0x1F3FB...0x1F3FF).contains($0.value) && $0.value != 0xFE0E && $0.value != 0xFE0F
                }))
    }

    static func parity() {
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        let items = ForkSearchCorpus.items(count: 1_000, seed: 0x7E57_C0DE)
        let head = 2_000
        var mismatches: [String] = []
        var comparisons = 0
        var matched = 0
        var unmatched = 0
        var skipped: [Int] = []
        func compare<T: Equatable>(_ label: String, _ fork: T, _ reference: T, _ item: Int, _ query: String) {
            comparisons += 1
            if fork != reference {
                mismatches.append("item \(item) query \(query.debugDescription) \(label): fork \(fork) vs reference \(reference)")
            }
        }
        for (index, item) in items.enumerated() {
            // A lone modifier is its own Character; stripping it would shift later positions.
            let stripped = stripEmojiModifiers(item)
            guard stripped.count == item.count else {
                skipped.append(index)
                continue
            }
            let text = String(item.prefix(head))
            let referenceText = stripEmojiModifiers(text)
            for query in ForkSearchCorpus.queries {
                let referenceQuery = stripEmojiModifiers(query)
                let forkMatch = resultKey(ForkSearch.match(query, fields: [text], profile: .fuzzy))
                let referenceMatch = referenceKey(
                    ReferenceSearch.match(referenceQuery, fields: [referenceText], profile: .fuzzy))
                compare("match", forkMatch, referenceMatch, index, query)
                if forkMatch == nil { unmatched += 1 } else { matched += 1 }
                compare(
                    "clipboardScore", ForkSearch.clipboardScore(query, item),
                    ReferenceSearch.clipboardScore(referenceQuery, stripped), index, query)
                compare(
                    "launcherScore", ForkSearch.launcherScore(query, in: text),
                    ReferenceSearch.launcherScore(referenceQuery, in: referenceText), index, query)
                compare(
                    "tiered", tierKey(ForkSearch.tiered(query, text)),
                    tierKey(ReferenceSearch.tiered(query, referenceText)), index, query)
            }
        }
        print(
            "      \(comparisons) comparisons, \(matched) fork matches, \(unmatched) fork misses, "
                + "\(skipped.count) items skipped for a changed Character count")
        check("parity corpus exercises both matches and misses", matched > 0 && unmatched > 0)
        check(
            "fork and reference agree on \(items.count - skipped.count) items x \(ForkSearchCorpus.queries.count) queries",
            mismatches.isEmpty,
            "\(mismatches.count) mismatches, first: \(mismatches.prefix(5).joined(separator: " | "))")
    }
}
