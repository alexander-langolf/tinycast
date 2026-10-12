## ADDED Requirements

### Requirement: Inactive launcher remains visible at half scale

While Tinycast is running in ordinary unlocked desktop use, the inactive launcher SHALL present one
main-launcher field at uniform visual scale 0.5. The field SHALL contain the launcher search glyph
and neutral placeholder, centred horizontally 4 points below the selected display's menu/notch-safe
top boundary. It SHALL scale resolved normal header geometry, typography and decoration together,
and SHALL NOT display results, favourites, auxiliary chips, footer or a retained query.

#### Scenario: Start without invoking the launcher
- **WHEN** Tinycast finishes starting with no active palette session
- **THEN** the half-scale field appears without changing the frontmost app or keyboard focus
- **AND** no interactive palette session is started merely to display it

#### Scenario: Appearance or interface size changes
- **WHEN** the current theme, font, size or applicable header token changes while resting
- **THEN** the resting field updates and remains half the resolved normal header size

### Requirement: Invocation moves and scales the resting field into the active palette

The existing summon hotkey and clicking or accessibility-activating the resting field SHALL invoke
the palette. Normal-motion invocation SHALL animate uniform scale from 0.5 to 1.0 and translation
to the existing active placement using a non-bouncing 0.34-second transition. Only one perceived
launcher field SHALL be visible, and results/body SHALL reveal at the destination.

#### Scenario: Invoke with hotkey
- **WHEN** the user invokes the resting launcher with its hotkey
- **THEN** it transitions to normal scale at the existing resolved palette position
- **AND** active compact/full presentation and existing mode-restoration rules are preserved

#### Scenario: Click the resting field
- **WHEN** the user clicks or accessibility-activates the resting field
- **THEN** the main launcher opens on the field's display using the same transition

#### Scenario: Type during opening
- **WHEN** the user types immediately after invocation while the transition is running
- **THEN** the real palette accepts each keystroke once
- **AND** the travelling launcher header reflects that input without dropping or resetting it at handoff

#### Scenario: Open a feature directly
- **WHEN** an existing feature command or shortcut opens a non-launcher mode from rest
- **THEN** its mode, seed input and destination are preserved
- **AND** the resting representation yields to that active palette without a second visible field

### Requirement: Dismissal returns to the resting field without extending the session

An actual palette dismissal SHALL end the active session and return its header presentation to the
half-scale top position. Existing Escape navigation, pop-to-root policy, action completion and
focus-restoration semantics SHALL remain authoritative. The resting surface SHALL NOT count as an
active palette, accept text input or retain active-only search, input-source or feature work.

#### Scenario: Dismiss the active palette
- **WHEN** the palette is dismissed by its existing toggle, outside-click, Escape or completed action
- **THEN** active content is removed and the neutral header returns to the resting position
- **AND** teardown and requested focus restoration each occur once independently of animation completion

#### Scenario: Escape only navigates back
- **WHEN** existing Escape behavior closes a menu or navigates within the active palette
- **THEN** the palette stays active and does not return to rest until that behavior actually dismisses it

#### Scenario: Quit
- **WHEN** Tinycast terminates
- **THEN** resting, active and transitional surfaces and their owned observers are removed

### Requirement: Resting placement respects screens and Spaces

The feature SHALL maintain one resting field across available displays, initially using the existing
cursor-display/primary-display preference. It SHALL keep its display while idle, resolve hotkey
activation on the normal target display, and rest on the active display after dismissal. Cross-display
activation SHALL relocate the resting endpoint before animating locally rather than travel through
the space between displays. Idle geometry SHALL NOT overwrite saved active palette placement.

#### Scenario: Invoke on another display
- **WHEN** the normal hotkey target display differs from the resting field's display
- **THEN** one field transitions on the target display and none remains on the previous display

#### Scenario: Notch, display geometry or availability changes
- **WHEN** a display has a notch, changes usable geometry or is disconnected
- **THEN** resting placement is recomputed inside an available safe screen area
- **AND** the field does not occupy the reserved menu/notch region

#### Scenario: Change desktop Space or enter fullscreen
- **WHEN** the user changes Space, including an ordinary fullscreen Space
- **THEN** the resting field remains available on the active Space without switching focus or Spaces
- **AND** system-modal, lock and other OS-protected surfaces retain precedence

### Requirement: Transitions are interruptible and respect reduced motion

New summon/dismiss requests SHALL retarget from the current presentation without queuing duplicate
transitions. Stale completion callbacks SHALL NOT change the latest intended state or focus.
Reduce Motion SHALL replace geometric travel with an immediate position/scale update and at most
a 0.15-second fade. The resting field SHALL expose an Open Tinycast accessibility action and SHALL
have no hit-test area outside its visible bounds.

#### Scenario: Rapidly reverse direction
- **WHEN** summon or dismissal reverses an in-flight transition
- **THEN** the presentation proceeds from its current geometry toward the latest requested endpoint
- **AND** only one active session and one perceived field remain

#### Scenario: Reduce Motion enabled
- **WHEN** invocation or dismissal occurs with Reduce Motion enabled
- **THEN** no scale/translation animation or stagger runs
- **AND** focus, session lifecycle and final geometry match normal-motion behavior

#### Scenario: Resting resource use
- **WHEN** the field is resting without relevant input or configuration changes
- **THEN** it runs no animation display link, repeated search refresh or active feature session
