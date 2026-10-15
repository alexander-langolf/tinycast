## Why

Search Google lists only Tinycast's own 50-query history and Google's autocomplete. Chrome's new-tab
dropdown also offers pages already visited, so a known page means typing its full name or leaving
Tinycast. Chrome's omnibox can't be driven without scripting Chrome, which Tinycast never does, so the
same signal has to come from Chrome's own history file.

## What Changes

- Typing in Search Google also lists matching pages from Chrome's browsing history, read-only, beside the
  typed row, local query history and Google suggestions.
- History pages show title and host, ranked by match quality, visit count and recency.
- ↵ on a history page opens its URL in Chrome as a new tab; ⌘↵ and ⇥ follow the website-suggestion rows.
- Any result whose host is `github.com` (or a subdomain) shows a GitHub icon, whether it comes from
  history or from Google's website suggestions.
- Chrome's `History` file is copied to a temporary location and read there, since Chrome locks the
  original. The profile comes from Chrome's `Local State` (`last_used`), never a hardcoded name.
- Nothing from Chrome history is persisted by Tinycast or carried by backups or `settings.json`.
- Chrome is still never scripted: no Apple Events, no CDP, no helper window.

## Capabilities

### New Capabilities

- `chrome-history-results`: reading Chrome's browsing history as Search Google results, their ranking and
  actions, and host-based icons on results (GitHub).

### Modified Capabilities

<!-- The Search Google spec still lives in the unarchived `chrome-google-search` change, not in
     openspec/specs/. Its rows and actions are extended by the new capability above. -->

## Impact

- Code: `Tinycast/Fork/ChromeSearch/` — a pure Model for history matching and ranking, a Service that
  copies and queries the `History` SQLite file off the main actor, new row cases in `GoogleSearchRow`,
  and the row view in `ChromeSearchRows.swift`.
- Wiring: owned by `AppCore` like `GoogleSearchHistoryStore`; reached by the screen through the
  existing `ChromeSearchCoordinator`.
- Docs: `docs/features/chrome-google-search.md` invariants (history is local, Chrome is never
  scripted) and `docs/fork.md`.
- Dependencies: none new; system SQLite via `SQLite3`. Reads `~/Library/Application Support/Google/Chrome/`,
  which needs no TCC grant.
- Privacy: Chrome history is more sensitive than the query history, so it is read on demand, held in
  memory only, and never logged.
- Depends on `chrome-google-search` landing first.
