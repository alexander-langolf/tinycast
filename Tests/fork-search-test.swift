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
    }

    static func clipboardFTS() {
        ForkSearch.setEnabled(false)
        check("off: upstream phrase", ForkSearch.clipboardFTS("march invoice") == "\"march invoice\"")
        check("off: short query falls back", ForkSearch.clipboardFTS("gh") == nil)
        check("off: quotes escaped", ForkSearch.clipboardFTS("say\"hi") == "\"say\"\"hi\"")
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        check("words ANDed", ForkSearch.clipboardFTS("march invoice") == "\"march\" AND \"invoice\"")
        check("short words left to memory", ForkSearch.clipboardFTS("gh pr create") == "\"create\"")
        check("no long word → memory", ForkSearch.clipboardFTS("gh pr") == nil)
        check("!word becomes NOT", ForkSearch.clipboardFTS("stardust !bump") == "\"stardust\" NOT \"bump\"")
        check("quotes escaped", ForkSearch.clipboardFTS("say\"hi") == "\"say\"\"hi\"")
        check(
            "accurate item filter",
            ForkSearch.contains("march invoice", in: "invoice for March", profile: .accurate)
                && !ForkSearch.contains("inv mrch", in: "invoice for March", profile: .accurate))
    }

    static func clipboardRank() {
        let newestFirst = ["March 2026 invoice total", "attaching the invoice for March", "unrelated"]
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        let ranked = ForkSearch.rankAccurate(newestFirst, query: "invoice march") { $0 }
        check("non-matches dropped", ranked.count == 2)
        check("best match first", ranked.first == "March 2026 invoice total")
        check(
            "short query keeps newest-first",
            ForkSearch.rankAccurate(newestFirst, query: "in") { $0 }
                == newestFirst.filter { $0.contains("in") })
        let differentScores = ["preinvoice premarch", "invoice march"]
        check(
            "higher score beats recency",
            ForkSearch.rankAccurate(differentScores, query: "invoice march") { $0 }
                == Array(differentScores.reversed()))
        check(
            "short query keeps order despite different scores",
            ForkSearch.rankAccurate(differentScores, query: "in") { $0 } == differentScores)
        let equalScores = ["invoice march newer", "invoice march older"]
        check(
            "equal scores keep incoming newest-first",
            ForkSearch.rankAccurate(equalScores, query: "invoice march") { $0 } == equalScores)
        ForkSearch.setEnabled(false)
        check(
            "off: input unchanged",
            ForkSearch.rankAccurate(newestFirst, query: "invoice march") { $0 } == newestFirst)
    }
}
