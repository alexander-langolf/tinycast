## Why

Clipboard search feels sluggish because the shared fzf scorer re-derives every candidate's folded
text on every keystroke. Non-ASCII text takes a per-`Character` path that splits graphemes, folds
each one and allocates arrays before it can reject a non-match. On a 783-item history measured on
2026-10-17, the 77 non-ASCII items cost ~18.5 ms of the ~20 ms each keystroke spends scoring, and
this work runs on the main actor. Every list surface shares this scorer, so the fix belongs in the
shared layer rather than in the clipboard alone.

## What Changes

- The shared scorer compiles a query once per search, not once per candidate.
- Each candidate's folded form is prepared once and reused across keystrokes. The prepared form
  holds the folded bytes, their source offsets and the fzf bonuses.
- Scoring runs on bytes for all text. A subsequence check rejects a non-match before the scorer
  computes bonuses or alignment, and the alignment reuses its buffers.
- Scores, highlight positions and the fzf syntax (`'exact`, `^prefix`, `suffix$`, `!exclude`)
  stay identical. Existing harness expectations do not change.
- A typed clipboard query searches text entries only: plain text, links, colours and email
  addresses. Image and file entries never appear in typed results. The type filter with an empty
  query still lists them.
- **BREAKING:** With fork search on, a typed clipboard query no longer consults recognized image and
  PDF text. Settings hide the "Search text in images and PDFs" switch, and `AppCore` creates no
  background text indexer. On-demand Copy Text extraction is unchanged.
- The clipboard caches each resident item's prepared text, so a keystroke only scans and scores.
  Search stays synchronous on the main actor.
- The `Tinycast` target's Debug configuration builds with `-O`, so Tinycast Dev searches as fast as
  release.
- A performance harness pins the time a search takes on a large corpus of mixed ASCII and
  non-ASCII text.
- Ripgrep plays no part. It has no fuzzy scoring, the history lives in SQLite rather than files, and
  starting a process costs more than the whole per-keystroke budget.

## Capabilities

### New Capabilities

- `fuzzy-matching`: the shared fzf scorer's contract. It covers query compilation, prepared
  candidate text, byte-level scoring, score and position parity, and per-search time budgets.
- `clipboard-search`: what a typed clipboard query searches and how it ranks. It covers the
  text-only scope, FTS (full-text search) retrieval, ranking and the prepared-text cache.

### Modified Capabilities

None. The `search` spec already states that clipboard, launcher, snippet and navigator matching use
the shared fork scorer, and that statement stays true.

## Impact

- `Tinycast/Fork/Search/ForkFzf.swift` and `ForkSearch.swift`: compiled query, prepared text and
  byte scorer.
- `Tinycast/Features/Clipboard/Model/ClipboardStore.swift`: text-only scope, prepared-text cache and
  removal of the OCR query branch behind `// FORK: search` hooks.
- `Tinycast/App/AppCore.swift` and clipboard settings: the indexer and its switch are gated off when
  fork search is on.
- Callers of the shared scorer: launcher (`LauncherMatch`, `SearchRelevance`), Snippets,
  Quicklinks and File Navigator name filters.
- `project.yml` and the generated `Tinycast.xcodeproj`: optimised Debug configuration.
- `Tests/fork-search-test.swift`, `Tests/clipboard-search-test.swift`, and a new
  `Tests/fork-search-performance.swift` registered in `Scripts/run-tests.sh`.
- `docs/fork.md` (Search section) and `docs/features/clipboard.md`.
