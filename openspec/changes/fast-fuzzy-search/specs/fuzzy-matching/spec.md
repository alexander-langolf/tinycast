## ADDED Requirements

### Requirement: The scorer keeps its results identical

The shared fork scorer SHALL return the same match decision, score and highlight positions as the
per-candidate scorer it replaces, apart from the two deliberate fold changes below. This SHALL hold
for every query syntax (`'exact`, `^prefix`, `suffix$`, `!exclude`), every scheme and every fold,
including expanding folds, combining marks, emoji and `\r\n` line endings. Highlight positions SHALL
be `Character` offsets into the source text.

#### Scenario: Mixed corpus parity
- **WHEN** the parity harness scores each query of its query set against each item of the mixed
  corpus with both the retired and the new scorer
- **THEN** every pair agrees on whether the item matches, on the score and on the positions

#### Scenario: Expanding fold
- **WHEN** the query `strasse` is scored against "Straße"
- **THEN** the item matches and its positions point at the source characters, with "ß" reported
  once

#### Scenario: Carriage return line endings
- **WHEN** a query is scored against text containing `\r\n`
- **THEN** each position counts the `\r\n` pair as one character

### Requirement: One fold serves every match

The fork fold SHALL ignore emoji skin-tone modifiers (U+1F3FB to U+1F3FF) and emoji variation
selectors (U+FE0E, U+FE0F). Fuzzy scoring, anchors, the launcher's exact-name check and the
clipboard's literal-word check SHALL all use this one fold. For a word with a non-ASCII letter, the
literal-word check SHALL search the folded text of the whole item rather than run Foundation's
case- and diacritic-insensitive search. An ASCII word SHALL keep its case-insensitive byte scan.

#### Scenario: Skin-tone emoji
- **WHEN** the clipboard holds "great 👍🏽 work" and the user types `great 👍`
- **THEN** the item matches

#### Scenario: Variation selector
- **WHEN** a candidate contains "❤️" and the query contains "❤" without a variation selector
- **THEN** the candidate matches

#### Scenario: Half-width text past the scan cap
- **WHEN** a clip longer than the scan cap holds "ｶﾀｶﾅ" only past the cap and the user types `カタカナ`
- **THEN** the item matches, as it would within the cap

### Requirement: A query is parsed once per search

A search SHALL parse and fold its query once and reuse the result for every candidate. Scoring a
candidate SHALL NOT parse the query or fold the query's words again.

#### Scenario: Many candidates
- **WHEN** a surface scores one query against 1,000 candidates
- **THEN** the query is parsed and folded once

### Requirement: Candidate text is prepared once and reusable

A candidate's text SHALL be preparable once into a folded form that later searches reuse. The
prepared form SHALL carry everything the scorer needs, so scoring a prepared candidate performs no
string folding and no grapheme splitting. ASCII text without `\r` SHALL be prepared without
splitting graphemes.

#### Scenario: Repeated keystrokes
- **WHEN** the user types a further letter into a query over prepared candidates
- **THEN** no candidate is folded again

#### Scenario: Plain ASCII candidate
- **WHEN** an ASCII candidate without `\r` is prepared
- **THEN** its folded units are its lowercased bytes, and positions map one to one onto source
  characters

### Requirement: A non-match is rejected before scoring work

The scorer SHALL check that each positive word is a subsequence of the prepared text before it
computes alignment. A candidate that fails this check SHALL be rejected without allocating memory.

#### Scenario: Absent letters
- **WHEN** a query contains a letter that a candidate's folded text lacks
- **THEN** the scorer rejects the candidate after one scan and computes no alignment

### Requirement: Search stays within its time budget

Over a 1,000-item corpus in which 10% of the items are non-ASCII, one warm search SHALL take at most
5 ms in an optimised build. A warm search is one whose candidates are already prepared. The
performance harness SHALL fail when the budget is exceeded. The `Tinycast` target's Debug
configuration SHALL build with `-O`, so Tinycast Dev searches within the same budget.

#### Scenario: Optimised build
- **WHEN** the performance harness runs its query set with `-O`
- **THEN** every query's median time is at most 5 ms

#### Scenario: Debug build
- **WHEN** Tinycast Dev is built with the Debug configuration
- **THEN** the `Tinycast` target compiles with `SWIFT_OPTIMIZATION_LEVEL` set to `-O`
