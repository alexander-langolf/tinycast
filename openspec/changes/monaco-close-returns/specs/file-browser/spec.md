## ADDED Requirements

### Requirement: Closing the Monaco editor returns to the browser

When File Navigator opens a file in the Monaco editor, Tinycast SHALL show File Navigator again after the editor closes.
The restored screen SHALL keep the folder, the filter, the picks and the focused row it had when the file opened.
Esc, ⌘W, the close button and a completed unsaved-changes dialog SHALL each count as a close.
Cancelling the unsaved-changes dialog SHALL keep the editor open and SHALL show no palette.

#### Scenario: Close after editing
- **WHEN** the user opens a file from File Navigator in Monaco and then presses Esc
- **THEN** the editor closes and File Navigator shows the same folder, filter, picks and focused row

#### Scenario: Folder removed while editing
- **WHEN** the folder no longer exists when the editor closes
- **THEN** File Navigator shows its missing-folder recovery state

#### Scenario: Cancel the close
- **WHEN** the user presses ⌘W with unsaved changes and chooses Cancel
- **THEN** the editor stays open and the palette stays hidden

#### Scenario: Another file replaces the open one
- **WHEN** the user opens a second file while the editor is open, and then closes the editor
- **THEN** Tinycast returns to the screen that opened the first file
