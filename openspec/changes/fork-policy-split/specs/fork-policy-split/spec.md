## ADDED Requirements

### Requirement: Lyra policy loads from files at run time

Tinycast SHALL read Lyra's limits, delays, modes, prompts and model routing from the policy folder
and SHALL apply a valid change without a rebuild or restart.

#### Scenario: Limit change
- **WHEN** Sasha changes `fix.minWords` from 3 to 5 in `policy/lyra.json` while Tinycast runs
- **THEN** typed Fix stops triggering on 4-word text, and the next Lyra event carries the new policy version

#### Scenario: Invalid change
- **WHEN** `policy/lyra.json` stops parsing
- **THEN** Tinycast logs the rejection and keeps the previous policy

### Requirement: BetterTouchTool decides where a selection offers Fix

Tinycast SHALL NOT trigger Fix from a selection on its own. The `lyra_offer` tool SHALL show the
Fix marker for the current selection when the selection meets the policy's `selection` limits.

#### Scenario: Slack selection
- **WHEN** the BetterTouchTool preset is active and the user selects four words in an unsent Slack message
- **THEN** BetterTouchTool calls `lyra_offer`, the Fix marker appears, and two Tab presses replace only the selection

#### Scenario: Add an app without a build
- **WHEN** Sasha adds Chrome to the preset's condition group
- **THEN** a selection in a Chrome text field offers Fix with the same Tinycast build
