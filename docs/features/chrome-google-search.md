# Search Google

`Search Google` is a launcher command and a fallback. The command opens a screen (`.googleSearch`)
with an empty field; the fallback hands the typed query straight to Google in Chrome. The search
field stays the query. Typing lists the typed row, matching local history, matching pages from Chrome's
browsing history and Google's autocomplete suggestions (queries and websites); ↵ and ⌘↵ open Google's results page in the user's Chrome as a new
tab. Tinycast never scripts Chrome: it only hands it a URL. The code is fork-owned, in
`Tinycast/Fork/ChromeSearch/` (see [fork.md](../fork.md#search-google)).

## Invariants

- **Tinycast never scripts Chrome.** No Apple Events, no helper window, no Automation prompt. Chrome
  is launched or raised only by an explicit action (↵, ⌘↵ or the fallback), through
  `NSWorkspace.open(_:withApplicationAt:)`, which opens a URL as a new tab in Chrome's front window.
  Typing only fetches suggestions over HTTP, as the Raycast Google Search extension does.
- **Every keystroke asks at once.** There is no debounce: `queryChanged` cancels the previous
  suggestion task and starts the next. The typed row and history rows come from local state in the
  same frame, and the previous suggestions stay until the next set lands. A response applies only if
  it still answers the query in the field.
- **Suggestions use a private session.** `GoogleSuggestionClient` is `.ephemeral` with
  `urlCache = nil`, never `URLSession.shared`. It sends nothing for an empty query or outside this
  screen, and leaving the screen cancels the request.
- **History is local.** `GoogleSearchHistory` (Model, pure) keeps 50 queries, most recent first,
  unique ignoring case. `GoogleSearchHistoryStore`, owned by `AppCore`, persists it as JSON at
  `AppPaths.applicationSupport()/google-search-history.json` and is never part of settings backups.
  Every query opened on Google and every website opened is recorded.
- **Chrome's browsing history is read, never kept.** `ChromeHistoryReader` copies the last-used
  profile's `History` (named by `profile.last_used` in `Local State`, plus `History-wal`) into a private
  temp directory, opens the copy read-only and queries it off the main actor; it copies again only when
  Chrome has written since. `ChromeHistoryRanking` (Model, clock injected) cuts the candidates to 5. Rows
  live in memory only, are never logged, and the copy is deleted when the screen closes (`reset()`) and
  on exit. No backup or `settings.json` carries them, and any failure yields no rows and no error.
- **The command gates the fallback**, as Define Word's does: while Search Google is hidden in
  Settings › Commands, `FallbackCoordinator` offers no fallback.
- **Without Chrome, the default browser opens the page** (`AppLauncher.open`).

## Actions

| Key | Typed, history, query suggestion | Website suggestion or Chrome page |
| --- | --- | --- |
| ↵ | Open Google's results page in Chrome, close the palette | Open the URL in Chrome |
| ⌘↵ | same as ↵ | Open Google's results page for the site's host |
| ⇥ | Put it in the field without searching (not on the typed row) | same, with the site's host |
| ⌃X | Remove from History (history rows) | none |
| ⌃⇧X | Clear Search History (history rows) | none |
| ⌘K | lists the above with their shortcuts | |

With an empty field the screen lists recent history, never Chrome pages. A result whose host is
`github.com` or a subdomain shows the GitHub icon (`ChromeSearchHostIcon`).
