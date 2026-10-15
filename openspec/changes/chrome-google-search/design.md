## Context

Searching Google from Tinycast used to mean leaving the palette: a quicklink opens Chrome and the
results page takes over the screen. The Search Google screen suggests as you type and hands the
search to Chrome, the way the Raycast Google Search extension does.

The first version also listed Google's results inside the palette, by driving a hidden Chrome window
over Apple Events and reading the DOM. It was removed. Creating a Chrome window raises Chrome, so
typing made the browser flash, minimise and open pages, and ⌘↵ opened a new window instead of a
tab. Google serves results only to clients that run JavaScript, so there is no clean way to read
them without scripting a real browser.

## Goals / Non-Goals

**Goals:**
- Suggestions and local history under the search field, with a keystroke-fast response.
- Every open action lands as a new tab in the user's Chrome. Typing never touches Chrome.
- No Automation prompt and no Chrome setup.

**Non-Goals:**
- No in-palette results, no scraping of Google's pages, no Chrome scripting of any kind.
- No other browsers: Chrome is preferred, and the default browser is the fallback.

## Decisions

### 1. Feature layout mirrors Dictionary
`Tinycast/Fork/ChromeSearch/` holds `Model/` (pure), `Service/` and `UI/`. Integration points in
shared files are marked `// FORK: chrome-search`: `PaletteMode.googleSearch`, `CommandID.searchGoogle`,
`Fallback.Builtin.searchGoogle`, the two coordinators, `RootPaletteView` routing and `AppCore`
ownership.

### 2. The session only holds suggestions
`ChromeSearchSession` is `@MainActor @Observable` with `query` and `suggestions`. `queryChanged`
cancels the previous request, starts the next at once and applies a response only if it still
answers the current query. There is no debounce. A blank query clears the list and sends nothing.

### 3. Suggestions use `client=chrome` on a private session
`GoogleSuggestionClient` uses an `.ephemeral` session with `urlCache = nil` and a 3 s timeout, modelled
on `CurrencyRateStore`. The body is decoded with the response charset (ISO-8859-1 fallback) and parsed
into queries and websites by `google:suggesttype`.

### 4. Opening is a URL handoff
`ChromeSearchCoordinator.openInChrome` hides the palette and calls
`NSWorkspace.open([url], withApplicationAt: chrome)` with `activates = true`. Chrome opens such a URL as
a new tab in its front window. Without Chrome, `AppLauncher.open` uses the default browser. ↵ and ⌘↵
on query rows open the results page; a website row's ↵ opens the site and its ⌘↵ searches its host.

### 5. Local history
`GoogleSearchHistory` (Model, pure) handles insertion, dedupe, a cap of 50, matching and removal.
`GoogleSearchHistoryStore` (Service, `@MainActor`, owned by `AppCore`) keeps a JSON file at
`AppPaths.applicationSupport()/google-search-history.json`, loads on first use and writes atomically. It
is not part of settings backups. History rows come before Google's suggestions.

## Risks / Trade-offs

- **No in-palette results** → The user sees Google's results in Chrome, as with the Raycast extension.
- **Keystrokes reach Google as suggestion requests** → Only while this screen is open, never for an
  empty query, on a private session with no cache.
- **A URL handoff opens a new window when Chrome has none** → That is Chrome's own behaviour and what
  the user would get from a quicklink.

## Migration Plan

New feature, no data migration. The history file is created on the first recorded query.
