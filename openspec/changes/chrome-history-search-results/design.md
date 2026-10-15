## Context

Search Google (`Tinycast/Fork/ChromeSearch/`) builds its rows in `GoogleSearchRow.rows(...)`: the typed
row, local query history, then Google's suggestions. `ChromeSearchSession` owns the typed query and the
suggestions task; `ChromeSearchCoordinator` hands URLs to Chrome through `NSWorkspace`. Tinycast never
scripts Chrome, which rules out the omnibox and CDP (port 9222 is the agents' `cdp-mux`, not a Tinycast
dependency, and Chrome 136+ ignores the debug port on the default profile).

Chrome keeps visited pages in `<user-data-dir>/<profile>/History`, a SQLite file locked while Chrome
runs. The `urls` table holds `url`, `title`, `visit_count`, `last_visit_time` (WebKit epoch,
microseconds since 1601). This machine has a single profile, "Profile 1", named by `last_used` in
`Local State`. The asset `BrandGitHub` already exists in `Assets.xcassets`.

## Goals / Non-Goals

**Goals:**
- Visited pages from Chrome's last-used profile appear as results while typing, every keystroke, with the
  same latency feel as the existing rows.
- GitHub results carry the GitHub icon, from history and from Google's website suggestions alike.
- Chrome is only read from disk and handed URLs, never scripted.

**Non-Goals:**
- Bookmarks, open tabs, Chrome's on-device suggestions or other profiles (bookmarks are a later change).
- Persisting, syncing or backing up anything from Chrome history.
- Other brand icons; the mapping is built so a host can be added, but only GitHub ships.
- Other browsers.

## Decisions

**Copy, then read.** The service copies `History` (plus `History-wal` if present) into a private temp
directory and opens the copy `SQLITE_OPEN_READONLY`. Alternatives: open the original with
`immutable=1` (returns stale or torn pages while Chrome writes) or `nolock` (same risk). A 71 MB copy is
cheap on APFS (clone), and it is refreshed at most once per screen visit, and again only when the
source's modification date changed, so typing never copies.

**Query in SQL, rank in the pure Model.** The service runs one `LIKE` query over `url` and `title` for
the typed words and returns the top ~200 candidates; `ChromeHistoryRanking` (Model, no AppKit, clock
injected) scores and cuts them to ~5. Score: every word must match; title or host prefix beats
substring; then `log(visit_count)` and recency decay. Alternative: rank in SQL — rejected because the
rule is the testable part and must live in a harness-compiled Model file.

**Off-main, cancellable, stale-safe.** The query is a `@concurrent` async function, so SQLite never runs
on the main actor. `ChromeSearchSession` starts it beside the suggestion task on every `queryChanged`,
cancels the previous one, and applies a result only if it still answers the query in the field, the same
guard `applySuggestions` has. The previous history rows stay until the next set lands. The SQLite
handle is opened per query batch and closed before returning; no long-lived handle.

**No new owner of persistent state.** `ChromeHistoryReader` is a plain service constructed by `AppCore`
beside `GoogleSearchHistoryStore` and injected into the session. It holds no cache of rows, only the
copy's modification-date check. The temp copy is deleted when the screen closes and on app exit, so
history never lingers on disk outside Chrome's own file.

**Profile from `Local State`.** `ChromeProfileLocator` (Model, filesystem injected) decodes
`profile.last_used` from `Local State` and returns the profile directory. A missing file, an unknown
profile or an unreadable database yields no history rows and no error UI, matching how suggestions fail.
Alternative: hardcode `Default` — wrong on this machine.

**Rows.** `GoogleSearchRow` gains `.page(title:url:detail:)`. Order: typed, local query history, history
pages, Google suggestions; a page whose URL equals a website suggestion's is shown once, as the history
page. With an empty field the screen still lists only recent query history, because browsing history is
not a "recent" list. ↵ opens the URL in Chrome and records the title in the query history, like a
website suggestion; ⌘↵ opens Google's results page for the host; ⇥ puts the host in the field.

**Host icon in the row view.** `ChromeSearchHostIcon` (Model, pure) maps a URL host to an asset name:
`github.com` and any subdomain give `BrandGitHub`, everything else gives nil and the existing globe.
`ChromeSearchRowView` renders the asset as a template image at `resultRowIcon` size, the same way
`NotchBarView` renders brand assets. Alternative: fetch favicons from Chrome's `Favicons` database —
rejected as a second SQLite file, bitmap scaling, and a visual mismatch for the rest of the rows.

## Risks / Trade-offs

- [Chrome history is sensitive] → read on demand, in memory only, never logged, never in backups or
  `settings.json`, temp copy removed on close; documented in the feature doc's invariants.
- [Copy lags Chrome's last writes] → a freshly visited page may be missing until Chrome flushes the WAL;
  copying `History-wal` with the database closes most of the gap.
- [Chrome's schema changes] → the query touches only `urls` columns that have been stable for years; a
  failed query yields no history rows.
- [A 71 MB copy on each screen open] → APFS clone makes it near-instant; skipped when the modification
  date is unchanged.
- [LIKE is a full scan] → ~100k rows scan in a few ms; the cap of 200 candidates bounds ranking work. If
  it ever stutters, add an in-memory index built once per screen visit.
- [Depends on the unarchived `chrome-google-search` change] → this change builds on its rows and
  coordinator and lands after it.

## Open Questions

- Should history pages rank above or below Google's query suggestions? The design puts them above, as
  Chrome's omnibox does for strong matches; confirm after trying it.
- Is a profile picker needed, or is `last_used` enough? One profile exists here, so deferred.
