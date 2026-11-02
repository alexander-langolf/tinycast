## ADDED Requirements

### Requirement: A typed clipboard query searches text entries only

With fork search on, a non-empty clipboard query SHALL match only text entries: plain text, links,
colours and email addresses. Image and file entries SHALL NOT appear in typed results. This SHALL
hold for pinned and unpinned entries and for the resident window and FTS (full-text search)
retrieval alike. An empty query SHALL list every entry kind.

#### Scenario: Query matching a file path
- **WHEN** the history holds a file entry whose path contains "report" and the user types `report`
- **THEN** the file entry does not appear in the results

#### Scenario: Pinned image
- **WHEN** an image entry is pinned and the user types any query
- **THEN** the pinned image does not appear in the results

#### Scenario: Empty query
- **WHEN** the clipboard query is empty
- **THEN** text, image and file entries are all listed

#### Scenario: Images filter with a query
- **WHEN** the Images type filter is active and the user types a query
- **THEN** the list is empty

### Requirement: Recognized text takes no part in clipboard search

With fork search on, a clipboard query SHALL NOT consult text recognized from images or PDFs. Fork
search being on SHALL also keep `AppCore` from creating the background text indexer, and SHALL hide
the "Search text in images and PDFs" switch in Settings and in settings search. On-demand Copy
Text extraction SHALL keep working.

#### Scenario: Switch previously enabled
- **WHEN** the per-machine text search switch is on and fork search is on
- **THEN** no text indexer runs and no recognized-text query runs while the user types

#### Scenario: Settings
- **WHEN** the user opens Clipboard History settings or searches settings for "images"
- **THEN** the "Search text in images and PDFs" switch is not shown

#### Scenario: Copy Text
- **WHEN** the user runs Copy Text on an image entry
- **THEN** the recognized text is copied as before

### Requirement: Clipboard ranking keeps its order

Clipboard results SHALL keep their ordering rules:

- Pinned matches lead, in pin order.
- Ordinary matches follow, ranked by fzf score, with ties newest first.
- A query of one or two non-space characters keeps newest-first order.

FTS SHALL keep retrieving literal words of three or more letters from the whole history, limited
to the newest `searchLimit` hits.

#### Scenario: Long query
- **WHEN** the user types a word of three or more letters
- **THEN** resident and FTS matches are merged, deduplicated by item, and ranked by score

#### Scenario: Short query
- **WHEN** the user types one or two letters
- **THEN** matching resident entries are listed newest first

### Requirement: Clipboard items are prepared once

The clipboard SHALL keep each searched item's prepared text, keyed by item ID, and reuse it on
later keystrokes. The cache SHALL drop entries for items that leave the resident window. It SHALL
hold at most `searchLimit` entries for items outside that window. Search SHALL stay synchronous on
the main actor.

#### Scenario: Typing a longer query
- **WHEN** the user extends a query by one letter
- **THEN** no resident item's text is folded again

#### Scenario: Item deleted
- **WHEN** an item is deleted from the history
- **THEN** its prepared text is removed from the cache
