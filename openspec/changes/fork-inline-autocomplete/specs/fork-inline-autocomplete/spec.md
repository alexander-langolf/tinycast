## ADDED Requirements

### Requirement: Tinycast bundles contextual ranking

Tinycast SHALL bundle its standard-library Python service and locate it through app resources in Debug and Release.
The service SHALL use one Kneser-Ney trigram scorer and recent-word cache per Tinycast channel.
Oxford fallback words SHALL rank below personal candidates.
No Swift or Python service locator SHALL depend on a vault directory.

#### Scenario: Service startup from the app
- **WHEN** Tinycast starts a new autocomplete service
- **THEN** it launches the bundled `service.py` with the running bundle identifier
- **AND** sibling Python imports resolve inside the bundled resource folder

#### Scenario: Research imports
- **WHEN** the research ladder imports the production scorer and socket engine
- **THEN** it resolves the repository modules without a kitten source copy

### Requirement: Learned counts persist locally

The service SHALL retain the existing channel-specific `Autocomplete/learned.sqlite3` path and schema.
It SHALL commit each learned event before acknowledgment and restore counts at startup.
The learned store SHALL have mode 600, and the service SHALL log no typed text.

#### Scenario: Restart
- **WHEN** the service restarts after acknowledging a learned word
- **THEN** the restored model includes that learning event exactly once

### Requirement: Completion defaults to all eligible applications

Tinycast SHALL use `autocomplete.excludedBundleIDs` instead of an allow-list.
The default exclusions SHALL be VS Code, Xcode, Zed, and 1Password with their accepted bundle identifiers.
Settings SHALL provide bundle-ID add and remove controls.
Tinycast's own windows SHALL always be excluded.

#### Scenario: Ordinary applications
- **WHEN** a user types at the end of an eligible field in an application outside the exclude list
- **THEN** Tinycast may show a suffix when confidence reaches the configured threshold and real caret geometry exists

#### Scenario: Default exclusion
- **WHEN** VS Code is frontmost with the default preferences
- **THEN** autocomplete reads no field value and shows no ghost

#### Scenario: Own window
- **WHEN** a Tinycast window has focus and the exclude list is empty
- **THEN** autocomplete reads no field value and shows no ghost

### Requirement: Completion targets editable text surfaces

Text fields, search fields, text areas, combo boxes, and editable web content SHALL be eligible.
Explicitly read-only controls and non-editable web containers SHALL be excluded.
A browser address bar SHALL qualify as a text field.
Generic spreadsheet cells SHALL require an eligible text editor.
Missing value or selection SHALL suppress both presentations.
Missing caret geometry SHALL select the fallback chip when a safe anchor exists.
The default confidence threshold SHALL be 0.5.

#### Scenario: Missing caret
- **WHEN** an otherwise eligible field exposes no real caret bounds
- **THEN** Tinycast may show the top prediction in a fallback chip at the same confidence threshold
- **AND** the chip shows the full predicted word with the typed prefix de-emphasised

### Requirement: Fallback placement uses focused Accessibility geometry

The chip SHALL prefer the focused field's bottom-left corner, below its Accessibility position and size.
The chip SHALL stay inside a display's visible frame and SHALL never intersect a known field frame.
Placement MAY move above the field when the chip cannot fit below.
If the field frame is unavailable, the chip SHALL use the focused window's bottom-left interior.
The chip SHALL use no mouse anchor or invented coordinates.

#### Scenario: Field frame unavailable
- **WHEN** an eligible field exposes text and selection but no caret or field frame
- **AND** its focused window exposes a usable frame
- **THEN** the chip appears inside the window near its bottom-left corner

#### Scenario: Safe placement unavailable
- **WHEN** neither frame is known or no non-overlapping on-screen placement fits
- **THEN** Tinycast shows no chip and registers no autocomplete keys
- **AND** diagnostics record `noAnchor` or `offscreen`

#### Scenario: Geometry changes
- **WHEN** a visible suggestion's caret availability, caret bounds, or fallback frame changes
- **THEN** Tinycast dismisses the suggestion and releases its keys

### Requirement: Presentation kind is observable without text

Each successful autocomplete offer SHALL record `presentationKind` as `inlineGhost` or `fallbackChip`.
Presentation tracing SHALL contain no typed prefix, predicted word, context words, or field text.

#### Scenario: Fallback offer
- **WHEN** Tinycast submits a fallback chip to AppKit
- **THEN** `tinycast logs --op autocomplete` includes an offer with `presentationKind=fallbackChip`

### Requirement: Autocomplete owns Tab during typing

Autocomplete SHALL register Tab and Escape only while ghost text or a fallback chip is visible.
An explicit Lyra card or workflow marker SHALL hide autocomplete and release its keys before Lyra claims them.

#### Scenario: Acceptance
- **WHEN** a current ghost or fallback chip is visible and the user presses Tab
- **THEN** Tinycast inserts the suffix into the same focused field

#### Scenario: Dismissal
- **WHEN** another key, Escape, a click, a selection change, or an app switch dismisses the suggestion
- **THEN** obsolete results cannot restore it

#### Scenario: Normal Tab
- **WHEN** no ghost, fallback chip, or explicit Lyra surface is visible
- **THEN** neither autocomplete nor Lyra claims Tab for typing assistance

#### Scenario: Lyra card
- **WHEN** the Lyra hotkey opens a card
- **THEN** autocomplete stays hidden and owns no Tab registration until the card closes

### Requirement: Secure fields are never read

Tinycast SHALL check focused elements and their ancestors for secure and protected content before reading text.
Secure fields SHALL produce no learning event, ghost, or fallback chip regardless of the exclude list.

#### Scenario: Password field
- **WHEN** focus enters a secure or protected field
- **THEN** autocomplete reads no value, learns no word, and presents no suggestion

#### Scenario: Obsolete target
- **WHEN** the field, text, selection, or frontmost app changes before insertion
- **THEN** Tinycast rejects the old target
