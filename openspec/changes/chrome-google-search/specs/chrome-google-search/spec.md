## ADDED Requirements

### Requirement: Search Google opens a dedicated palette screen

The launcher SHALL offer a **Search Google** command that opens the Search Google palette screen
with an empty query. The launcher SHALL also offer a **Search Google** fallback that opens Google's
results page for the typed launcher query in Chrome at once. The command's visibility
SHALL gate the fallback, the same way Define Word's does: while the command is hidden in Settings ›
Commands, the fallback SHALL NOT be offered.

#### Scenario: Command opens an empty screen
- **WHEN** the user runs Search Google from the launcher
- **THEN** the palette switches to the Search Google screen with an empty, focused search field
- **AND** the screen shows a "Search Google" prompt instead of rows

#### Scenario: Fallback opens the typed query
- **WHEN** the user types "swift observation" in the launcher and picks the Search Google fallback
- **THEN** Google's results page for "swift observation" opens in Chrome and the palette closes

#### Scenario: Hidden command hides the fallback
- **WHEN** Search Google is hidden in Settings › Commands
- **THEN** the launcher offers no Search Google fallback

### Requirement: Typing shows Google suggestions

While the trimmed query is not empty, the screen SHALL
list the typed query as its first row, then matching entries from the local search history, then
Google's autocomplete suggestions for it. Every keystroke SHALL send its suggestion request at once,
with no debounce, and SHALL cancel the request still in flight. The typed row and history rows SHALL
appear synchronously with the keystroke, before any network answer. The previous suggestions SHALL
stay on screen until the next set arrives, so typing never blanks the list. A response SHALL be
applied only if it answers the query currently in the field.

Google marks each suggestion as a search query or a website. A website suggestion SHALL be shown as
a website row with its URL, and SHALL be opened directly instead of searched.

#### Scenario: Suggestions follow the query
- **WHEN** the user types "tinyc"
- **THEN** the first row is "tinyc" as typed
- **AND** Google's suggestions for "tinyc" follow it, in Google's order and without duplicates of
  the typed row

#### Scenario: No debounce
- **WHEN** the user types "a" then "b" 30 ms apart
- **THEN** a request for "a" is sent at once and cancelled when "ab" is typed, and a request for
  "ab" is sent at once

#### Scenario: Website suggestion
- **WHEN** Google returns "github.com" marked as a website for the query "gith"
- **THEN** a website row shows "github.com" with its URL
- **AND** ↵ on it opens that URL in Chrome without a Google search

#### Scenario: A late response is discarded
- **WHEN** suggestions for "tin" arrive after the field already reads "tiny"
- **THEN** the "tin" suggestions are not shown

#### Scenario: Suggestions fail quietly
- **WHEN** the suggestion request fails or times out
- **THEN** the screen keeps the typed-query row, so ↵ still searches
- **AND** no error is shown for suggestions alone

#### Scenario: Empty query
- **WHEN** the field is empty or only whitespace
- **THEN** no request is made
- **AND** the screen lists the most recent history entries, or the "Search Google" prompt when the
  history is empty

### Requirement: Search history is kept locally

The screen SHALL record in a local history every query the user sends to Google, when opened in
Chrome, and every website suggestion they open. The history SHALL be kept most recent first,
without duplicates, capped at 50 entries, and stored under the app's own
Application Support directory, keyed by bundle identifier, and SHALL never leave the machine. While
typing, history entries containing the typed text (case-insensitive) SHALL appear after the typed
row and before Google's suggestions, at most 5 of them, and Google suggestions duplicating them
SHALL be dropped. ⌘K on a history row SHALL offer Remove from History and Clear Search History.

#### Scenario: History shows before the network answers
- **WHEN** the user once searched "swift observation" and now types "obs"
- **THEN** a history row "swift observation" appears in the same frame as the typed row

#### Scenario: Remove an entry
- **WHEN** the user chooses Remove from History on "swift observation"
- **THEN** that entry is gone from the screen and from disk

#### Scenario: Clear history
- **WHEN** the user chooses Clear Search History
- **THEN** the history is empty on screen and on disk

### Requirement: Rows open Google in Chrome as a new tab

↵ and ⌘↵ on the typed-query row, a history row or a query suggestion SHALL open Google's results
page for that row's text in Chrome, bring Chrome forward and close the palette. Chrome SHALL receive
the URL as a new tab; Tinycast SHALL NOT script Chrome, create a Chrome window of its own or request
Automation permission. ↵ on a website row SHALL open its URL the same way, and ⌘↵ on it SHALL open
the results page for its host. ⇥ on a suggestion or history row SHALL replace the field's text with it
and load suggestions for it, without opening anything. When Chrome is not installed the default
browser SHALL open the page instead.

#### Scenario: Enter opens Google in a new tab
- **WHEN** the user selects the suggestion "tinycast github" and presses ↵
- **THEN** Google's results page for "tinycast github" opens as a new tab in Chrome and the palette closes

#### Scenario: Command-Enter opens a new tab
- **WHEN** the user selects the suggestion "tinycast github" and presses ⌘↵
- **THEN** the results page opens as a new tab in Chrome, with no new Chrome window

#### Scenario: Tab completes a suggestion
- **WHEN** the user selects the suggestion "tinycast github" and presses ⇥
- **THEN** the field reads "tinycast github"
- **AND** suggestions for "tinycast github" load, and nothing opens

#### Scenario: Typing never touches Chrome
- **WHEN** the user types in the field
- **THEN** Chrome is not launched, scripted, raised or given a window

### Requirement: Suggestion traffic stays private and scoped

Suggestion requests SHALL use a private `.ephemeral` URL session with `urlCache` set to nil, never
`URLSession.shared`. They SHALL be sent only while the Search Google screen is open, and never for
an empty query. Leaving the screen SHALL cancel any request in flight.

#### Scenario: No requests outside the screen
- **WHEN** the user types in the launcher or any other palette screen
- **THEN** no request is sent to Google's suggestion endpoint

#### Scenario: Leaving cancels work
- **WHEN** the user leaves the screen while a suggestion request is in flight
- **THEN** the work is cancelled and its result is never applied
