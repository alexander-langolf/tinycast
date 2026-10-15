## ADDED Requirements

### Requirement: Chrome history pages appear as Search Google results

While the trimmed query is not empty, the Search Google screen SHALL list matching pages from Chrome's
browsing history. Rows SHALL be ordered: the typed row, local query history, history pages, then
Google's suggestions. At most 5 history pages SHALL be shown. Each page row SHALL show its title and
host, falling back to the host alone when the title is empty. A page whose URL equals a website
suggestion's URL SHALL be shown once, as the history page. With an empty field the screen SHALL NOT
list history pages, because browsing history is not a recent list. History rows SHALL be computed off
the main actor, started on every keystroke, and the previous history rows SHALL stay on screen until
the next set arrives. A result SHALL be applied only if it answers the query currently in the field.

#### Scenario: Visited page matches the typed words
- **WHEN** the user has visited "Tinycast · GitHub" at github.com/acme/tinycast and types "tinycast"
- **THEN** a history row titled "Tinycast · GitHub" with host "github.com" appears after the typed row
  and local query history, and before Google's suggestions

#### Scenario: Every word must match
- **WHEN** the user types "tinycast issues"
- **THEN** only pages whose title or URL contain both "tinycast" and "issues" (case-insensitive) are listed

#### Scenario: Duplicate of a website suggestion
- **WHEN** Google returns the website github.com/acme/tinycast and the same URL is in Chrome history
- **THEN** one row is shown, as the history page

#### Scenario: Empty field lists no history pages
- **WHEN** the field is empty or only whitespace
- **THEN** no Chrome history is read and no history page rows are shown

#### Scenario: A late result is discarded
- **WHEN** history rows for "tin" arrive after the field already reads "tiny"
- **THEN** the "tin" rows are not shown

#### Scenario: Typing never blanks the list
- **WHEN** the user types another character while history rows are shown
- **THEN** the previous history rows stay until the new set arrives

### Requirement: History pages are ranked by match, visits and recency

History pages SHALL be ranked by, in order of weight: match quality, visit count, then recency. A
title or host prefix match SHALL outrank a substring match. Visit count SHALL contribute
logarithmically and recency SHALL decay with age. The ranking rule SHALL be a pure function of the
candidates and an injected clock, and SHALL cut a bounded candidate set (about 200) to the rows shown.

#### Scenario: Prefix beats substring
- **WHEN** one page's title starts with the typed word and another only contains it
- **THEN** the prefix match ranks first, whatever their visit counts

#### Scenario: Visits and recency break ties
- **WHEN** two pages match equally well and one was visited more often and more recently
- **THEN** that page ranks first

#### Scenario: Ranking is deterministic
- **WHEN** the same candidates and clock are ranked twice
- **THEN** the order is identical

### Requirement: History pages open in Chrome

↵ on a history page SHALL open its URL in Chrome as a new tab, bring Chrome forward, close the
palette and record the page's title in the local query history, the same way a website suggestion
does. ⌘↵ SHALL open Google's results page for the page's host. ⇥ SHALL put the page's host in the
field and load suggestions for it, without opening anything. When Chrome is not installed the default
browser SHALL open the URL instead.

#### Scenario: Enter opens the page
- **WHEN** the user selects a history page and presses ↵
- **THEN** its URL opens as a new tab in Chrome and the palette closes

#### Scenario: Command-Enter searches the host
- **WHEN** the user selects a history page on github.com and presses ⌘↵
- **THEN** Google's results page for "github.com" opens as a new tab in Chrome

#### Scenario: Tab completes the host
- **WHEN** the user selects a history page on github.com and presses ⇥
- **THEN** the field reads "github.com", suggestions for it load, and nothing opens

### Requirement: Chrome history is read from a private copy of the last-used profile

Tinycast SHALL read Chrome's `History` database from a temporary copy, opened read-only, never the
original that Chrome locks. The copy SHALL include `History-wal` when present. The profile SHALL be
the one named by `profile.last_used` in Chrome's `Local State`, never a hardcoded name. The copy SHALL
be refreshed at most once per screen visit and again only when the source's modification date has
changed. The copy SHALL be deleted when the screen closes and when the app exits. A missing Chrome
install, a missing or unreadable `Local State` or `History`, an unknown profile or a failed query
SHALL yield no history rows and no error UI.

#### Scenario: Profile comes from Local State
- **WHEN** `Local State` names "Profile 1" as `last_used`
- **THEN** history is read from the `Profile 1` directory

#### Scenario: Locked original
- **WHEN** Chrome is running and holds its `History` file locked
- **THEN** history is still read, from the temporary copy

#### Scenario: Copy is reused while unchanged
- **WHEN** the user types several queries in one visit and Chrome's `History` has not changed
- **THEN** the file is copied once

#### Scenario: Copy is removed
- **WHEN** the user leaves the Search Google screen
- **THEN** the temporary copy is deleted

#### Scenario: Chrome history is unavailable
- **WHEN** Chrome is not installed, or `History` cannot be read
- **THEN** no history rows are shown and no error appears, and the rest of the screen works

### Requirement: Chrome history stays local and is never scripted

Chrome history SHALL be read on demand, held in memory only and never logged. Tinycast SHALL NOT
persist any of it beyond the temporary copy, and no backup or `settings.json` SHALL carry it. Chrome
SHALL NOT be scripted: no Apple Events, no CDP and no helper window. Reading `~/Library/Application
Support/Google/Chrome/` SHALL NOT require a TCC grant or Automation permission.

#### Scenario: Nothing is persisted
- **WHEN** the user uses Search Google with history results and then quits Tinycast
- **THEN** no Chrome history remains on disk outside Chrome's own files

#### Scenario: Backups exclude history
- **WHEN** the user exports a settings backup or enables the `settings.json` mirror
- **THEN** neither contains any Chrome history

#### Scenario: Chrome is not scripted
- **WHEN** history results are read and a page is opened
- **THEN** Chrome receives only a URL handed to it, with no Apple Event, CDP session or helper window

### Requirement: Results on github.com show a GitHub icon

Any result row whose URL host is `github.com` or a subdomain of it SHALL show the GitHub brand icon
in place of the generic globe, whether the row is a history page or a Google website suggestion. The
icon SHALL render as a template image at the result-row icon size. Every other host SHALL keep the
existing icon. The host-to-icon mapping SHALL be a pure function that lets other hosts be added later.

#### Scenario: History page on GitHub
- **WHEN** a history page's URL is https://github.com/acme/tinycast
- **THEN** its row shows the GitHub icon

#### Scenario: Website suggestion on GitHub
- **WHEN** Google returns the website suggestion "gist.github.com"
- **THEN** its row shows the GitHub icon

#### Scenario: Lookalike host
- **WHEN** a result's host is "notgithub.com" or "github.com.example.org"
- **THEN** its row shows the existing icon

#### Scenario: Other hosts
- **WHEN** a result's host is "example.com"
- **THEN** its row shows the existing icon
