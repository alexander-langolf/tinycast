## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: Home indexing honors its current visibility and exclusion policy
**Reason**: Tinycast no longer builds a home index. fsearch owns coverage, freshness and its own
exclusions. The `Search hidden files` preference now filters fsearch hits locally.
**Migration**: Use fsearch's index and the existing ignore patterns and `Search hidden files`
preference. No stored setting needs converting.

### Requirement: Shared index lifecycle is independent of individual queries
**Reason**: AppCore no longer owns a ripgrep index, so there is nothing to warm, refresh or invalidate.
The fsearch child is started lazily by the client and owned by the app for its lifetime.
**Migration**: Replaced by the process-lifecycle and stale-answer requirements in `fsearch-file-search`.
