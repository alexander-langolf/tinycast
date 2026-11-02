## ADDED Requirements

### Requirement: Selection reading is one shared path

Tinycast SHALL read a selection through `ForkSelectionReader` for Quick Actions, extensions and
Automation. The reader SHALL try Accessibility, then BetterTouchTool, then the clipboard borrow.

#### Scenario: Chrome selection
- **WHEN** Accessibility returns no text for a Chrome selection
- **THEN** the reader returns BetterTouchTool's text with source `betterTouchTool`

#### Scenario: Borrow excluded
- **WHEN** a caller excludes the clipboard borrow and the earlier sources return no text
- **THEN** the reader returns nothing and sends no ⌘C

### Requirement: Quick Actions run without the UI

Tinycast SHALL run a Quick Action through the `quick_action_run` Automation tool without showing
the palette.

#### Scenario: Rewrite from Script Kit
- **WHEN** a client with the `selection` scope calls `quick_action_run` with action `rewrite` and `apply` true while text is selected in Chrome
- **THEN** the selection is replaced with the rewrite, and the call returns the text with `applied` true

#### Scenario: Client without the scope
- **WHEN** a client without the `selection` scope calls `selection_read`
- **THEN** the call is denied and the audit log records the denial

### Requirement: Automation calls are traced

Tinycast SHALL record each Automation call as a trace with the client ID, operation, duration and
outcome, and SHALL NOT record arguments or results.

#### Scenario: Traced call
- **WHEN** a client calls `hud_show`
- **THEN** `tinycast logs --op automation` shows the call with its duration and outcome
