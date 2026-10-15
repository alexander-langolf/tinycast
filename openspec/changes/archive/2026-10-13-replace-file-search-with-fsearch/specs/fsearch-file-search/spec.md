## ADDED Requirements

### Requirement: fsearch is the sole file candidate source
Search Files and File Navigator global (word) search SHALL obtain candidates only from the `fsearch`
daemon through one long-lived `fsearch stdio` child. They SHALL NOT query Spotlight or build a Tinycast
file index for nonblank queries.

#### Scenario: Nonblank file query
- **WHEN** the user enters a nonblank query in Search Files
- **THEN** one JSON-line request carrying the query and a unique `id` is written to the child
- **AND** the rows published come from the `hits` of the response with that `id`

#### Scenario: Navigator global search
- **WHEN** the navigator input is interpreted as words rather than a path
- **THEN** its candidates come from the same client and the same ordering as Search Files

### Requirement: The fsearch child is started lazily and owned by the app
The client SHALL locate `fsearch` at `~/.local/bin/fsearch`, then on `PATH`, without a shell. It SHALL
start the child on the first nonblank query, never at launch, and SHALL terminate it on app exit. A
child that exits mid-session SHALL be relaunched once on the next request.

#### Scenario: No query issued
- **WHEN** Tinycast launches and no file query has been made
- **THEN** no `fsearch` process has been started by Tinycast

#### Scenario: Child dies mid-session
- **WHEN** the child exits and the user types another query
- **THEN** the client relaunches it once and sends the request
- **AND** a second failure leaves the session in the failed state

### Requirement: Responses are matched by id and stale answers never publish
Each request SHALL carry a monotonically increasing `id`. A response SHALL be applied only if its `id`
belongs to the session's current revision and its request and filter still equal the published request.

#### Scenario: Query superseded while in flight
- **WHEN** a newer query is issued before an older response arrives
- **THEN** the older response is discarded and cannot replace the newer rows

#### Scenario: Out-of-order responses
- **WHEN** responses for ids 8 and 9 arrive in the order 9, 8
- **THEN** only the response for the current request is published

### Requirement: fsearch order is the ranking
Hits SHALL be published in the order fsearch returns them. Tinycast SHALL NOT re-score them. It SHALL
only drop rows, in this order: application bundles, hidden path components unless hidden search is
enabled, ignore-list exclusions, rows rejected by the type filter. It SHALL then publish at most 200.

#### Scenario: Application bundle among hits
- **WHEN** a hit is an application bundle or lies inside one
- **THEN** it is not published

#### Scenario: Ties and order
- **WHEN** two hits have equal scores
- **THEN** they keep the relative order fsearch returned

### Requirement: The type filter is pushed; scopes and ignore patterns are enforced locally
The type filter SHALL belong to the request and SHALL be sent as fsearch's `type:` word where fsearch has
one, so changing it re-runs the same words. Folders SHALL be answered from each hit's kind. Configured
scopes and ignore patterns SHALL be enforced locally on the returned paths, and the query text SHALL NOT
carry a path term for a scope. An empty scope list SHALL return no results rather than searching everywhere.
Paths under `~/Library` SHALL be admitted only through `Library/CloudStorage`, iCloud Drive, or a scope the
user named.

#### Scenario: Type filter changes
- **WHEN** the user changes the filter from All Types to Images
- **THEN** the same words are re-queried with `type:image`
- **AND** the session keys its de-duplication on query and filter together

#### Scenario: Out-of-scope hit
- **WHEN** fsearch returns a path outside every configured scope
- **THEN** it is dropped locally before the 200-row cap is applied

#### Scenario: Post-filter leaves a full page short
- **WHEN** a full response is reduced below 200 rows by local filtering
- **THEN** the client re-queries once with a larger limit and publishes the result

#### Scenario: Empty scope list
- **WHEN** the configured scope list is empty
- **THEN** no request is sent and the screen shows no results

### Requirement: Unavailability is visible and has no fallback
If `fsearch` cannot be found, started or decoded, Search Files SHALL show "File search is unavailable"
inline and SHALL NOT fall back to Spotlight or any other engine. A response with `ok: false` or a line
that cannot be decoded SHALL fail that request and not the app.

#### Scenario: Executable missing
- **WHEN** neither `~/.local/bin/fsearch` nor a `PATH` entry contains an executable `fsearch`
- **THEN** a nonblank query leaves the session failed
- **AND** the screen reads "File search is unavailable"

#### Scenario: Malformed response line
- **WHEN** the child writes a line that is not a valid response
- **THEN** that request fails and the next request is still sent

### Requirement: Typing is debounced and the blank screen is separate
Nonblank input SHALL be debounced by 120 ms before a request is written. The blank-query Recently Used
list SHALL NOT go through fsearch in this change and SHALL keep its existing source and no-debounce
behavior.

#### Scenario: Fast typing
- **WHEN** the user types three characters within 120 ms of each other
- **THEN** one request is written for the final text

#### Scenario: Blank screen
- **WHEN** Search Files opens with an empty query
- **THEN** Recently Used rows are listed as before, without an fsearch request

### Requirement: Search requires no Tinycast file permission
Tinycast SHALL NOT request Full Disk Access or any file permission for file search. Coverage SHALL be
whatever the `fsearch` binary's own access provides, and File Navigator settings SHALL state when
fsearch reports no Full Disk Access.

#### Scenario: fsearch lacks Full Disk Access
- **WHEN** `fsearch status` reports `full_disk_access: false`
- **THEN** Tinycast shows no permission prompt
- **AND** the settings pane says results may be incomplete until the `fsearch` binary is granted access
