# fzf Search for Every Input Implementation Plan

> **For agentic workers:** Execute this plan task by task, following the global CLAUDE.md orchestration policy: delegate implementation to executor or Codex, and run a fresh-context verifier pass before reporting done. Steps use checkbox (`- [ ]`) syntax for tracking. This is a **fork** feature: read `docs/fork.md` first. Upstream-owned files get only `// FORK: search` one-liners.

**Goal:** One fzf-v2 matcher with fzf's extended syntax (`'exact`, `^prefix`, `suffix$`, `!exclude`, words in any order) behind the launcher, every tiered list, Snippets, Quicklinks, the clipboard (exact-words profile), and file search.

**Architecture:** The matcher lives in fork-owned `Tinycast/Fork/Search/`, which is Foundation-only so Model files may call it. Each existing matcher entry point gets a one-line hook guarded by `ForkSearch.isEnabled`. The switch is off by default and turned on in `ForkAppearance.start()`. Upstream's own harnesses therefore keep testing upstream behaviour, and `fork-search-test` tests the fork behaviour.

**Tech Stack:** Swift 6 (strict concurrency), Foundation, `Synchronization.Mutex`, the SQLite FTS5 trigram index (clipboard) and Spotlight MD queries (file search). Tests are standalone harnesses run by `Scripts/run-tests.sh`.

**Settled decisions** (prototype `prototype/fuzzy-search` @ `97c6596b`, `prototypes/fuzzy-search.html`):
- fzf v2 scoring: match 16, gap start −3, gap extension −1. Bonuses: after whitespace 10, after a delimiter `/,:;|` 9, after other non-word characters 8, camelCase or digit 7, consecutive 4. The first matched character's bonus counts ×2.
- Words are ANDed, in any order. No typo tolerance anywhere.
- Clipboard uses the `accurate` profile: every word must appear as typed (contiguously), in any order. Ranked by fzf score, then recency.
- Queries of 1–2 letters keep recency or use order. From 3 letters, rank by score with recency as the tie-break. The launcher keeps its own comparator, which is already use-weighted.
- Outside the clipboard, letters skipped inside a word are allowed (`pkg` → `package.json`). fzf's gap penalties rank them lower.

---

## File structure

| File | Responsibility |
|---|---|
| Create `Tinycast/Fork/Search/ForkFzf.swift` | Pure fzf v2 scorer: character classes, bonuses, exact and aligned matching of one folded term in one text |
| Create `Tinycast/Fork/Search/ForkSearch.swift` | The enabled switch, query parsing (extended syntax), multi-field matching, profiles, the short-query rule, and the adapters each hook calls |
| Create `Tests/fork-search-test.swift` | Harness for both files (fixtures from the prototype) |
| Modify `Scripts/run-tests.sh` | Register `fork-search-test`; extend the `harness-sources` hook so harnesses compiling a hooked file also compile `Tinycast/Fork/Search/*.swift` |
| Modify `Tinycast/Fork/ForkAppearance.swift` | `start()` turns the switch on (fork-owned, no upstream edit) |
| Modify (hook) `Tinycast/Features/Launcher/Model/SearchRelevance.swift` | `FuzzyMatch.match` → `ForkSearch.tiered` |
| Modify (hook) `Tinycast/Features/Launcher/Model/LauncherMatch.swift` | `LauncherMatch.match` → `ForkSearch.launcherScore`; `SearchSensitivity.accepts` → `ForkSearch.accepts` |
| Modify (hook) `Tinycast/Features/Snippets/UI/SnippetsScreen.swift`, `Tinycast/Features/Quicklinks/UI/QuicklinkListScreen.swift` | substring → `ForkSearch.contains` |
| Modify (hook) `Tinycast/Features/Clipboard/Model/ClipboardStore.swift` | `matches`, the `runSearch` FTS expression, the OCR FTS expression, and the in-memory rerank |
| Modify (hook) `Tinycast/Features/FileSearch/Model/FileSearchQuery.swift` | Spotlight name clause and rank (only if Task 9's spike passes) |
| Modify `docs/fork.md` | Hook rows (the audit reads them) and a Search section |

---

### Task 0: Branch

- [ ] **Step 1: Branch from a clean, pushed main**

```bash
cd ~/github/tinycast
git status --short   # expect: empty
git fetch origin && git status -sb | head -1   # expect: ## main...origin/main
git checkout -b al/fzf-search
```

---

### Task 1: fzf v2 scorer (`ForkFzf`)

**Files:**
- Create: `Tinycast/Fork/Search/ForkFzf.swift`
- Create: `Tests/fork-search-test.swift`
- Modify: `Scripts/run-tests.sh` (registration next to `fork-layer-test`, line ~129)

- [ ] **Step 1: Write the failing harness**

`Tests/fork-search-test.swift`:

```swift
// Pins the fork's fzf matcher: scoring shape, syntax, profiles and the hook adapters.
import Foundation

@main
struct ForkSearchTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ description: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition { print("PASS  \(description)") } else { print("FAIL  \(description)  \(detail())"); failures += 1 }
    }

    static func main() {
        scorer()
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func hit(_ term: String, _ text: String, exact: Bool = false) -> ForkFzf.Hit? {
        ForkFzf.match(Array(FuzzyMatch.normalized(term)), in: text, exact: exact)
    }

    static func scorer() {
        check("initials land on word starts", hit("vsc", "Visual Studio Code")?.positions == [0, 7, 14],
              "\(String(describing: hit("vsc", "Visual Studio Code")))")
        check("exact term found contiguously", hit("fork", "ForkTypography.swift", exact: true)?.positions == [0, 1, 2, 3])
        check("exact rejects scattered letters", hit("slk", "Slack", exact: true) == nil)
        check("fuzzy accepts scattered letters", hit("slk", "Slack") != nil)
        check("no match is nil", hit("xyz", "Slack") == nil)
        check("diacritics fold", hit("resume", "Résumé photo.jpg") != nil)
        check("camelCase hump scores as a boundary",
              (hit("ft", "ForkTypography")?.score ?? 0) > (hit("ft", "Forkfootnote")?.score ?? 0))
        check("consecutive beats scattered",
              (hit("abc", "abc def")?.score ?? 0) > (hit("abc", "a b c")?.score ?? 0))
        check("word start beats mid-word",
              (hit("set", "System Settings")?.score ?? 0) > (hit("set", "Closet")?.score ?? 0))
        check("exact picks the best-bonus occurrence",
              hit("inv", "Hi — attaching the invoice for March", exact: true)?.positions.first == 19)
    }
}
```

Register it in `Scripts/run-tests.sh`, directly after the `fork-layer-test` block:

```bash
# // FORK: fork-search pins the fork's fzf matcher, syntax, profiles and hook adapters.
run fork-search-test Tinycast/Features/Launcher/Model/SearchRelevance.swift Tinycast/Fork/Search/*.swift
```

- [ ] **Step 2: Run it and check that it fails**

Run: `./Scripts/run-tests.sh fork-search-test`
Expected: FAIL, does not compile (`cannot find 'ForkFzf' in scope`).

- [ ] **Step 3: Implement `ForkFzf`**

`Tinycast/Fork/Search/ForkFzf.swift`:

```swift
import Foundation

/// fzf v2: the best alignment of one folded term in a text, scored with fzf's bonuses and gaps.
enum ForkFzf {
    struct Hit: Sendable, Equatable {
        let score: Int
        /// Character offsets into the text, one per term character.
        let positions: [Int]
    }

    static let scoreMatch = 16
    static let gapStart = -3
    static let gapExtension = -1
    static let bonusWhite = 10
    static let bonusDelimiter = 9
    static let bonusBoundary = 8
    static let bonusCamel = 7
    static let bonusConsecutive = -(gapStart + gapExtension)
    static let firstCharMultiplier = 2

    enum CharClass: Equatable { case white, delimiter, nonWord, lower, upper, digit }

    static func charClass(_ c: Character?) -> CharClass {
        guard let c else { return .white }
        if c.isWhitespace { return .white }
        if "/,:;|".contains(c) { return .delimiter }
        if c.isNumber { return .digit }
        if c.isUppercase { return .upper }
        if c.isLetter { return .lower }
        return .nonWord
    }

    static func bonus(after prev: CharClass, at cur: CharClass) -> Int {
        guard cur == .lower || cur == .upper || cur == .digit else { return cur == .white ? 0 : bonusBoundary }
        switch prev {
        case .white: return bonusWhite
        case .delimiter: return bonusDelimiter
        case .nonWord: return bonusBoundary
        default: break
        }
        if prev == .lower, cur == .upper { return bonusCamel }
        if prev != .digit, cur == .digit { return bonusCamel }
        return 0
    }

    /// `humps` are extra word starts a folded text no longer shows (the launcher's camel humps).
    static func match(_ term: [Character], in raw: String, exact: Bool, humps: [Int] = []) -> Hit? {
        let chars = Array(raw)
        let text = chars.map { FuzzyMatch.normalized(String($0)).first ?? $0 }
        guard !term.isEmpty, term.count <= text.count else { return nil }
        var bonuses = [Int](repeating: 0, count: text.count)
        var prev = CharClass.white
        for j in chars.indices {
            let cur = charClass(chars[j])
            bonuses[j] = bonus(after: prev, at: cur)
            prev = cur
        }
        for j in humps where j < bonuses.count { bonuses[j] = max(bonuses[j], bonusCamel) }
        return exact ? exactMatch(term, text, bonuses) : align(term, text, bonuses)
    }

    /// The bonus a character earns inside a consecutive run, as fzf carries the run's first bonus.
    private static func runBonus(_ bonus: Int, carried: inout Int) -> Int {
        if bonus >= bonusBoundary, bonus > carried { carried = bonus }
        return max(bonus, carried, bonusConsecutive)
    }

    private static func exactMatch(_ term: [Character], _ text: [Character], _ bonuses: [Int]) -> Hit? {
        let m = term.count
        var best: Hit?
        for start in 0...(text.count - m) where text[start] == term[0] && Array(text[start..<start + m]) == term {
            var carried = bonuses[start]
            var score = scoreMatch + bonuses[start] * firstCharMultiplier
            for k in 1..<max(m, 1) where k < m { score += scoreMatch + runBonus(bonuses[start + k], carried: &carried) }
            if score > (best?.score ?? Int.min) { best = Hit(score: score, positions: Array(start..<start + m)) }
        }
        return best
    }

    private static func align(_ term: [Character], _ text: [Character], _ bonuses: [Int]) -> Hit? {
        let m = term.count, n = text.count
        let none = Int.min / 2
        var score = [Int](repeating: none, count: n)
        var carried = [Int](repeating: 0, count: n)
        var back: [[Int]] = [[Int](repeating: -1, count: n)]
        for j in 0..<n where text[j] == term[0] {
            score[j] = scoreMatch + bonuses[j] * firstCharMultiplier
            carried[j] = bonuses[j]
        }
        for i in 1..<max(m, 1) where i < m {
            var next = [Int](repeating: none, count: n)
            var nextCarried = [Int](repeating: 0, count: n)
            var from = [Int](repeating: -1, count: n)
            // max over k <= j-2 of score[k] + k: a gap of g letters costs gapStart + (g-1)*gapExtension = -2-g.
            var gapBest = none, gapAt = -1
            for j in 1..<n {
                if j >= 2, score[j - 2] > none, score[j - 2] + (j - 2) > gapBest {
                    gapBest = score[j - 2] + (j - 2)
                    gapAt = j - 2
                }
                guard text[j] == term[i] else { continue }
                var viaRun = none, runCarry = 0
                if score[j - 1] > none {
                    runCarry = carried[j - 1]
                    viaRun = score[j - 1] + scoreMatch + runBonus(bonuses[j], carried: &runCarry)
                }
                let viaGap = gapBest > none ? gapBest - j - 1 + scoreMatch + bonuses[j] : none
                if viaRun == none, viaGap == none { continue }
                if viaRun >= viaGap {
                    next[j] = viaRun; nextCarried[j] = runCarry; from[j] = j - 1
                } else {
                    next[j] = viaGap; nextCarried[j] = bonuses[j]; from[j] = gapAt
                }
            }
            score = next
            carried = nextCarried
            back.append(from)
        }
        guard let end = score.indices.max(by: { score[$0] < score[$1] }), score[end] > none else { return nil }
        var positions = [Int](repeating: 0, count: m)
        var j = end
        for i in stride(from: m - 1, through: 0, by: -1) {
            positions[i] = j
            j = back[i][j]
        }
        return Hit(score: score[end], positions: positions)
    }
}
```

- [ ] **Step 4: Run it and check that it passes**

Run: `./Scripts/run-tests.sh fork-search-test`
Expected: `ALL PASSED` (10 checks).

- [ ] **Step 5: Commit**

```bash
git add Tinycast/Fork/Search/ForkFzf.swift Tests/fork-search-test.swift Scripts/run-tests.sh
git commit -m "Fork search: fzf v2 scorer with harness"
```

---

### Task 2: Query syntax, profiles and the switch (`ForkSearch`)

**Files:**
- Create: `Tinycast/Fork/Search/ForkSearch.swift`
- Modify: `Tests/fork-search-test.swift`

- [ ] **Step 1: Add the failing checks**

Add `syntax()` to `main()` after `scorer()`, and add this function:

```swift
    static func syntax() {
        let invoice = "Hi Rawling — attaching the invoice for March, net 30 as agreed."
        check("words in any order", ForkSearch.match("march invoice", fields: [invoice], profile: .accurate) != nil)
        check("accurate rejects scattered letters", ForkSearch.match("inv mrch", fields: [invoice], profile: .accurate) == nil)
        check("accurate rejects a typo", ForkSearch.match("pasword", fields: ["Password reset link"], profile: .accurate) == nil)
        check("fuzzy allows skipped letters", ForkSearch.match("ariel pkg", fields: ["package.json", "~/work/ariel/"], profile: .fuzzy) != nil)
        check("!word excludes", ForkSearch.match("stardust !bump", fields: ["Stardust 5.20.0 bump complete"], profile: .fuzzy) == nil)
        check("!word keeps others", ForkSearch.match("stardust !bump", fields: ["{\"name\":\"stardust\"}"], profile: .fuzzy) != nil)
        check("^prefix anchors", ForkSearch.match("^git", fields: ["git push origin main"], profile: .fuzzy) != nil
            && ForkSearch.match("^push", fields: ["git push origin main"], profile: .fuzzy) == nil)
        check("suffix$ anchors", ForkSearch.match("json$", fields: ["package.json"], profile: .fuzzy) != nil
            && ForkSearch.match("json$", fields: ["package.json.bak"], profile: .fuzzy) == nil)
        check("'exact in the fuzzy profile", ForkSearch.match("'pkg", fields: ["package.json"], profile: .fuzzy) == nil)
        check("best field wins and positions follow it",
              ForkSearch.match("ariel", fields: ["package.json", "~/work/ariel/"], profile: .fuzzy)?.positions[1].isEmpty == false)
        check("short query rule", ForkSearch.isShort("st") && ForkSearch.isShort(" a ") && !ForkSearch.isShort("sta"))
        check("disabled by default", !ForkSearch.isEnabled)
    }
```

- [ ] **Step 2: Run it and check that it fails**

Run: `./Scripts/run-tests.sh fork-search-test`
Expected: FAIL, does not compile (`cannot find 'ForkSearch' in scope`).

- [ ] **Step 3: Implement `ForkSearch`**

`Tinycast/Fork/Search/ForkSearch.swift`:

```swift
import Foundation
import Synchronization

/// fzf extended search for every Tinycast input. Off until `ForkAppearance.start()`, so upstream harnesses keep upstream behaviour.
enum ForkSearch {
    enum Profile: Sendable { case fuzzy, accurate }

    struct Term: Sendable, Equatable {
        let text: [Character]
        let exact: Bool
        let prefix: Bool
        let suffix: Bool
        let negated: Bool
    }

    struct Result: Sendable, Equatable {
        let score: Int
        /// One array of character offsets per field.
        let positions: [[Int]]
    }

    private static let enabled = Mutex(false)
    static var isEnabled: Bool { enabled.withLock { $0 } }
    static func setEnabled(_ value: Bool) { enabled.withLock { $0 = value } }

    /// 1–2 typed letters match nearly everything, so callers keep recency or use order.
    static func isShort(_ query: String) -> Bool { query.filter { !$0.isWhitespace }.count <= 2 }

    static func terms(_ query: String, profile: Profile) -> [Term] {
        query.split(whereSeparator: \.isWhitespace).compactMap { token in
            var t = Substring(token)
            var exact = profile == .accurate, prefix = false, suffix = false, negated = false
            if t.hasPrefix("!") { negated = true; exact = true; t = t.dropFirst() }
            if t.hasPrefix("'") { exact = true; t = t.dropFirst() }
            if t.hasPrefix("^") { prefix = true; exact = true; t = t.dropFirst() }
            if t.count > 1, t.hasSuffix("$") { suffix = true; exact = true; t = t.dropLast() }
            let folded = Array(FuzzyMatch.normalized(String(t)))
            return folded.isEmpty ? nil : Term(text: folded, exact: exact, prefix: prefix, suffix: suffix, negated: negated)
        }
    }

    static func hit(_ term: Term, in field: String, humps: [Int] = []) -> ForkFzf.Hit? {
        if term.prefix {
            guard let h = ForkFzf.match(term.text, in: String(field.prefix(term.text.count)), exact: true) else { return nil }
            return h
        }
        if term.suffix {
            let start = max(0, field.count - term.text.count)
            guard let h = ForkFzf.match(term.text, in: String(field.suffix(term.text.count)), exact: true) else { return nil }
            return ForkFzf.Hit(score: h.score, positions: h.positions.map { $0 + start })
        }
        return ForkFzf.match(term.text, in: field, exact: term.exact, humps: humps)
    }

    /// Every positive word must hit some field (the best one wins); any negated word that hits rejects the item.
    static func match(_ query: String, fields: [String], weights: [Double]? = nil, profile: Profile, humps: [Int] = []) -> Result? {
        let terms = terms(query, profile: profile)
        guard terms.contains(where: { !$0.negated }) else { return nil }
        var total = 0
        var positions = Array(repeating: [Int](), count: fields.count)
        for term in terms {
            var best: (score: Int, field: Int, hit: ForkFzf.Hit)?
            for (index, field) in fields.enumerated() {
                guard let h = hit(term, in: field, humps: index == 0 ? humps : []) else { continue }
                let weighted = Int(Double(h.score) * (weights?[index] ?? 1))
                if weighted > (best?.score ?? Int.min) { best = (weighted, index, h) }
            }
            if term.negated {
                if best != nil { return nil }
                continue
            }
            guard let best else { return nil }
            total += best.score
            positions[best.field] += best.hit.positions
        }
        return Result(score: total, positions: positions)
    }

    /// For filters with no ranking of their own (Snippets, Quicklinks): upstream's substring test when off.
    static func contains(_ query: String, in text: String?, profile: Profile = .fuzzy) -> Bool {
        guard let text else { return false }
        guard isEnabled else { return text.localizedCaseInsensitiveContains(query) }
        return match(query, fields: [text], profile: profile) != nil
    }
}
```

- [ ] **Step 4: Run it and check that it passes**

Run: `./Scripts/run-tests.sh fork-search-test`
Expected: `ALL PASSED` (22 checks).

- [ ] **Step 5: Commit**

```bash
git add Tinycast/Fork/Search/ForkSearch.swift Tests/fork-search-test.swift
git commit -m "Fork search: fzf extended syntax, profiles, switch"
```

---

### Task 3: Harness sources and the switch-on

**Files:**
- Modify: `Scripts/run-tests.sh` (the existing `// FORK: harness-sources` block, line ~88)
- Modify: `Tinycast/Fork/ForkAppearance.swift:30-35`

- [ ] **Step 1: Make harnesses that compile a hooked file also compile the fork search**

Add a `case` after the existing `harness-sources` cases in `Scripts/run-tests.sh`:

```bash
    case " $* " in
        *"/SearchRelevance.swift "*|*"/LauncherMatch.swift "*|*"/ClipboardStore.swift "*|*"/FileSearchQuery.swift "*|*"/SnippetsScreen.swift "*|*"/QuicklinkListScreen.swift "*)
            case " $* " in *"Fork/Search/"*) ;; *) set -- "$@" Tinycast/Fork/Search/ForkFzf.swift Tinycast/Fork/Search/ForkSearch.swift ;; esac
            # The fork search folds through FuzzyMatch.normalized, so it needs SearchRelevance too.
            case " $* " in *"/SearchRelevance.swift "*) ;; *) set -- "$@" Tinycast/Features/Launcher/Model/SearchRelevance.swift ;; esac
            ;;
    esac
```

- [ ] **Step 2: Turn the switch on at app start (fork-owned file)**

In `ForkAppearance.start()`, after `assets.publish()`:

```swift
        ForkSearch.setEnabled(true)
```

- [ ] **Step 3: Check that nothing regressed**

Run: `./Scripts/run-tests.sh`
Expected: every harness passes, as before. The switch is off in harnesses, so upstream suites still see upstream behaviour.

- [ ] **Step 4: Commit**

```bash
git add Scripts/run-tests.sh Tinycast/Fork/ForkAppearance.swift
git commit -m "Fork search: harness sources and app-start switch"
```

---

### Task 4: Hook the tiered matcher (menus, windows, rooms, emoji, notes, settings, action menu, extensions)

**Files:**
- Modify: `Tinycast/Fork/Search/ForkSearch.swift`
- Modify: `Tinycast/Features/Launcher/Model/SearchRelevance.swift` (`FuzzyMatch.match(_:candidate:)` for `Candidate`, right after `let c = candidate.text`)
- Modify: `Tests/fork-search-test.swift`

- [ ] **Step 1: Add the failing check**

Add `tiered()` to `main()` and add:

```swift
    static func tiered() {
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        let exact = FuzzyMatch.match(query: "notes", candidate: "Notes")
        check("exact tier kept", exact?.tier == .exact)
        check("prefix tier kept", FuzzyMatch.match(query: "sys", candidate: "System Settings")?.tier == .prefix)
        check("any-order words now match", FuzzyMatch.match(query: "settings system", candidate: "System Settings") != nil)
        check("initials match as subsequence", FuzzyMatch.match(query: "sysset", candidate: "System Settings")?.tier == .subsequence)
        check("no typo tolerance", FuzzyMatch.match(query: "sytsem", candidate: "System Settings") == nil)
    }
```

- [ ] **Step 2: Run it and check that it fails**

Run: `./Scripts/run-tests.sh fork-search-test`
Expected: FAIL on "any-order words now match" (upstream's tiered matcher needs the words in order).

- [ ] **Step 3: Implement the adapter and the hook**

Add to `ForkSearch`:

```swift
    /// The tiered matcher's answer computed by fzf, with tiers kept so `SearchRelevance` weights still apply.
    static func tiered(_ q: String, _ c: String) -> FuzzyMatch.Match? {
        let length = c.count
        guard !q.isEmpty else { return FuzzyMatch.Match(tier: .exact, offset: 0, queryLength: 0, candidateLength: length, spread: 0) }
        guard let r = match(q, fields: [c], profile: .fuzzy) else { return nil }
        let p = r.positions[0].sorted()
        let contiguous = !p.isEmpty && p.last! - p.first! + 1 == p.count
        let tier: FuzzyMatch.Tier =
            c == q ? .exact
            : contiguous && p.first == 0 ? .prefix
            : contiguous && ForkFzf.bonus(after: ForkFzf.charClass(p.first! > 0 ? Array(c)[p.first! - 1] : nil),
                                          at: ForkFzf.charClass(Array(c)[p.first!])) >= ForkFzf.bonusBoundary ? .wordStart
            : contiguous ? .substring : .subsequence
        return FuzzyMatch.Match(tier: tier, offset: p.first ?? 0, queryLength: q.count, candidateLength: length,
                                spread: tier == .subsequence ? r.score : 0)
    }
```

In `SearchRelevance.swift`, inside `static func match(_ query: Query, candidate: Candidate) -> Match?`, directly after `let c = candidate.text`:

```swift
        if ForkSearch.isEnabled { return ForkSearch.tiered(q, c) }  // FORK: search
```

- [ ] **Step 4: Run it and check that it passes**

Run: `./Scripts/run-tests.sh fork-search-test && ./Scripts/run-tests.sh`
Expected: `ALL PASSED`, and the full suite stays green.

- [ ] **Step 5: Commit**

```bash
git add Tinycast/Fork/Search/ForkSearch.swift Tinycast/Features/Launcher/Model/SearchRelevance.swift Tests/fork-search-test.swift
git commit -m "Fork search: tiered matcher answers via fzf"
```

---

### Task 5: Hook the launcher aligner and its sensitivity

**Files:**
- Modify: `Tinycast/Fork/Search/ForkSearch.swift`
- Modify: `Tinycast/Features/Launcher/Model/LauncherMatch.swift` (first line of `LauncherMatch.match`; in `SearchSensitivity.accepts` after `let length = …`)
- Modify: `Tests/fork-search-test.swift`

- [ ] **Step 1: Add the failing checks** (calibrated on the prototype's app list)

Add `launcher()` to `main()` and add:

```swift
    static func launcher() {
        func accepted(_ q: String, _ t: String, _ level: String = "medium") -> Bool {
            guard let s = ForkSearch.launcherScore(q, in: t) else { return false }
            return s == .max || ForkSearch.accepts(score: s, letters: q.filter { !$0.isWhitespace }.count, level: level)
        }
        check("vsc → Visual Studio Code", accepted("vsc", "Visual Studio Code"))
        check("slk → Slack", accepted("slk", "Slack"))
        check("saf → Safari", accepted("saf", "Safari"))
        check("exact is max", ForkSearch.launcherScore("slack", in: "slack") == .max)
        check("scattered junk rejected at medium", !accepted("lnd", "alexander-langolf"))
        check("low accepts anything matched", accepted("lnd", "alexander-langolf", "low"))
        check("camel hump honoured", (ForkSearch.launcherScore("gh", in: "github", humps: [3]) ?? 0)
            > (ForkSearch.launcherScore("gh", in: "github") ?? 0))
    }
```

- [ ] **Step 2: Run it and check that it fails**

Run: `./Scripts/run-tests.sh fork-search-test`
Expected: FAIL, does not compile (`launcherScore` and `accepts` are missing).

- [ ] **Step 3: Implement the adapters and the hooks**

Add to `ForkSearch`:

```swift
    /// The launcher's texts are folded or transliterated already; `humps` restore the camel starts folding lost.
    static func launcherScore(_ query: String, in target: String, humps: [Int] = []) -> Int? {
        if FuzzyMatch.normalized(query) == FuzzyMatch.normalized(target) { return .max }
        return match(query, fields: [target], profile: .fuzzy, humps: humps)?.score
    }

    /// fzf scores about 16 per letter plus bonuses, so thresholds are per-letter averages (`level` = `SearchSensitivity.rawValue`).
    static func accepts(score: Int, letters: Int, level: String) -> Bool {
        switch level {
        case "low": return true
        case "high": return score >= 24 * letters
        default: return score >= 20 * letters - 4
        }
    }
```

In `LauncherMatch.swift`, the first line of `static func match(_ query: SearchText, in target: SearchText) -> Outcome?`:

```swift
        if ForkSearch.isEnabled { return ForkSearch.launcherScore(query.string, in: target.string, humps: target.humps).map { $0 == .max ? .exact : .scored(score: $0, skipped: 0) } }  // FORK: search
```

In `SearchSensitivity.accepts`, directly after `let length = queryLength - skipped`:

```swift
        if ForkSearch.isEnabled { return ForkSearch.accepts(score: score, letters: length, level: rawValue) }  // FORK: search
```

- [ ] **Step 4: Run it and check that it passes, then calibrate**

Run: `./Scripts/run-tests.sh fork-search-test`
Expected: `ALL PASSED`. If "scattered junk rejected" or an accepted case fails, adjust only the two numbers in `accepts` (per-letter average and slack) until all 7 pass, then re-run.

- [ ] **Step 5: Commit**

```bash
git add Tinycast/Fork/Search/ForkSearch.swift Tinycast/Features/Launcher/Model/LauncherMatch.swift Tests/fork-search-test.swift
git commit -m "Fork search: launcher aligner and sensitivity via fzf"
```

---

### Task 6: Snippets and Quicklinks lists

**Files:**
- Modify: `Tinycast/Features/Snippets/UI/SnippetsScreen.swift:18-19`
- Modify: `Tinycast/Features/Quicklinks/UI/QuicklinkListScreen.swift:17`

- [ ] **Step 1: Replace the substring tests**

`SnippetsScreen.swift` lines 18–19 become:

```swift
            ForkSearch.contains(query, in: record.snippet.name)  // FORK: search
                || ForkSearch.contains(query, in: record.snippet.keyword)  // FORK: search
```

`QuicklinkListScreen.swift` line 17 becomes:

```swift
        return store.enabled.filter { ForkSearch.contains(query, in: $0.name) }  // FORK: search
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug -derivedDataPath /tmp/tc-dd CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Tinycast/Features/Snippets/UI/SnippetsScreen.swift Tinycast/Features/Quicklinks/UI/QuicklinkListScreen.swift
git commit -m "Fork search: Snippets and Quicklinks filter with fzf"
```

---

### Task 7: Clipboard retrieval (words ANDed in FTS, accurate filter in memory)

**Files:**
- Modify: `Tinycast/Fork/Search/ForkSearch.swift`
- Modify: `Tinycast/Features/Clipboard/Model/ClipboardStore.swift` (`ClipboardItem.matches` ~line 80; `runSearch` ~lines 592–593; OCR query ~line 708)
- Modify: `Tests/fork-search-test.swift`

- [ ] **Step 1: Add the failing checks**

Add `clipboardFTS()` to `main()` and add:

```swift
    static func clipboardFTS() {
        ForkSearch.setEnabled(false)
        check("off: upstream phrase", ForkSearch.clipboardFTS("march invoice") == "\"march invoice\"")
        check("off: short query falls back", ForkSearch.clipboardFTS("gh") == nil)
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        check("words ANDed", ForkSearch.clipboardFTS("march invoice") == "\"march\" AND \"invoice\"")
        check("short words left to memory", ForkSearch.clipboardFTS("gh pr create") == "\"create\"")
        check("no long word → memory", ForkSearch.clipboardFTS("gh pr") == nil)
        check("!word becomes NOT", ForkSearch.clipboardFTS("stardust !bump") == "\"stardust\" NOT \"bump\"")
        check("quotes escaped", ForkSearch.clipboardFTS("say\"hi") == "\"say\"\"hi\"")
        check("accurate item filter", ForkSearch.contains("march invoice", in: "invoice for March", profile: .accurate)
            && !ForkSearch.contains("inv mrch", in: "invoice for March", profile: .accurate))
    }
```

- [ ] **Step 2: Run it and check that it fails**

Run: `./Scripts/run-tests.sh fork-search-test`
Expected: FAIL, does not compile (`clipboardFTS` is missing).

- [ ] **Step 3: Implement `clipboardFTS`**

Add to `ForkSearch`:

```swift
    /// The trigram FTS expression for a clipboard query. Off: upstream's quoted phrase (3+ chars).
    /// On: each word of 3+ letters as an ANDed phrase and `!word` as NOT; nil when no word is long enough.
    static func clipboardFTS(_ query: String) -> String? {
        let quote = { (s: Substring) in "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        guard isEnabled else { return query.count >= 3 ? quote(Substring(query)) : nil }
        var positive: [String] = [], negative: [String] = []
        for token in query.split(whereSeparator: \.isWhitespace) {
            let negated = token.hasPrefix("!")
            var t = token.drop { "!'^".contains($0) }
            if t.count > 1, t.hasSuffix("$") { t = t.dropLast() }
            guard t.count >= 3 else { continue }
            negated ? negative.append(quote(t)) : positive.append(quote(t))
        }
        guard !positive.isEmpty else { return nil }
        return positive.joined(separator: " AND ") + negative.map { " NOT " + $0 }.joined()
    }
```

- [ ] **Step 4: Hook the store**

`ClipboardItem.matches` body:

```swift
        ForkSearch.contains(query, in: text, profile: .accurate)  // FORK: search
```

`runSearch`: replace the `guard` line and the `let match = …` line with:

```swift
        guard let stmt = searchStmt, q.count >= 3, let match = ForkSearch.clipboardFTS(q) else { return fallbackSearch(q) }  // FORK: search
```

OCR text search (~line 708): replace `let match = "\"" + query.replacingOccurrences(of: "\"", with: "\"\"") + "\""` with:

```swift
            let match = ForkSearch.clipboardFTS(query) ?? "\"" + query.replacingOccurrences(of: "\"", with: "\"\"") + "\""  // FORK: search
```

- [ ] **Step 5: Run the tests**

Run: `./Scripts/run-tests.sh fork-search-test && ./Scripts/run-tests.sh clipboard-test`
Expected: both pass. clipboard-test runs with the switch off, so upstream behaviour holds.

- [ ] **Step 6: Commit**

```bash
git add Tinycast/Fork/Search/ForkSearch.swift Tinycast/Features/Clipboard/Model/ClipboardStore.swift Tests/fork-search-test.swift
git commit -m "Fork search: clipboard words ANDed in FTS, accurate in memory"
```

---

### Task 8: Clipboard ranking (fzf score, then recency; short queries newest first)

**Files:**
- Modify: `Tinycast/Fork/Search/ForkSearch.swift`
- Modify: `Tinycast/Features/Clipboard/Model/ClipboardStore.swift` (`unfiltered`, the `ordinary` line ~580)
- Modify: `Tests/fork-search-test.swift`

- [ ] **Step 1: Add the failing checks**

Add `clipboardRank()` to `main()` and add:

```swift
    static func clipboardRank() {
        let newestFirst = ["March 2026 invoice total", "attaching the invoice for March", "unrelated"]
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        let ranked = ForkSearch.rankAccurate(newestFirst, query: "invoice march") { $0 }
        check("non-matches dropped", ranked.count == 2)
        check("best match first", ranked.first == "March 2026 invoice total")
        check("short query keeps newest-first", ForkSearch.rankAccurate(newestFirst, query: "in") { $0 } == newestFirst.filter { $0.contains("in") })
        ForkSearch.setEnabled(false)
        check("off: input unchanged", ForkSearch.rankAccurate(newestFirst, query: "invoice march") { $0 } == newestFirst)
    }
```

- [ ] **Step 2: Run it and check that it fails**

Run: `./Scripts/run-tests.sh fork-search-test`
Expected: FAIL, does not compile (`rankAccurate` is missing).

- [ ] **Step 3: Implement it and hook it**

Add to `ForkSearch`:

```swift
    /// Clipboard order: input arrives newest first; ties keep it. Off: unchanged.
    static func rankAccurate<T>(_ items: [T], query: String, text: (T) -> String?) -> [T] {
        guard isEnabled else { return items }
        let scored = items.enumerated().compactMap { offset, item -> (score: Int, offset: Int, item: T)? in
            guard let s = text(item), let r = match(query, fields: [s], profile: .accurate) else { return nil }
            return (r.score, offset, item)
        }
        guard !isShort(query) else { return scored.map(\.item) }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }.map(\.item)
    }
```

In `ClipboardStore.unfiltered`, replace `runSearch(q).filter { !$0.isPinned }` with:

```swift
ForkSearch.rankAccurate(runSearch(q).filter { !$0.isPinned }, query: q) { $0.text }  // FORK: search
```

(Pins keep upstream's pin order on purpose.)

- [ ] **Step 4: Run it and check that it passes**

Run: `./Scripts/run-tests.sh fork-search-test && ./Scripts/run-tests.sh`
Expected: `ALL PASSED`, and the full suite stays green.

- [ ] **Step 5: Commit**

```bash
git add Tinycast/Fork/Search/ForkSearch.swift Tinycast/Features/Clipboard/Model/ClipboardStore.swift Tests/fork-search-test.swift
git commit -m "Fork search: clipboard ranks by fzf score, then recency"
```

---

### Task 9: File search spike (decide before building)

**Question:** can Spotlight return fuzzy candidates fast enough with a subsequence glob (`kMDItemFSName == "*f*o*r*k*"cd`), or do we need a path index of our own?

**Files:**
- Create: `prototypes/spotlight-glob-spike.sh` (on `prototype/fuzzy-search`, not on this branch)
- Create: `docs/fork-search-spike.md` (on this branch; records the verdict)

- [ ] **Step 1: Write the timing script**

```bash
#!/bin/bash
# PROTOTYPE: compare Spotlight substring vs subsequence-glob name queries. Read-only.
terms=(fork forktypo invmarch ariel pkg agenda sigils stardust tc)
for t in "${terms[@]}"; do
  glob=$(echo "$t" | sed 's/./*&/g')*
  for q in "kMDItemFSName == \"*$t*\"cd" "kMDItemFSName == \"$glob\"cd"; do
    start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    n=$(mdfind -onlyin "$HOME" "$q" | head -1000 | wc -l | tr -d ' ')
    end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    printf "%-10s %-40s %5s results %6.0f ms\n" "$t" "$q" "$n" "$(echo "($end-$start)*1000" | bc)"
  done
done
```

- [ ] **Step 2: Run it three times and record the medians**

Run: `bash prototypes/spotlight-glob-spike.sh` (×3)
Record for each term: result count and median ms, substring vs glob.

- [ ] **Step 3: Decide and record**

Write `docs/fork-search-spike.md` with the table and the verdict:
- **Glob wins** if the median glob latency is ≤ 150 ms for 3–8 letter terms and the count stays under 1,000 for terms of 4+ letters → do Task 10.
- **Otherwise** a path index of our own is needed. Stop here and open a separate plan; do not do Task 10.

```bash
git add docs/fork-search-spike.md
git commit -m "Fork search: Spotlight subsequence-glob spike verdict"
```

---

### Task 10 (only if the glob wins): file search via glob + fzf rank

**Files:**
- Modify: `Tinycast/Fork/Search/ForkSearch.swift`
- Modify: `Tinycast/Features/FileSearch/Model/FileSearchQuery.swift` (`expression` matches line; first line of `rank`)
- Modify: `Tests/fork-search-test.swift`

- [ ] **Step 1: Add the failing checks**

Add `files()` to `main()` and add:

```swift
    static func files() {
        ForkSearch.setEnabled(true)
        defer { ForkSearch.setEnabled(false) }
        check("glob interleaves letters", ForkSearch.spotlightNameClause("fork") == "kMDItemFSName == \"*f*o*r*k*\"cd")
        check("'exact stays substring", ForkSearch.spotlightNameClause("'fork") == "kMDItemFSName == \"*fork*\"cd")
        check("glob metacharacters escaped", ForkSearch.spotlightNameClause("a*b") == "kMDItemFSName == \"*a*\\\\**b*\"cd")
        check("negated word is NOT clause", ForkSearch.spotlightNameClause("!bak") == "kMDItemFSName != \"*bak*\"cd")
        let ranked = ForkSearch.rankPaths([("package-lock.json", "~/work/ariel/js/"), ("package.json", "~/work/ariel/")], query: "ariel pkg")
        check("folder words count", ranked.count == 2)
        check("tighter name first", ranked.first == 1)
    }
```

- [ ] **Step 2: Run it and check that it fails**

Run: `./Scripts/run-tests.sh fork-search-test`
Expected: FAIL, does not compile (`spotlightNameClause` and `rankPaths` are missing).

- [ ] **Step 3: Implement it and hook it**

Add to `ForkSearch`:

```swift
    /// One Spotlight name clause per word: a subsequence glob, or a substring for 'exact/^/$ words; !word negates.
    static func spotlightNameClause(_ token: String) -> String {
        let negated = token.hasPrefix("!")
        var t = Substring(token).drop { "!'^".contains($0) }
        let exact = negated || token.hasPrefix("'") || token.hasPrefix("^") || (t.count > 1 && t.hasSuffix("$"))
        if t.count > 1, t.hasSuffix("$") { t = t.dropLast() }
        let escaped = t.map { "*?\\\"".contains($0) ? "\\\\\($0)" : String($0) }
        let pattern = exact ? "*" + escaped.joined() + "*" : "*" + escaped.joined(separator: "*") + "*"
        return "kMDItemFSName \(negated ? "!=" : "==") \"\(pattern)\"cd"
    }

    /// Indices of (name, folder) pairs ranked by fzf (folder hits weigh 0.6), then shorter name (fzf's
    /// default tie-break), then incoming order; short queries keep the incoming order.
    static func rankPaths(_ items: [(name: String, folder: String)], query: String) -> [Int] {
        let scored = items.enumerated().compactMap { index, item -> (score: Int, length: Int, index: Int)? in
            match(query, fields: [item.name, item.folder], weights: [1, 0.6], profile: .fuzzy).map { ($0.score, item.name.count, index) }
        }
        guard !isShort(query) else { return scored.map(\.index) }
        return scored.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.length != $1.length ? $0.length < $1.length : $0.index < $1.index
        }.map(\.index)
    }
```

In `FileSearchQuery.expression`, replace the `let matches = …` line with:

```swift
        let matches = terms.map { ForkSearch.isEnabled ? ForkSearch.spotlightNameClause($0) : "kMDItemFSName == \"*\(escape($0))*\"cd" }  // FORK: search
```

In `FileSearchQuery.rank`, after `guard !terms.isEmpty else { return [] }`:

```swift
        if ForkSearch.isEnabled { let kept = results.filter { !isExcludedPath($0.id, ignoring: ignore) }; return ForkSearch.rankPaths(kept.map { ($0.name, $0.parentPath) }, query: query).prefix(resultLimit).map { kept[$0] } }  // FORK: search
```

- [ ] **Step 4: Run it and check that it passes**

Run: `./Scripts/run-tests.sh fork-search-test && ./Scripts/run-tests.sh`
Expected: `ALL PASSED`, and the full suite stays green (file-search harnesses run with the switch off).

- [ ] **Step 5: Commit**

```bash
git add Tinycast/Fork/Search/ForkSearch.swift Tinycast/Features/FileSearch/Model/FileSearchQuery.swift Tests/fork-search-test.swift
git commit -m "Fork search: file search via Spotlight subsequence glob + fzf rank"
```

---

### Task 11: Fork docs, audit, verification, merge

**Files:**
- Modify: `docs/fork.md`

- [ ] **Step 1: Document the hooks**

Add one row per hooked file to the `## Upstream hooks` table (the audit reads it):

```markdown
| `Tinycast/Features/Launcher/Model/SearchRelevance.swift` | `// FORK: search` | `FuzzyMatch.match` answers via fzf (tiers kept). |
| `Tinycast/Features/Launcher/Model/LauncherMatch.swift` | `// FORK: search` | Launcher alignment and sensitivity via fzf. |
| `Tinycast/Features/Snippets/UI/SnippetsScreen.swift` | `// FORK: search` | Snippet filter via fzf. |
| `Tinycast/Features/Quicklinks/UI/QuicklinkListScreen.swift` | `// FORK: search` | Quicklink filter via fzf. |
| `Tinycast/Features/Clipboard/Model/ClipboardStore.swift` | `// FORK: search` | Words ANDed in FTS, exact-words filter, fzf rank. |
| `Tinycast/Features/FileSearch/Model/FileSearchQuery.swift` | `// FORK: search` | Spotlight subsequence glob and fzf rank (if Task 10 ran). |
| `Scripts/run-tests.sh` | `// FORK: fork-search` | Registers the fork search harness. |
```

Add a `## Search` section: the switch, the settled decisions, the two profiles, and the short-query rule, linking `prototype/fuzzy-search`.

- [ ] **Step 2: Audit, format, full suite, build**

```bash
./Scripts/fork-audit.sh            # expect: Fork audit passed (… documented hooks …)
./Scripts/format.sh                # then revert formatter-only churn in files this branch did not touch
./Scripts/run-tests.sh             # expect: all harnesses passed
xcodegen generate && xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug -derivedDataPath /tmp/tc-dd CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 3: Manual check in Tinycast Dev** (restart it on the new build)

- Launcher: `vsc`, `slk`, `settings system`, `!safari s` (Safari is excluded).
- Clipboard: copy "attaching the invoice for March", then search `march invoice` (found), `inv mrch` (not found), `^attach` (found).
- Menus, notes, settings, emoji: a two-word query in reverse order finds the item.
- Files (if Task 10 ran): `forktypo`, `ariel pkg`.

- [ ] **Step 4: Fresh-context verifier pass**

Give the verifier this plan's decisions list and the branch diff, and ask it to refute "every input uses fzf matching per the decisions, upstream harnesses are unchanged, and the upstream footprint is only `// FORK: search` lines".

- [ ] **Step 5: Merge and push**

```bash
git checkout main && git merge --no-ff al/fzf-search -m "Merge al/fzf-search: fzf search for every input"
./Scripts/fork-audit.sh && ./Scripts/run-tests.sh
git push origin main
```

---

## Self-review notes

- **Spec coverage:**
  - fzf v2: Task 1. Syntax and any order: Task 2.
  - No typos: Tasks 2 and 4 checks.
  - Clipboard accurate profile: Tasks 7 and 8. Short-query rule: Task 2 (`isShort`), used in Tasks 8 and 10. The launcher keeps its own comparator, by decision.
  - Skipped letters outside the clipboard: Task 2's `fuzzy allows skipped letters` check.
  - Every input: the tiered surfaces in Task 4, the launcher in Task 5, Snippets and Quicklinks in Task 6, clipboard in Tasks 7–8, files in Tasks 9–10.
- **Known limits, accepted:**
  - Plain substring filters elsewhere stay as they are: Uninstall, calculator history, AI chat lists, window layouts and settings lists. That's a follow-up if wanted.
  - The launcher's humps are UTF-16 offsets, used as character offsets; this is exact for BMP text.
  - Clipboard FTS still caps at 200 newest candidates before the rerank.
- **Upstream footprint:** about 9 one-line hooks across 7 upstream files, plus one `run-tests.sh` registration.
