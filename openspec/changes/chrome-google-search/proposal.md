## Why

Searching Google from Tinycast currently means leaving the palette: a quicklink opens Chrome, and
the results page takes over the screen. A palette screen that suggests as you type keeps the search
on the keyboard and hands the chosen search to Chrome, the way Raycast's Google Search extension does.

## What Changes

- New **Search Google** launcher command that opens a dedicated palette screen. The search field is
  the query, and every keystroke immediately shows local history and Google's autocomplete suggestions.
- ↵ and ⌘↵ on the typed query, a history row or a suggestion open Google's results page in Chrome as a
  new tab. A website suggestion opens its URL on ↵. ⇥ completes a suggestion into the field.
- New **Search Google** launcher fallback that opens the typed launcher query on Google in Chrome.
- Local search history, kept on the machine, with Remove from History and Clear Search History.
- Typing never launches, scripts or raises Chrome, and Tinycast never creates a Chrome window or asks
  for Automation permission.
- Suggestions are fetched on a private ephemeral session with no URL cache, and only while the
  Search Google screen is open.

## Capabilities

### New Capabilities

- `chrome-google-search`: the Search Google palette screen. It covers live suggestions, local history,
  handing a search or website to Chrome as a new tab, and the launcher command and fallback.

### Modified Capabilities

<!-- None: the launcher gains a command and a fallback through existing extension points. -->

## Impact

- **New fork feature folder** `Tinycast/Fork/ChromeSearch/` with `Model/`, `Service/` and `UI/`.
- **Upstream integration points**, each marked `// FORK: chrome-search` and listed in `docs/fork.md`:
  `PaletteMode`, `CommandID`, `Fallback.Builtin`, `LauncherCoordinator`, `FallbackCoordinator`,
  `RootPaletteView` and `AppCore`.
- **Network**: requests to `suggestqueries.google.com` while the screen is open. No new dependencies.
- **Tests**: a standalone harness for suggestion parsing, URL building, history, rows and stale-suggestion
  rejection, registered in `Scripts/run-tests.sh`.
- **Docs**: `docs/features/chrome-google-search.md`, with `docs/fork.md` and `docs/features/launcher.md`
  updated.
