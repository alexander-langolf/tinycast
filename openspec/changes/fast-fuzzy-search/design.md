## Context

Every Tinycast list surface matches through one fzf v2 scorer in `Tinycast/Fork/Search/`.
`ForkFzf.match` scores one folded term against one raw string. `ForkSearch` parses the fzf syntax
and adapts the scorer to its callers: the clipboard, the launcher (`LauncherMatch`,
`SearchRelevance.tiered`), Snippets, Quicklinks and File Navigator name filters.

`ForkFzf.match` has two paths:

- **ASCII path.** It runs when the text is ASCII without `\r` and the term is ASCII. It copies the
  bytes, lowercases them, checks the subsequence and only then computes bonuses.
- **General path.** It runs for any other text. It splits the text into `Character`s, folds each
  one through `FuzzyMatch.normalized`, and builds folded, source and bonus arrays. Only then does it
  check the subsequence.

`ForkSearch` re-parses the query for every candidate, and the clipboard copies a 4,096-character
head of every item. Nothing is reused between keystrokes.

The following figures come from the Dev clipboard on 2026-10-17: 783 text items, 155 KB, 77 of
them non-ASCII. Each figure is the time to score every item once.

| Build | ASCII items | Non-ASCII items |
| --- | --- | --- |
| `-O` | ~1.7 ms | ~18.5 ms |
| `-Onone` (Tinycast Dev) | ~20–36 ms | ~65–87 ms |

A trigram FTS (full-text search) query costs well under 1 ms. In an `-Onone` build, a keystroke
spends ~100 ms scoring on the main actor.

Clipboard rows have a kind: `text`, `image` or `file`. A file row stores its path in `text`, and
the `items_fts` triggers index that path. Image rows have no text. They match only through the
opt-in OCR (optical character recognition) path, which `ClipboardTextIndexer` fills and an
off-main SQLite query reads.

## Goals / Non-Goals

**Goals:**

- Remove per-keystroke folding. Each candidate's text is folded once and reused.
- Make the per-candidate cost of a non-match a single linear scan over integers.
- Keep scores, highlight positions, syntax and acceptance identical for every caller.
- Restrict a typed clipboard query to text entries, and keep image and file entries out of FTS
  retrieval, fuzzy scoring and OCR lookup.
- Keep clipboard search synchronous, with a measured budget, in both release and Tinycast Dev.

**Non-Goals:**

- Changing the fzf scoring constants, the medium acceptance bar or the 4,096-character scan cap.
- Making fuzzy matches reach history beyond the resident window. FTS still retrieves only literal
  words of three or more letters.
- Changing file search, which ranks with `fsearch`.
- Removing the upstream OCR subsystem. It stays in the source tree, gated off by fork hooks.

## Decisions

### 1. A folded candidate is a `ForkSearch.Text` value

`ForkSearch.Text` is a `Sendable` struct built once from a raw string, a scheme and camel humps.
It holds:

- `units: [UInt32]`, one code per folded character;
- `bonuses: [UInt8]`, the fzf bonus of each unit;
- `sources: [Int32]?`, the source `Character` offset of each unit, or `nil` when units map one to
  one onto source characters;
- `length`, the source text's `Character` count, which the launcher's tiers and suffix anchors use;
- `isASCII`, true for ASCII text without `\r`;
- `folded: String?`, the whole text's `FuzzyMatch.normalized` fold, stored only for non-ASCII text.
  Anchors on non-ASCII text read it instead of folding per search.

Preparation keeps the existing semantics exactly:

- **ASCII without `\r`.** Units are the lowercased bytes, bonuses come from `asciiClass`, and
  `sources` is `nil`. This preparation never splits graphemes.
- **Any other text.** Preparation walks `Character`s once. It folds each one as the general path
  does today, and gives the second and later units of an expansion `bonusConsecutive`.

A unit code is the folded `Character`'s single Unicode scalar after NFC (canonical composition).
A `Character` that remains several scalars after NFC gets a code from a process-wide intern table
above `0x110000`, keyed by its NFC string and guarded by a `Mutex`. Query terms encode through the
same function, so `Character` equality and unit equality agree.

Alternatives considered:

- *Cache `[Character]`.* This preserves equality trivially, but `Character` comparison costs a
  string comparison per step.
- *Scan folded UTF-8 bytes.* Byte offsets do not map onto `Character` offsets, so highlights would
  need a second mapping pass. A multi-byte folded letter would also break run bonuses.
- *Fold the whole string with one `FuzzyMatch.normalized` call.* This measured 9 ms for the
  non-ASCII set and would still run on every keystroke without a cache.

### 2. A query compiles once per search into `ForkSearch.Query`

`ForkSearch.Query` holds the parsed `Term`s with their unit codes, the positive terms, and each
positive term's self-match score. `terms(_:profile:)` remains the parser. `clipboardScore`,
`match`, `launcherScore`, `tiered` and the File Navigator filter take a `Query` instead of
re-parsing the string per candidate. String-taking entry points stay as thin conveniences for
single calls in tests.

### 3. The scorer works on units and rejects before it allocates

`ForkFzf.match(term:in:exact:)` takes unit codes and a `ForkSearch.Text`. The order is fixed:

1. A subsequence check over `units` rejects a non-match. It allocates nothing.
2. `exactMatch` or `align` runs over `units` and `bonuses`.
3. `sources` maps positions back to `Character` offsets.

`align` runs only between the first occurrence of the term's first letter and the last occurrence
of its last letter. Within that window it visits only the columns where each row's letter occurs,
because no other column can hold a finite score. Ties still resolve to the first maximal column.

The fork fold is `FuzzyMatch.normalized` with emoji skin-tone modifiers and emoji variation
selectors removed, so "👍" matches "👍🏽" and "❤" matches "❤️". Literal checks past the scan cap use
the same fold instead of Foundation's case- and diacritic-insensitive search. The fuzzy scorer
already folded width, so this also makes half-width and full-width kana match past the cap.

Prefix and suffix anchors still judge the folded whole text. ASCII text compares `units` directly,
because its fold is its lowercase. Non-ASCII text compares against `folded`. Neither path runs
`FuzzyMatch.normalized` per candidate.

The existing `ForkFzf.match(_:in:exact:humps:scheme:)` keeps its signature. It prepares a
`ForkSearch.Text` and calls the unit scorer, so it becomes the single implementation behind both
entry points.

### 4. The clipboard caches prepared heads per item

`ForkSearch.ClipboardText` pairs an item's raw text with two prepared `Text` values. `head` covers
the first 4,096 characters. `whole` covers the entire text, and for an uncapped item it is the same
value as `head`. Literal checks past the head read `whole`: ASCII words byte-scan the raw text, and
non-ASCII words search `whole.units` contiguously.

`ClipboardStore` owns a `[UUID: ForkSearch.ClipboardText]` cache. An item's text never changes
after capture, so the UUID is a sufficient key. The cache has these rules:

- A lookup prepares a missing entry and stores it.
- When `items` changes, the cache drops entries whose IDs are no longer resident.
- FTS hits outside the resident window are cached too, up to `searchLimit` extra entries. Those
  extra entries are evicted first.

Alternative considered: *move clipboard search off the main actor.* A detached task with
stale-result validation would hide the cost but not remove it. With the cache, a keystroke costs a
linear scan of resident units. That cost fits the budget in decision 6, so the search stays
synchronous, as the project's concurrency posture prefers.

### 5. A typed clipboard query searches text entries only

All of the following are `// FORK: search` hooks:

- **FTS:** `searchStmt` joins `items` and adds `AND kind = 'text'`, so file paths in `items_fts`
  are never retrieved.
- **Resident items and pins:** they pass through `kind == .text` before the scorer sees them.
- **OCR:** `updateTextSearch` returns at once, so the off-main OCR query never starts.
- **Indexer:** `AppCore.applyClipboardTextSearch` treats the feature as disabled, so no
  `ClipboardTextIndexer` is created.
- **Settings:** `ClipboardSettingsView` hides the "Search text in images and PDFs" toggle, and
  `SettingsSearchCatalog` hides its entry.

An empty query still lists every kind, and the type filter still selects images and files. With
a typed query, the Images and Files filters show an empty list. Their empty message stays the
upstream string.

Copy Text keeps spawning the helper on demand, because it never depended on the switch.

Alternative considered: *keep OCR behind its switch.* The owner chose text-only search, so the
OCR query branch has no consumer.

### 6. Performance budgets are pinned by a harness

The new harness `Tests/fork-search-performance.swift` builds a synthetic corpus of 1,000 items.
Ten percent of the items are non-ASCII: emoji, accented prose, CJK and `\r\n` line endings. The
lengths follow the Dev history's spread, up to 15,000 characters. The harness times these queries:
1–2 letters, a long word, two words, a non-match and an anchored word. It uses a warm cache.
It builds with `-O`, and a warm search takes at most 5 ms, under a 120 Hz frame of 8.3 ms. The
corpus is about twice as text-heavy as the Dev history, where a warm search takes 0.1–1 ms.

The harness reports both a warm and a cold (uncached) time. A parity section in
`fork-search-test` compares the old and new scorers on the same corpus. Both must give the same
scores and positions for every query and item.

### 7. The Debug build is optimised

The `Tinycast` target's Debug configuration sets `SWIFT_OPTIMIZATION_LEVEL` to `-O`. Tinycast Dev
is the daily-driver channel, so it must match release speed. Measured on the Dev history, a warm
search takes 0.3–1.7 ms with `-O` and 20–80 ms with `-Onone`. The same scan loop runs about 140×
slower at `-Onone`, and `@_optimize(speed)` has no effect in an `-Onone` build.

Alternatives considered:

- *Keep `-Onone` and accept a slower Dev.* Search would remain visibly sluggish in Dev.
- *Move `Fork/Search` into a framework target that always builds with `-O`.* This adds a target,
  a module boundary and test-runner changes for one feature.

### 8. Launcher and other callers adopt compiled queries

- `LauncherMatch` compiles the query once per keystroke and passes it to every entry.
- `AppIndex` entries carry a prepared `ForkSearch.Text` built when the index loads, so launcher
  scoring also skips folding.
- Snippets, Quicklinks and File Navigator compile once and prepare per row. Their lists are small,
  so they do not cache.

## Risks / Trade-offs

- [Parity regressions in edge folds, such as ß → ss, ligatures, `\r\n` or combining marks] →
  The parity harness runs the retired scorer, kept as a test-only copy, against the new one on the
  mixed corpus and on the existing fold fixtures.
- [Cache memory for long items] → Each cached head holds at most 4,096 units, ~37 KB. A full
  window of 1,000 maximum-length items is ~37 MB. The Dev history uses ~1.5 MB. If the harness
  reports more than 8 MB on its corpus, `bonuses` and `sources` move to on-demand computation for
  survivors only.
- [The intern table grows without bound] → Only multi-scalar folded graphemes such as flags, ZWJ
  emoji and some Indic clusters enter it. Their number is bounded by distinct graphemes the user
  has copied.
- [Removing OCR from typed search surprises an upgrading user] → The switch is hidden, not reset.
  Turning fork search off restores upstream behaviour, and `docs/fork.md` records the choice.
- [An optimised Debug build is harder to debug, and incremental builds are slower] → A developer
  who needs a debugger session sets `SWIFT_OPTIMIZATION_LEVEL` to `-Onone` locally for that
  session.
