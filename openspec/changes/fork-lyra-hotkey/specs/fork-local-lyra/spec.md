## MODIFIED Requirements

### Requirement: The panel rewrites through Tinycast connections

Tinycast SHALL open the rewrite panel through the Lyra rewrite command (default Hyper+R).
Tinycast SHALL run Refine, Professional and Friendly through the connection chosen in settings.

#### Scenario: Professional rewrite of a selection
- **WHEN** the user selects part of a paragraph, invokes the Lyra rewrite command (default Hyper+R), chooses Professional and presses Return after the stream completes
- **THEN** only the selection changes

## ADDED Requirements

### Requirement: Bindable Lyra rewrite command

Tinycast SHALL expose “Rewrite with Lyra” as a built-in palette command with the `sparkles` symbol and a normal command hotkey action.
The command SHALL appear in Settings under Commands and in `commands.builtIn` under the `lyra-rewrite` record name.
The command's binding SHALL use `HotKeyAction.defaultsKey`, the normal conflict checks, and the settings-file mirror.
Palette and hotkey invocation SHALL call the existing `ForkLyraCoordinator.openPanel()` entry point.
Disabled Lyra SHALL ignore the command, and the existing policy gates SHALL apply.

#### Scenario: Assign another shortcut
- **WHEN** the user records a free shortcut for Rewrite with Lyra in Settings
- **THEN** the normal hotkey manager persists the binding and the settings-file mirror exposes the shortcut
- **AND** the shortcut opens the panel when Lyra and the active policy permit rewriting

#### Scenario: Conflict with another action
- **WHEN** the user assigns a shortcut already bound to another action
- **THEN** Tinycast reports the conflict through the normal hotkey conflict checks

#### Scenario: Run from the palette
- **WHEN** the user runs Rewrite with Lyra from the palette while Lyra is enabled
- **THEN** Tinycast dismisses the palette and restores the previous app's focus before opening the rewrite panel

#### Scenario: Lyra disabled
- **WHEN** the user invokes the command while Lyra is disabled
- **THEN** Tinycast opens no panel and starts no rewrite request

### Requirement: One-time Hyper+R seed

Tinycast SHALL seed Hyper+R only when the Lyra action has no stored binding, the seed-attempt flag is unset, and no other stored action holds the chord.
The seed SHALL construct Hyper through `KeyShortcut.hyperChord(includesShift:)` using the user's Include Shift setting.
The first attempt SHALL set `fork.lyra.panelHotKeySeeded`, including attempts skipped for an existing binding or a conflict.
Later launches SHALL preserve unbinding and rebinding choices without another seed attempt.
The seed flag and binding SHALL use the app channel's UserDefaults domain.

#### Scenario: Unbound first launch
- **WHEN** the action has no stored binding or seed flag and Hyper+R is free
- **THEN** Tinycast stores Hyper+R for the Lyra command and records the seed-attempt flag
- **AND** Hyper includes Shift exactly when the user's Include Shift setting is enabled

#### Scenario: Existing binding
- **WHEN** the action has a stored binding before the first seed attempt
- **THEN** Tinycast preserves the stored binding and records the seed-attempt flag

#### Scenario: User removes the binding
- **WHEN** the seed-attempt flag is set and the action has no stored binding
- **THEN** Tinycast leaves the action unbound across launches

#### Scenario: User changes the binding
- **WHEN** the seed-attempt flag is set and the user stores another Lyra binding
- **THEN** Tinycast preserves the replacement binding across launches

#### Scenario: Hyper+R belongs to another action
- **WHEN** another stored action holds Hyper+R during the first seed attempt
- **THEN** Tinycast leaves both bindings unchanged and records the seed-attempt flag
- **AND** later release of the chord does not trigger another seed

### Requirement: Temporary Lyra card keys

Tinycast SHALL preserve Lyra's existing temporary marker and card key registrations and SHALL remove the fixed panel shortcut registration.
Temporary keys SHALL remain scoped to the visible marker or card.

#### Scenario: Dismissed card
- **WHEN** the marker and card are hidden
- **THEN** Lyra releases temporary card keys while the rewrite command retains its configured binding
