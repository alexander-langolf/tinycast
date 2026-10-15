## 1. Model (pure, Foundation only)

- [x] 1.1 `ChromeHistoryEntry` (title, url, visitCount, lastVisit; `Sendable`, `Hashable`) and the
  WebKit-epoch conversion (microseconds since 1601) to `Date`.
- [x] 1.2 `ChromeProfileLocator`: decode `profile.last_used` from `Local State` JSON and return the
  profile directory, with the filesystem injected. A missing file, bad JSON or an unknown profile
  returns nil.
- [x] 1.3 `ChromeHistoryRanking`: split the query into words, require every word to match title or URL
  (case-insensitive), score title/host prefix above substring, then `log(visitCount)` and recency decay
  from an injected clock. Cut to 5, deterministically.
- [x] 1.4 `ChromeSearchHostIcon`: map a URL host to an asset name. `github.com` and subdomains give
  `BrandGitHub`; lookalikes (`notgithub.com`, `github.com.example.org`) and everything else give nil.
- [x] 1.5 `GoogleSearchRow.page(title:url:detail:)`. Extend `rows(...)` to order typed, query history,
  history pages, suggestions, drop a website suggestion whose URL equals a page's, and list no pages for
  an empty query.
- [x] 1.6 Confirm the Model folder imports neither AppKit nor SwiftUI (the AGENTS.md grep).

## 2. Service

- [x] 2.1 `ChromeHistoryReader`: copy `History` and `History-wal` into a private temp directory, open
  the copy `SQLITE_OPEN_READONLY`, and skip the copy while the source's modification date is unchanged.
  The profile comes from `ChromeProfileLocator`.
- [x] 2.2 One `LIKE` query over `url` and `title` for the typed words, returning up to 200 candidates,
  as a `@concurrent` async function. The handle is opened per batch and closed before returning.
- [x] 2.3 Every failure (no Chrome, no `Local State`, unreadable `History`, failed query) yields an
  empty result with no error UI and no logging of history content.
- [x] 2.4 Delete the temp copy when the screen closes and on app exit.
- [x] 2.5 Wire `ChromeHistoryReader` in `AppCore.start()` beside `GoogleSearchHistoryStore` and inject
  it into `ChromeSearchSession`.

## 3. Session and coordinator

- [x] 3.1 `ChromeSearchSession` starts the history query beside the suggestion task on every
  `queryChanged`, cancels the previous one, and applies a result only if it still answers the query in
  the field. Previous history rows stay until the next set lands.
- [x] 3.2 Make no history query for an empty or whitespace query, and cancel any in flight when the
  screen is left.
- [x] 3.3 Actions on a page row: ↵ opens the URL in Chrome as a new tab and records the title in the
  query history; ⌘↵ opens Google's results page for the host; ⇥ puts the host in the field and loads
  suggestions. Chrome stays unscripted.

## 4. UI

- [x] 4.1 Render `.page` rows in `ChromeSearchRows.swift` with title and host, falling back to the host
  when the title is empty.
- [x] 4.2 Show the `BrandGitHub` template image at `resultRowIcon` size, the way `NotchBarView` renders
  brand assets, for any row whose host maps to it, on page rows and website-suggestion rows alike.
  Everything else keeps the existing icon.

## 5. Tests

- [x] 5.1 Add `Tests/chrome-history-test.swift` covering profile location, ranking (every word, prefix
  over substring, visits, recency, determinism), host icon (GitHub, subdomain, lookalikes, others),
  row ordering and de-duplication, WebKit epoch conversion, and the reader against a fixture SQLite file
  (copy reuse, missing file, bad schema).
- [x] 5.2 Extend the session test for stale-result discard, previous rows kept while typing, and
  cancellation on leaving the screen.
- [x] 5.3 Register the harness in `Scripts/run-tests.sh` inside the `FORK: chrome-search` block.

## 6. Docs and verification

- [x] 6.1 Update `docs/features/chrome-google-search.md` invariants (history is local, in memory,
  copied and removed, Chrome never scripted) and `docs/fork.md`.
- [x] 6.2 Run `./Scripts/run-tests.sh`, build Debug with no new warnings, and run `./Scripts/lint.sh`.
- [x] 6.3 Run `xcodegen generate` if `project.yml` changed, and keep the project diff separate from the
  other uncommitted changes.
- [ ] 6.4 Native check in Tinycast Dev: typing a visited page shows it, ↵ opens it as a new tab, the
  GitHub icon shows, and no Chrome history is left in the temp directory after closing the screen.
