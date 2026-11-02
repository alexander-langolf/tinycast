## ADDED Requirements

### Requirement: Fix runs inside Tinycast

When Lyra is enabled, Tinycast SHALL offer a Fix marker after the user pauses in a text field
holding at least 3 words and at most 1,000 characters. Tinycast SHALL apply the fix on the second
Tab.

#### Scenario: Fix in TextEdit
- **WHEN** the user types "can u send me teh notes pls" in TextEdit and pauses
- **THEN** a Fix marker appears, and two Tab presses replace the text with the local model's fix

#### Scenario: Secure field
- **WHEN** the focused field is a password field
- **THEN** Tinycast sends no request

### Requirement: The panel rewrites through Tinycast connections

Tinycast SHALL open the rewrite panel through the Lyra rewrite command (default Hyper+R).
Tinycast SHALL run Refine, Professional and Friendly through the connection chosen in settings.

#### Scenario: Professional rewrite of a selection
- **WHEN** the user selects part of a paragraph, invokes the Lyra rewrite command (default Hyper+R), chooses Professional and presses Return after the stream completes
- **THEN** only the selection changes

### Requirement: Tinycast owns the model server

Tinycast SHALL reuse a healthy `llama-server` on port 8765 or start one while Lyra is enabled.
Tinycast SHALL stop only a server it started, and SHALL report the server in `tinycast://health`.

#### Scenario: Server already running
- **WHEN** a healthy server answers on port 8765 at Tinycast launch
- **THEN** Tinycast reuses it and leaves it running at quit

### Requirement: A Lyra mode runs without the UI

Tinycast SHALL run a Lyra mode through the `lyra_rewrite` Automation tool under the `selection`
scope.

#### Scenario: Script Kit runs Friendly
- **WHEN** a client with the `selection` scope calls `lyra_rewrite` with mode `friendly` and `apply` true
- **THEN** the selection is replaced, and the call returns the rewrite

### Requirement: A selection in Slack triggers Fix

Tinycast SHALL offer a Fix marker for a Slack selection of at least 3 words and at most 1,000
characters, after the selection settles for 0.5 s, while Lyra is enabled. Applying the fix
SHALL replace only the selection. A selection in any other app SHALL NOT trigger Fix.

#### Scenario: Selection in a Slack message
- **WHEN** the user selects "can u send me teh notes" inside an unsent Slack message
- **THEN** a Fix marker appears, and two Tab presses replace only the selected words

#### Scenario: Selection in Chrome
- **WHEN** the user selects three words in a Chrome text field
- **THEN** no Fix marker appears
