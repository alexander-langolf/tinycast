# Search

## Purpose

Describe the search feature area implemented in Tinycast at commit `9f065751`, inspected on
2026-10-12. This is a baseline of current behavior, not a proposal for new functionality.

The area covers launcher entry matching, Search Files, the `fsearch` file client, and File Navigator's
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

File search SHALL use `fsearch` as its only candidate engine for nonblank queries, as specified by
`fsearch-file-search`. There SHALL be no engine preference. Search Files SHALL show
"File search is unavailable" when `fsearch` cannot be found or started, and SHALL NOT use Spotlight or
ripgrep as a fallback.

#### Scenario: fsearch is unavailable
- **WHEN** no `fsearch` executable is found or the child cannot start
- **THEN** file queries fail visibly and no other engine is consulted

#### Scenario: Ready daemon
- **WHEN** a nonblank query is entered and the daemon answers
- **THEN** the answer's hits become the candidates for that request

#### Scenario: Blank file query
- **WHEN** Search Files receives an empty query
- **THEN** it requests recent files through the existing Spotlight service without a typing debounce

### Requirement: File search supports extended terms and engine-specific ranking

Production file matching SHALL pass the typed query to fsearch and SHALL use fsearch's own syntax and
scores. Whitespace-separated terms, exact, prefix, suffix and negated terms SHALL mean what fsearch
defines. Tinycast SHALL NOT re-rank fsearch results. Launcher, clipboard, snippet and navigator
in-folder name matching SHALL continue to use the shared fork scorer.

#### Scenario: Multiple terms
- **WHEN** a file query contains several space-separated terms
- **THEN** the same string is sent to fsearch and its ordering is preserved

#### Scenario: In-folder navigator filter
- **WHEN** the user filters rows inside a listed folder
- **THEN** names are scored by the shared fork scorer, not by fsearch

### Requirement: File results remain bounded and filterable

Search Files SHALL expose All Types, Folders, Documents, Images, Audio, Videos and Archives filters
and debounce nonblank input by 120 milliseconds, returning at most 200 rows. Rows removed by local
filtering SHALL be removed before the cap. A full response reduced below 200 rows by local filtering
SHALL be re-queried once with a larger limit. Application bundles SHALL be excluded from file results.

#### Scenario: Type filter changes
- **WHEN** the user changes the type filter
- **THEN** the session reruns the same query with that filter as part of request identity

#### Scenario: Short page after filtering
- **WHEN** local filtering leaves a full response with fewer than 200 rows
- **THEN** one larger request is made and its filtered rows are published

### Requirement: File Navigator distinguishes words from paths

File Navigator SHALL interpret ordinary words as global file search and path-shaped input as
folder browsing with a filename filter. Folder filtering SHALL score row names; it SHALL NOT reuse
fsearch's whole-path ordering. Clearing the entire navigator input SHALL return to the launcher.

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
of 50,000, delivering batches of 500 rows. It SHALL use ripgrep when an executable is available and
otherwise the Swift walker; the removal of the file-search engine preference SHALL NOT change this.
Recursive scans SHALL include dot entries independently of the home hidden-search preference and
direct-listing reveal toggle, while enforcing recursive exclusions and package boundaries.

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
| fsearch client, query and protocol | `FSearchClient`, `FSearchQuery`, `FSearchProtocol` |
| Candidate routing and stale-answer handling | `Tinycast/Features/FileSearch/Service/FileSearchSession.swift` |
| Blank-query Spotlight recents and filters | `Tinycast/Features/FileSearch/Service/FileSearchService.swift`, `Tinycast/Features/FileSearch/Model/FileSearchQuery.swift`, `FileSearchFilter.swift` |
| Navigator state and integration | `Tinycast/Features/FileNavigator/Model/FileNavigatorState.swift`, `FileNavigatorPath.swift`, `Tinycast/Features/FileNavigator/UI/FileNavigatorCoordinator.swift` |
| Direct and recursive enumeration | `Tinycast/Features/FileNavigator/Service/DirectoryLister.swift`, `SubtreeWalker.swift`, `RipgrepSubtreeScanner.swift` |

## Evidence and current limitations

This baseline was checked against source, not a running app. Relevant existing harnesses include
`Tests/fork-search-test.swift`, `file-search-test.swift`, `file-search-session-test.swift`,
`fuzz-test.swift`, and `file-navigator-test.swift`.
Their existence is not evidence that every scenario above is covered
or passing; no harnesses, build or runtime checks were run for this exploration artifact.

- Search here means entry/name/path search, not file-content search.
- Nonblank file candidates, ordering and coverage come from the `fsearch` daemon (see
  `fsearch-file-search`); Tinycast keeps no home index and applies no fallback engine.
- The subtree caps differ: ripgrep counts emitted file and derived-directory rows, while the Swift
  walker counts visited entries. These are bounded scans, not exhaustive filesystem search.
- Navigator name filters accept negative-only queries. The Swift recursive fallback does not read
  `.gitignore`, unlike ripgrep.
- Hidden behavior is currently split across fsearch hit filtering, direct-listing reveal and recursive
  scanning. This records that split without deciding whether a future change should unify it.

Related documentation: `docs/features/launcher.md`, `docs/features/file-search.md`, and
`docs/features/file-navigator.md`.
