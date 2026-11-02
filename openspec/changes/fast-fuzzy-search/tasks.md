> Every task below is sized for one Haiku executor run. Each names its files, its done check, and
> the spec or design section it implements. Run `./Scripts/run-tests.sh` after each group, not only
> at the end.

## 1. Baseline and parity harness

- [x] 1.1 Copy `Tinycast/Fork/Search/ForkFzf.swift` and `ForkSearch.swift` unchanged into
  `Tests/fork-search-reference/` as `ReferenceFzf.swift` and `ReferenceSearch.swift`. Rename the
  enums to `ReferenceFzf` and `ReferenceSearch`, and rename every internal reference to match.
  These copies are the retired scorer that parity compares against (design: Risks, first item).
- [x] 1.2 Add `Tests/fork-search-corpus.swift`. It defines `ForkSearchCorpus.items(count:seed:)`,
  which returns deterministic synthetic clipboard texts. Ten percent of them are non-ASCII and mix
  emoji, ZWJ sequences, flags, accented prose, "Straße", CJK, combining marks and `\r\n` line
  endings. Lengths follow 20 / 200 / 2,000 / 15,000 characters at 50 / 35 / 13 / 2 percent. The
  file also defines `ForkSearchCorpus.queries`: `c`, `co`, `con`, `config`, `tinycast`,
  `swift ui`, `xyzq`, `https github`, `'exact`, `^pre`, `fix$`, `!skip word`, `strasse`, `café`
  and `日本`.
- [x] 1.3 Add a parity section to `Tests/fork-search-test.swift`. For every corpus item (count
  1,000, fixed seed) and every query, it compares `ForkSearch.match` with `ReferenceSearch.match`
  on fields `[text]` with profile `.fuzzy`. It also compares `clipboardScore`, `launcherScore` and
  `tiered`. Results must be equal, including positions. Register the reference and corpus files on
  the `fork-search-test` line in `Scripts/run-tests.sh`. Done when the suite passes against the
  unchanged scorer.

## 2. Prepared text and compiled query

- [x] 2.1 Create `Tinycast/Fork/Search/ForkSearchText.swift` with `ForkSearch.Text`, a `Sendable`
  struct holding `units: [UInt32]`, `bonuses: [UInt8]`, `sources: [Int32]?` and `length: Int`.
  Its initialiser is `init(_ raw: String, scheme: ForkFzf.Scheme = .standard, humps: [Int] = [])`.
  ASCII text without `\r` uses lowercased bytes and `sources = nil`. Any other text walks
  `Character`s once, folding exactly as the general path in `ForkFzf.match` does (design §1).
  Append the file to the three places where `Scripts/run-tests.sh` lists the `Fork/Search` sources:
  lines ~126, ~171 and ~183.
- [x] 2.2 In the same file, add `ForkSearch.unitCode(_ c: Character) -> UInt32`. A single scalar
  after NFC returns its value. Any other grapheme gets a code from a `Mutex<[String: UInt32]>`
  intern table that starts at `0x110000`. Encode `Term.text` with the same function and store the
  result as a new `Term.units: [UInt32]` field.
- [x] 2.3 Add `ForkSearch.Query`, a `Sendable` struct built by
  `ForkSearch.Query(_ query: String, profile: Profile)`. It holds `terms`, `positive` and the
  `letters` count that `launcherScore` uses. `terms(_:profile:)` stays the parser.
- [x] 2.4 Unit-test `Text` in `fork-search-test`. ASCII text gets `sources == nil`. "Straße" gets
  6 source characters and 7 units. `"a\r\nb"` gets 3 source characters. A flag emoji encodes to
  one unit equal to the unit of the same flag in a query.

## 3. Unit scorer

- [x] 3.1 In `ForkFzf.swift`, add
  `static func match(_ term: [UInt32], in text: ForkSearch.Text, exact: Bool) -> Hit?`. It runs
  `containsSubsequence` over `text.units` first, then `exactMatch` or `align` over units and
  bonuses, then maps positions through `sources` (sorted and unique, as today). Change `align` to
  use one flat `[Int32]` back-pointer buffer of `m × n` entries (design §3).
- [x] 3.2 Rewrite the existing
  `ForkFzf.match(_ term: [Character], in raw: String, exact:humps:scheme:)` as
  `match(units(term), in: ForkSearch.Text(raw, scheme:, humps:), exact:)`. Delete both old
  per-path bodies, so one implementation remains.
- [x] 3.3 In `ForkSearch.swift`, change `hit(_:in:)` to take a `ForkSearch.Text`. Prefix and suffix
  anchors compare against `text.units` rather than calling `FuzzyMatch.normalized(field)`. Keep a
  `String` overload that prepares and forwards to it.
- [x] 3.4 Add `Query`-taking overloads of `match(_:fields:…)`, `clipboardScore`, `launcherScore`
  and `tiered`, all over prepared `Text`. `tiered` must compute `Array(c)` once, not twice. The
  `String` overloads compile a `Query` and forward. Done when parity (1.3) and every existing
  `fork-search-test` assertion pass.

## 4. Performance harness

- [x] 4.1 Add `Tests/fork-search-performance.swift`. It prepares 1,000 corpus items, then times
  each query over all items with `ForkSearch.clipboardScore(query, text, raw:)` on prepared text.
  It reports the warm median of 9 runs and the cold time, as JSON, the same way
  `emoji-search-performance` does. It exits non-zero when a warm median exceeds 5 ms (spec: Search
  stays within its time budget).
- [x] 4.2 Register it in `Scripts/run-tests.sh` as `run -O fork-search-performance`. Done
  when it passes.
- [x] 4.3 In `project.yml`, set `SWIFT_OPTIMIZATION_LEVEL: -O` under the `Tinycast` target's
  `configs: Debug:` settings. Run `xcodegen generate`. Done when the Debug build compiles with no
  new warnings and its build log shows `-O` for the `Tinycast` target (design §7).

## 5. Clipboard text-only scope and cache

- [x] 5.1 In `ClipboardStore.swift`, mark with `// FORK: search` and change `searchStmt` so that,
  when `ForkSearch.isEnabled`, the inner FTS select joins `items` and keeps only
  `kind = 'text'`. Prepare a second statement rather than branching the SQL text at run time.
- [x] 5.2 In `unfiltered(_:filter:)` and `ForkSearch.clipboardResults`, pass only `kind == .text`
  items, pinned and resident alike, when fork search is on.
- [x] 5.3 Make `updateTextSearch` return at once when `ForkSearch.isEnabled` (`// FORK: search`).
- [x] 5.4 Add `@ObservationIgnored private var preparedText: [UUID: ForkSearch.Text]` to
  `ClipboardStore`, with lookup-or-prepare of the 4,096-character head. Wherever
  `invalidateSearch` runs after `items` changes, drop entries whose IDs are not in `items`. Cap
  non-resident entries at `searchLimit` and evict them first (design §4). Pass prepared text into
  `clipboardResults` through a new `prepared: (T) -> ForkSearch.Text?` closure.
- [x] 5.5 Extend `Tests/clipboard-search-test.swift`. With fork search on:
  - a file entry whose path contains "report" does not match `report`;
  - a pinned image never appears in typed results;
  - an empty query lists all kinds;
  - the Images filter with a query is empty;
  - extending a query prepares no further text, which a test-only counter on the cache shows;
  - deleting an item removes its cache entry.

## 6. Recognized-text search off under fork search

- [x] 6.1 In `AppCore.applyClipboardTextSearch`, treat `ForkSearch.isEnabled` as disabled
  (`// FORK: search`), so no `ClipboardTextIndexer` is created and a running one is cancelled.
- [x] 6.2 Hide the "Search text in images and PDFs" toggle in `ClipboardSettingsView` and its
  `SettingsSearchCatalog` entry when `ForkSearch.isEnabled` (`// FORK: search`). Check that the
  settings-search harness still passes.
- [x] 6.3 Confirm Copy Text still extracts on demand by reading `ClipboardCoordinator`'s Copy Text
  path. No code change needed.
  - Result: `copyImageText` calls `ClipboardTextWorker.extract` directly. It reads neither
    `clipboardTextSearchEnabled` nor `ClipboardTextIndexer`, so Copy Text works with fork search on.

## 7. Other callers

- [x] 7.1 `LauncherMatch.match`: compile one `ForkSearch.Query` per keystroke. Store a prepared
  `ForkSearch.Text` (built with `target.humps`) on `SearchText` when the entry is created, and
  score against it.
- [x] 7.2 `FileNavigatorState` name filter, `SnippetsScreen` and `QuicklinkListScreen`: compile the
  query once per filter pass and use the `Query` overloads.
- [x] 7.3 Run the launcher, file-navigator, snippet and quicklink harnesses. Done when all pass
  unchanged.

## 8. Docs, checks and verification

- [x] 8.1 Update the Search section of `docs/fork.md`: prepared text, compiled query, text-only
  clipboard scope, recognized text off, and the performance budgets. Update
  `docs/features/clipboard.md` where it describes typed search over images, files and OCR.
- [x] 8.2 Run `./Scripts/run-tests.sh`, `./Scripts/lint.sh`, the Debug build (no new warnings) and
  the AGENTS.md Model-import grep. Fix anything they report.
- [ ] 8.3 Rebuild and relaunch Tinycast Dev, then check its start time. Type into the clipboard
  palette over the real history. Confirm typing is smooth, that images and files are absent from
  typed results, and that the settings switch is hidden.
- [x] 8.4 Run a `verifier` agent against the specs and the diff before reporting done.

## 9. One fold for every match

- [x] 9.1 Add `ForkSearch.fold(_:)`: `FuzzyMatch.normalized` with U+1F3FB–U+1F3FF and U+FE0E/U+FE0F
  removed. Use it everywhere the fork folds: `terms`, `Text` preparation, `Text.folded`,
  `Query.normalized` and anchors. `FuzzyMatch.normalized` itself stays upstream's.
- [x] 9.2 Make the parity harness strip those scalars from items and queries before calling the
  reference scorer, so parity checks everything except the deliberate fold change.
- [x] 9.3 Add `fork-search-test` cases for each scenario of the "One fold serves every match"
  requirement, through `clipboardResults` with an FTS hit as well as `clipboardScore`.
- [x] 9.4 Update `docs/fork.md` (Search) to state the fold. Run the full suite, lint and the Debug
  build, then rebuild and relaunch Tinycast Dev.

