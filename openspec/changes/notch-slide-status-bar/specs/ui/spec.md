## ADDED Requirements

### Requirement: Launcher shows and hides without resting-field travel

Invoking the launcher SHALL present the active palette at its resolved placement, and dismissal SHALL
remove it, with no animation that carries the field to or from a resting position. No header snapshot,
uniform scale or frame interpolation SHALL run. The summon hotkey, mode restoration, immediate input
focus, Escape navigation, pop-to-root policy and focus-restoration semantics SHALL be unchanged.

#### Scenario: Invoke with hotkey
- **WHEN** the user invokes the launcher
- **THEN** the palette appears at its resolved position with the search field focused
- **AND** each immediate keystroke reaches the field exactly once

#### Scenario: Dismiss the active palette
- **WHEN** the palette is dismissed by toggle, outside click, Escape or a completed action
- **THEN** it disappears as it did before the persistent field existed
- **AND** teardown and requested focus restoration each occur once

### Requirement: Launcher shows no Agent Runs cards

The active launcher SHALL NOT present the Agent Runs card stack or its child window. The Agent Runs
feature, its data, commands and settings SHALL remain available.

#### Scenario: Open the launcher
- **WHEN** the launcher is invoked with agent runs present
- **THEN** no agent-run card appears beside or inside the launcher

## REMOVED Requirements

### Requirement: Inactive launcher remains visible at half scale
**Reason**: The resting half-scale field is replaced by the notch-anchored status bar.
**Migration**: See `notch-status-surface`.

### Requirement: Invocation moves and scales the resting field into the active palette
**Reason**: The field-to-bar travel animation is removed; the bar retracts into the notch instead.
**Migration**: See "Launcher shows and hides without resting-field travel" and `notch-status-surface`.

### Requirement: Dismissal returns to the resting field without extending the session
**Reason**: There is no resting field to return to; dismissal removes the palette and the notch bar slides out.
**Migration**: See "Launcher shows and hides without resting-field travel" and `notch-status-surface`.

### Requirement: Resting placement respects screens and Spaces
**Reason**: The resting field and its cross-display travel are removed; the notch bar is main-display only.
**Migration**: Bar placement is defined in `notch-status-surface`. Active palette placement is unchanged.

### Requirement: Transitions are interruptible and respect reduced motion
**Reason**: These guarantees covered the field travel and its clickable Open Tinycast control, both removed.
**Migration**: Interruptibility and Reduce Motion for the bar are defined in `notch-status-surface`.
