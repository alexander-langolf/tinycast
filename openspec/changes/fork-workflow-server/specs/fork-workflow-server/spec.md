## ADDED Requirements

### Requirement: Workflows run on the server

Tinycast SHALL run Rewrite and Fix Grammar as actions of the workflow server, and the server SHALL
apply a changed action, prompt or policy file without a Tinycast build or restart.

#### Scenario: Prompt change
- **WHEN** Sasha edits `server/prompts/rewrite.txt` while Tinycast and the server run
- **THEN** the next Rewrite uses the new prompt

#### Scenario: Broken action
- **WHEN** a saved action fails to import or validate
- **THEN** the server logs the rejection and keeps running the previous version

### Requirement: Every front end runs the same action

The server SHALL run an action for a POST with its token, and Tinycast SHALL forward a
`tinycast://run/<name>` link to the server only for link-safe actions.

#### Scenario: BetterTouchTool runs Lyra Fix
- **WHEN** a BetterTouchTool Open URL action opens `com.tinycast.app.dev://run/lyra-fix-selection` with a Slack selection
- **THEN** the Fix marker appears for the selection, and no process starts

#### Scenario: Tinycast hotkey
- **WHEN** the user presses the Rewrite hotkey while the server runs
- **THEN** the server's `rewrite` action handles it, and `tinycast logs --id <id>` shows server and Tinycast events under one correlation ID

#### Scenario: Server down
- **WHEN** the server is not running and the user presses the Rewrite hotkey
- **THEN** Tinycast shows the fallback message and runs the built-in Rewrite

### Requirement: Primitives stay in Tinycast

Tinycast SHALL provide selection reading, model completion, text replacement, previews, markers
and messages as Automation tools. Tinycast SHALL refuse `text_replace` for an expired handle or a
changed field.

#### Scenario: Field changed before replace
- **WHEN** the user edits the field after `selection_read` and before `text_replace`
- **THEN** `text_replace` returns `applied: false` and leaves the field unchanged
