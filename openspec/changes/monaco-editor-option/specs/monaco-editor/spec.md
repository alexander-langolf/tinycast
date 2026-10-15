## ADDED Requirements

### Requirement: Monaco is an opt-in editor kind
Tinycast SHALL offer an editor kind setting with the values Terminal and Monaco, defaulting to Terminal.
The setting SHALL be mirrored as `fileNavigator.editorKind` and SHALL be carried by settings backups. An
absent or unrecognised value SHALL behave as Terminal.

#### Scenario: Fresh install
- **WHEN** the setting has never been changed
- **THEN** Edit uses the terminal editor exactly as before

#### Scenario: Unknown value in settings.json
- **WHEN** `fileNavigator.editorKind` holds a value other than `terminal` or `monaco`
- **THEN** the value is ignored and the editor kind remains Terminal

### Requirement: Monaco loads fully offline from the app bundle
The Monaco editor SHALL load from a bundle in the app's resources and SHALL NOT make any network request.
The web view SHALL use a non-persistent data store, SHALL be limited to read access to the bundle folder,
and SHALL refuse navigation to any other location and any new-window request.

#### Scenario: No network available
- **WHEN** the Mac is offline and Edit opens a file in Monaco
- **THEN** the editor loads and shows the file

#### Scenario: Page attempts to navigate away
- **WHEN** the page requests a navigation or a new window
- **THEN** the request is cancelled and the editor is unchanged

### Requirement: Search Files offers the same Edit
The Search Files actions menu SHALL include Edit for a file result, never for a folder, and it SHALL route by
the same editor kind as File Navigator. The Edit row SHALL be titled for the editor it opens.

#### Scenario: Edit a search result with Monaco
- **WHEN** the editor kind is Monaco and Edit is chosen on a file result in Search Files
- **THEN** that file opens in Monaco exactly as from File Navigator

#### Scenario: Edit a search result with Terminal
- **WHEN** the editor kind is Terminal and Edit is chosen on a file result in Search Files
- **THEN** the configured editor command opens it in an embedded editor terminal, as from File Navigator

#### Scenario: Folder result
- **WHEN** the selected Search Files result is a folder
- **THEN** the actions menu has no Edit row

### Requirement: Opening a file in Monaco
Edit with Monaco selected SHALL open the first selected file in Monaco in its own panel, hiding the palette. Only UTF-8
text files up to the size cap SHALL open. The language SHALL be chosen from the file extension, with plain
text as the fallback.

#### Scenario: Open a source file
- **WHEN** Edit executes on `main.swift` with Monaco selected
- **THEN** a panel shows the file's text in Monaco with Swift highlighting and the file name in the title

#### Scenario: Unsupported file
- **WHEN** the file is not valid UTF-8, exceeds the size cap, or can no longer be read
- **THEN** the editor does not open and a HUD message names the reason

#### Scenario: Several files selected
- **WHEN** Edit executes on several files with Monaco selected
- **THEN** only the first file opens

### Requirement: Saving and unsaved changes
⌘S SHALL write the buffer to the file as UTF-8, atomically, and clear the dirty marker. The editor SHALL show
a dirty marker while the buffer differs from the last saved text. If the file changed on disk since it was
loaded, Save SHALL ask through `DialogController` before overwriting. Closing, hiding the palette or quitting
with unsaved changes SHALL ask through `DialogController` to Save, Discard or Cancel.

#### Scenario: Save
- **WHEN** the user edits the text and presses ⌘S
- **THEN** the file on disk equals the buffer and the dirty marker clears

#### Scenario: File changed on disk
- **WHEN** the file's modification date differs from the one recorded at load and the user saves
- **THEN** Tinycast asks before overwriting and writes nothing if the user cancels

#### Scenario: Close with unsaved changes
- **WHEN** the user presses Esc or ⌘W with a dirty buffer
- **THEN** a Tinycast dialog offers Save, Discard and Cancel, and Cancel keeps the editor open

### Requirement: Keyboard and focus
The Monaco view SHALL be first responder while the panel is key. ⌘S SHALL save and Esc and ⌘W SHALL close,
with the close confirmation above, except that Esc SHALL first dismiss an open Monaco widget such as find or
suggestions. Every other key SHALL reach Monaco.

#### Scenario: Typing in the editor
- **WHEN** the user types or presses arrow keys in Monaco
- **THEN** only the Monaco buffer changes

#### Scenario: Close the editor
- **WHEN** the editor closes with no unsaved changes
- **THEN** the panel disappears and the web view is released after a short idle period

### Requirement: Appearance follows the app
Monaco SHALL use a dark theme when the app resolves to dark and a light theme otherwise, SHALL use the
configured monospaced font family, and SHALL update live when either changes.

#### Scenario: Appearance changes while open
- **WHEN** the user switches appearance while Monaco is open
- **THEN** the editor theme changes without losing the buffer, selection or undo history
