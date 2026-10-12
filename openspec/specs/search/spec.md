# Search

## Purpose

Describe the search feature area implemented in Tinycast at commit `9f065751`, inspected on
2026-10-12. This is a baseline of current behavior, not a proposal for new functionality.

The area covers launcher entry matching, Search Files, the ripgrep file index, and File Navigator's
global, folder and subtree searches. Clipboard, menu, emoji, notes, settings and extension searches
are adjacent consumers with their own behavior; this baseline does not specify those surfaces.

## Requirements

### Requirement: Launcher search retains its own ranking policy

The launcher SHALL match indexed entries using their search profiles and retain launcher-specific
alias, learned-query, usage and sensitivity signals. It SHALL NOT use file-path ranking as its
complete ordering policy. Production fork matching SHALL use the shared fork scorer where wired
through `LauncherMatch`, while retaining typed and transliterated query forms.

#### Scenario: Nonblank launcher query
- **WHEN** the user enters words in the launcher
- **THEN** matching entries are ordered by `LauncherOrder` with the configured search sensitivity
- **AND** entry profiles, aliases and learned ranking remain inputs to that ordering

#### Scenario: Blank launcher query
- **WHEN** the launcher query is blank
- **THEN** the launcher uses its suggestions and usage-based listing behavior rather than file recents

### Requirement: File search selects an available candidate engine

File search SHALL support Spotlight and ripgrep. An unset engine preference SHALL select ripgrep
when an executable is available, otherwise Spotlight. Executable discovery SHALL check
`/opt/homebrew/bin/rg`, `/usr/local/bin/rg`, then PATH. A scope outside the supported home index
SHALL use Spotlight for that query.

#### Scenario: Ripgrep is unavailable
- **WHEN** ripgrep is selected but no executable is found
- **THEN** file queries use the Spotlight path

#### Scenario: Ready home index
- **WHEN** a nonblank query has a supported policy and a ready ripgrep index
- **THEN** indexed candidates replace both Spotlight candidate passes for that request

#### Scenario: Blank file query
- **WHEN** Search Files receives an empty query
- **THEN** it requests recent files through the existing Spotlight service without a typing debounce

### Requirement: File search supports extended terms and engine-specific ranking

Production fork file matching SHALL support whitespace-separated AND terms, fuzzy terms,
contiguous `'exact` terms, `^prefix`, `suffix$`, and `!negation`. The ripgrep query SHALL score the
whole home-relative path using the fzf path scheme, without `~/` or the internal directory marker.
Spotlight SHALL retain its separate filename/folder ranking semantics.

#### Scenario: Terms span parent and filename
- **WHEN** a ripgrep query contains multiple positive terms
- **THEN** every term must match the relative path and their scores add
- **AND** a matching negated term rejects that path

#### Scenario: Equal path scores
- **WHEN** indexed candidates have equal scores
- **THEN** ties prefer a match in the final path segment, an earlier start in that segment,
  a shorter relative path, then incoming index order

#### Scenario: Undotted query matches a dot entry
- **WHEN** a candidate has a leading filename dot and the term is undotted and unanchored
- **THEN** the scorer treats that one leading dot as neutral
- **AND** explicit dotted terms and prefix anchors retain literal spelling

### Requirement: File results remain bounded and filterable

Search Files SHALL expose All Types, Folders, Documents, Images, Audio, Videos and Archives filters
and debounce nonblank input by 120 milliseconds, returning at most 200 ranked rows.
Indexed search SHALL initially retain 200 candidate paths and
retry with up to 1,000 candidates when metadata or filtering leaves a full initial shortlist short
of 200 results. It SHALL exclude application bundles from file results.

#### Scenario: Type filter changes
- **WHEN** the user changes the type filter
- **THEN** the session reruns the same query with that filter as part of request identity

### Requirement: Home indexing honors its current visibility and exclusion policy

The home index SHALL honor the `Search hidden files` preference, which defaults to false and is
mirrored as `fileNavigator.searchHidden`. It SHALL retain compiled and user ignore patterns,
ripgrep ignore rules, fixed home Library and Trash exclusions, and package exclusions. It SHALL
derive directory candidates from emitted files rather than independently enumerate every folder.

#### Scenario: Hidden home search enabled
- **WHEN** Search hidden files is enabled
- **THEN** the next home index scan includes `--hidden`
- **AND** `.git/` and other exclusions remain in force

#### Scenario: Empty directory
- **WHEN** a directory has no emitted descendant file
- **THEN** the ripgrep home index does not derive a result for it

### Requirement: Shared index lifecycle is independent of individual queries

AppCore SHALL own one ripgrep index shared by Search Files and navigator global search. Palette
opening SHALL be able to warm an absent index. First indexed use SHALL also prepare it. After use,
palette opening SHALL refresh an index older than 120 seconds. Refresh SHALL serve the previous
snapshot until replacement; changing engine, ignore patterns or hidden search SHALL invalidate it.

#### Scenario: Index is still building
- **WHEN** a supported query arrives before the index is ready
- **THEN** the service may publish Spotlight matches before publishing the indexed answer
- **AND** an empty provisional result is withheld while an index answer is pending

#### Scenario: Query is superseded
- **WHEN** input or filter changes while work is outstanding
- **THEN** stale work cannot publish into the newer request
- **AND** query cancellation does not cancel the shared index build

#### Scenario: Refresh fails
- **WHEN** a replacement index fails to load
- **THEN** the previous snapshot remains available

### Requirement: File Navigator distinguishes words from paths

File Navigator SHALL interpret ordinary words as global file search and path-shaped input as
folder browsing with a filename filter. Folder filtering SHALL score row names; it SHALL NOT reuse
the home index's whole-path ordering. Clearing the entire navigator input SHALL return to the launcher.

#### Scenario: Launcher path entry
- **WHEN** the launcher receives `~`, `~/…`, or `/…`
- **THEN** it routes into File Navigator
- **AND** bare `~` and bare `/` both initialize the navigator at `~/`

#### Scenario: Folder navigation
- **WHEN** the user presses Enter on a folder in the navigator
- **THEN** the navigator enters that folder
- **AND** Tab completes the selected row and Shift-Tab navigates toward the parent

#### Scenario: Search Files folder activation
- **WHEN** the user invokes the default action on a Search Files folder result
- **THEN** Tinycast opens that folder in File Navigator

### Requirement: Subtree search remains distinct from home search

Navigator subtree search SHALL scan the current folder with a depth limit of 8 and an entry cap
of 50,000, delivering batches of 500 rows. It SHALL use ripgrep when available for the selected
engine and otherwise the Swift walker. Recursive scans SHALL include dot entries independently
of the home hidden-search preference and direct-listing reveal toggle, while enforcing recursive
exclusions and package boundaries.

#### Scenario: Subtree scan requested
- **WHEN** the user toggles Command-F in folder mode
- **THEN** the navigator switches between the direct listing and recursive candidates
- **AND** entered filter terms rank candidate names

#### Scenario: Subtree process fails
- **WHEN** a ripgrep subtree process fails without cancellation
- **THEN** partial rows are cleared and the Swift walker is used
- **AND** cancellation itself does not trigger fallback

## Implementation map

Paths below are relative to the repository root.

| Responsibility | Current source |
| --- | --- |
| Ownership and settings changes | `Tinycast/App/AppCore.swift` |
| Launcher profiles and ordering | `Tinycast/Features/Launcher/Service/AppIndex.swift`, `Tinycast/Features/Launcher/Model/LauncherOrder.swift`, `LauncherMatch.swift` |
| Shared syntax and scoring | `Tinycast/Fork/Search/ForkSearch.swift`, `ForkFzf.swift` |
| Engine, index, policy and query | `Tinycast/Fork/Search/ForkFileSearchEngine.swift`, `ForkRipgrepIndex.swift`, `ForkRipgrepPolicy.swift`, `ForkRipgrepQuery.swift` |
| Candidate routing and late publication | `Tinycast/Fork/Search/ForkFileSearchService.swift`, `Tinycast/Features/FileSearch/Service/FileSearchSession.swift` |
| Spotlight retrieval and filters | `Tinycast/Features/FileSearch/Service/FileSearchService.swift`, `Tinycast/Features/FileSearch/Model/FileSearchQuery.swift`, `FileSearchFilter.swift` |
| Navigator state and integration | `Tinycast/Features/FileNavigator/Model/FileNavigatorState.swift`, `FileNavigatorPath.swift`, `Tinycast/Features/FileNavigator/UI/FileNavigatorCoordinator.swift` |
| Direct and recursive enumeration | `Tinycast/Features/FileNavigator/Service/DirectoryLister.swift`, `SubtreeWalker.swift`, `RipgrepSubtreeScanner.swift` |

## Evidence and current limitations

This baseline was checked against source, not a running app. Relevant existing harnesses include
`Tests/fork-search-test.swift`, `file-search-test.swift`, `file-search-session-test.swift`,
`ripgrep-ranking-test.swift`, `fuzz-test.swift`, and `file-navigator-test.swift`.
Their existence is not evidence that every scenario above is covered
or passing; no harnesses, build or runtime checks were run for this exploration artifact.

- Search here means entry/name/path search, not file-content search.
- The ripgrep home index is in memory, omits empty directories and excluded trees, and does not
  follow symlinks. Spotlight has different candidate coverage and ranking, so engine changes can
  change results. No performance target is asserted by this baseline.
- The subtree caps differ: ripgrep counts emitted file and derived-directory rows, while the Swift
  walker counts visited entries. These are bounded scans, not exhaustive filesystem search.
- Navigator name filters accept negative-only queries; global indexed matching requires a positive
  term. The Swift recursive fallback does not read `.gitignore`, unlike ripgrep.
- `docs/features/ripgrep-search.md` still describes unconditional hidden home indexing and indexing
  starting only on the first nonblank search. Current settings and `ForkRipgrepIndex` supersede
  those descriptions: hidden home search defaults off and an absent index can warm on palette open.
- Hidden behavior is currently split across home indexing, direct-listing reveal and recursive
  scanning. This records that split without deciding whether a future change should unify it.

Related documentation: `docs/features/launcher.md`, `docs/features/file-search.md`,
`docs/features/file-navigator.md`, and `docs/features/ripgrep-search.md`.
