> Sections 1, 3 and 7 describe the first version, which scripted Chrome. Section 8 removed that
> path; the design and spec describe the current behaviour.

## 1. Spike and scaffolding

- [x] 1.1 Spike in Script Editor or `osascript` against real Chrome. Create a worker window and try
  off-screen bounds, `minimized:true` and `visible:false`. For each, confirm that Chrome stays
  non-frontmost, that the user's windows keep their active tab, that `loading` turns false, and that
  `execute javascript` works. Measure the load time. Record the chosen approach in `design.md`
  (resolving the Open Question).
- [x] 1.2 Capture the exact error number and message Chrome returns when "Allow JavaScript from
  Apple Events" is off. Capture what a `/sorry/` CAPTCHA page looks like to the extraction script.
  Update the error mapping in `design.md`.
- [x] 1.3 Create `Tinycast/Fork/ChromeSearch/{Model,Service,UI,Resources}`. Register the folder and
  the `.js` resource in `project.yml`. Run `xcodegen generate`.

## 2. Model (pure, Foundation only)

- [x] 2.1 `GoogleSuggestions`: the suggestion URL builder (`client=firefox`, UTF-8, `hl`, `q`) and a
  parser for `["q", [..]]`. The parser drops blanks and case-insensitive duplicates of the typed
  text, and caps the list at 8.
- [x] 2.2 `GoogleResult` (title, url, displayURL, snippet; `Sendable`, `Hashable`) and
  `GoogleResultsParser` for the extraction JSON payload. It accepts partial items, drops
  non-http(s) and `google.com` URLs, and preserves order.
- [x] 2.3 The results-page URL builder (`/search?q=&hl=&num=10`) and the CAPTCHA URL classifier
  (`/sorry/`).
- [x] 2.4 `GoogleSearchPhase` (`suggesting`, `searching`, `results`, `failed`, each carrying its
  query) and `GoogleSearchFailure` (`chromeMissing`, `automationDenied`, `javaScriptDisabled`,
  `captcha`, `noResults`, `timedOut`, `scriptFailed(String)`).
- [x] 2.5 Confirm the Model folder imports neither AppKit nor SwiftUI (the AGENTS.md grep).

## 3. Chrome controller and suggestion client

- [x] 3.1 Write `Resources/google-results-extract.js`. Walk `#search a:has(> h3)`, falling back to
  `#rso`. Read title, url (unwrapping `/url?q=`), `cite` and the snippet. Skip ads, and return
  `JSON.stringify({items, blocked})`.
- [x] 3.2 `ChromeController`: a serial-queue `NSAppleScript` runner with `@concurrent async`
  wrappers. It resolves and launches Chrome without activating it (`activates: false`), keeps the
  worker window by id (using the approach chosen in 1.1), sets the URL, polls `loading` at 100 ms
  with an 8 s timeout, and runs the extraction script. It maps errors to `GoogleSearchFailure` and
  provides `closeWorker()`.
- [x] 3.3 `GoogleSuggestionClient`: an ephemeral `URLSession` with `urlCache = nil` and a 3 s timeout,
  modelled on `CurrencyRateStore`'s session. It returns the parsed suggestions for one query.
- [x] 3.4 `ChromeSearchSession` (`@MainActor @Observable`):
  - `queryChanged(_:)`: a 120 ms debounce, a return to `.suggesting` when the text differs from the
    phase query, and a check that the response matches the current query before applying it.
  - `search(_:)`: an operation counter, the `.searching` phase, and checks for cancellation, the
    operation id and the query after each await.
  - `reset()`: cancels both tasks and closes the worker.
  - Services are injected through small protocols, so the harness can fake them.

## 4. Palette screen and actions

- [x] 4.1 `ChromeSearchCoordinator`:
  - `show(term:)` toggles `.googleSearch`, seeding the query and searching when a term is given.
  - `open(result)` opens the result in Chrome, activates Chrome and hides the palette.
  - `openResultsPage(query)` opens Google's results page in Chrome.
  - `copyURL`, `openAutomationSettings` and `revealChrome` cover the remaining actions.
- [x] 4.2 `ChromeSearchScreen: PaletteScreen` derives its rows from the phase.
  - **Suggesting:** a typed row, then suggestion rows.
  - **Searching:** a "Searching Google…" state.
  - **Results:** the result rows.
  - **Failed:** a failure state with its recovery action.
  - **Keys:** ↵ runs the search or opens the result, ⌘↵ opens the results page, ⌘C copies, ⇥
    completes a suggestion, and ⌘K lists the actions.
  - **Empty query:** shows the prompt.
- [x] 4.3 Result and suggestion row views use `Theme` tokens and `metrics.typography`, following
  `docs/ui.md`. A result row shows the title, display URL and a one-line snippet.
- [x] 4.4 Wire the integration points, each marked `// FORK: chrome-search`:
  - `PaletteMode.googleSearch` (icon, placeholder)
  - `CommandID.searchGoogle`
  - `Fallback.Builtin.searchGoogle` (with its command and open verb)
  - `LauncherCoordinator` and `FallbackCoordinator` dispatch
  - `RootPaletteView` routing, plus its query-change and reset hooks
  - `AppCore` ownership and the palette environment injection
- [x] 4.5 Confirm Settings › Commands visibility gates the fallback, following the Define Word path
  in `FallbackCoordinator`.
- [x] 4.6 Reword `NSAppleEventsUsageDescription` in `Info.plist` to cover Ghostty and Chrome.

## 5. Tests

- [x] 5.1 Add `Tests/chrome-google-search-test.swift`. It covers suggestion parsing (dedupe, cap,
  malformed input), results parsing (partial items, filtering, order), both URL builders, and
  CAPTCHA classification.
- [x] 5.2 The harness drives `ChromeSearchSession` with fake services to cover these cases: a late
  suggestion is discarded, a superseded search is dropped, editing returns to suggesting, and reset
  cancels and closes the worker.
- [x] 5.3 Register the harness in `Scripts/run-tests.sh`, next to `dictionary-test`.

## 6. Docs and verification

- [x] 6.1 Write `docs/features/chrome-google-search.md`. It opens with `## Invariants` (the
  worker-window ownership rule, the ephemeral session, stale-result protection, and the extraction
  script as the only selector source), followed by the actions table, the failure states and the
  setup step.
- [x] 6.2 Update `docs/fork.md` with the integration points, and `docs/features/launcher.md` with the
  new command and fallback.
- [x] 6.3 Run `./Scripts/run-tests.sh` and `./Scripts/lint.sh`. Build Debug with no new warnings, and
  run the Model import grep.
- [ ] 6.4 Check the Dev build by hand: suggestions and history while typing, ↵ and ⌘↵ open a new tab
  in Chrome, ⇥ completes, the fallback opens Google from the launcher, and Chrome stays untouched
  while typing.

## 7. Speed parity with the Google Search extension

- [x] 7.1 Remove the suggestion debounce. Each keystroke requests at once and cancels the in-flight
  task, and the `debounce` parameter is deleted. Update the session tests.
- [x] 7.2 Switch suggestions to `client=chrome`. Decode the body using the response charset, with
  ISO-8859-1 as the fallback. Parse to `[GoogleSuggestion]` with `.query` and `.website(URL)`,
  using `google:suggesttype`. Add parser tests for both types, unknown types, the Latin-1 bytes and
  malformed payloads.
- [x] 7.3 Make the typed, history and query-suggestion rows open in Chrome on ↵, closing the
  palette, and search in the palette on ⌘↵. A website row opens its URL on ↵. Update ⌘K, the footer
  titles and the fallback, which stays an in-palette search.
- [x] 7.4 Change `ChromeController` to read results early. Poll the extraction every 150 ms after
  navigation, return on items or `blocked`, decide on the final load, and guard against reading a
  stale URL.
- [x] 7.5 ~~Add a warm worker~~ Removed: warming on a keystroke raised Chrome while typing. Typing
  only fetches suggestions, and tests assert the searcher is never called before an explicit search.
- [x] 7.6 Add local history:
  - The `GoogleSearchHistory` model, with tests.
  - `GoogleSearchHistoryStore`, owned by `AppCore` and stored under `AppPaths`.
  - History rows on an empty query and while matching, plus ⇥ to complete.
  - Remove from History and Clear Search History in ⌘K.
  - Recording on open, on search and on website open.
- [x] 7.7 Update `docs/features/chrome-google-search.md`: the new keys, history, warming, early
  reads and the invariants. Then rerun the tests, lint, the Debug build and the Model import grep.

## 8. Drop in-palette results

- [x] 8.1 Remove `ChromeController`, the extraction script, `GoogleResult`, `GoogleSearchPhase` and
  the failure states. Reduce `ChromeSearchSession` to the query and its suggestions.
- [x] 8.2 ⌘↵ opens Google's results page in Chrome as a new tab; the fallback opens the typed query
  in Chrome; drop "Search in Palette", result rows and the Automation wording.
- [x] 8.3 Rewrite the harness for suggestions-only behaviour, regenerate the project, and update the
  feature doc, `docs/fork.md`, `docs/features/launcher.md`, the spec, the design and the proposal.
