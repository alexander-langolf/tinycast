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
}
