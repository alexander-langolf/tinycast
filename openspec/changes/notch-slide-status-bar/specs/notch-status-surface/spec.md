## ADDED Requirements

### Requirement: Status bar slides out of the notch

The status bar SHALL be attached to the top edge of the main display, centred on the notch, while no launcher session is active.
Collapsed, it SHALL occupy exactly the notch footprint and show no content. Expanded, it SHALL be
wider and taller than the notch, with a flat top flush to the screen edge, concave shoulders where
its sides meet the screen top, and rounded lower corners. Expanding SHALL animate the bar growing
downward and outward from the notch with a non-bouncing transition, revealing its content only once
the shape is settled.

#### Scenario: Start with no active launcher
- **WHEN** Tinycast finishes starting with no palette session
- **THEN** the bar slides out of the notch to its expanded shape
- **AND** the frontmost app and keyboard focus are unchanged

#### Scenario: Settled appearance
- **WHEN** the bar has finished expanding
- **THEN** it shows its icon, title and subtitle inside the expanded shape
- **AND** the shoulders join the screen top without a visible seam or gap

### Requirement: Bar reverses into the notch when the launcher is invoked

Invoking the launcher by any route SHALL play the slide animation in reverse: the content hides first,
then the bar retracts to the notch footprint. Dismissing the launcher SHALL slide the bar out again.
A new summon or dismissal SHALL retarget from the bar's current geometry without queuing a second
animation, and stale completions SHALL NOT change the latest intended state.

#### Scenario: Invoke while expanded
- **WHEN** the user invokes the launcher while the bar is expanded
- **THEN** the bar retracts into the notch as the launcher appears
- **AND** the launcher's input focus is unaffected by the retraction

#### Scenario: Dismiss the launcher
- **WHEN** the palette is dismissed by toggle, outside click, Escape or a completed action
- **THEN** the bar slides out of the notch once the launcher is gone

#### Scenario: Reverse mid-flight
- **WHEN** summon and dismissal alternate while the bar is moving
- **THEN** the bar proceeds from its current geometry toward the latest endpoint
- **AND** at most one bar is visible

### Requirement: Surface follows the menu bar

The bar's fill SHALL be a native menu-material blur, not a fixed black. A translucent menu bar SHALL
therefore show through the notch so it reads as part of the bar, and the fill SHALL follow light and
dark appearance with the menu bar. Text and icon colours SHALL come from the active appearance.

#### Scenario: Translucent menu bar
- **WHEN** the menu bar is translucent over a wallpaper
- **THEN** the bar's fill takes on the same wallpaper tint as the menu bar beside it

#### Scenario: Appearance changes
- **WHEN** the system switches between light and dark appearance
- **THEN** the bar's fill and content colours update without re-creating the surface

### Requirement: Bar is placed on the main display with a virtual notch

The bar SHALL appear only on the main display. On a display with a notch, its collapsed width and
height SHALL match the notch derived from the display's safe-area and top auxiliary areas. On a
display without a notch, a virtual notch of the same nominal width SHALL be centred at the top edge.
Placement SHALL be recomputed when displays, geometry or the main display change.

#### Scenario: Notched built-in display
- **WHEN** the main display has a notch
- **THEN** the collapsed bar covers exactly the notch and the expanded bar is centred on it

#### Scenario: External or notchless display
- **WHEN** the main display has no notch
- **THEN** the bar is centred at the top edge using the virtual notch width

#### Scenario: Main display changes or is disconnected
- **WHEN** the main display changes or is removed
- **THEN** exactly one bar exists, on the new main display, and none remains on the old one

### Requirement: Bar is non-interactive and passive

The bar SHALL NOT receive mouse events, become key or main, activate Tinycast, or change focus. It
SHALL expose its content to accessibility as read-only text and no actions. At rest it SHALL run no
animation display link and no work beyond the bounded Ghostty status observation.

#### Scenario: Click on the bar
- **WHEN** the user clicks anywhere on the bar
- **THEN** the click reaches the window beneath and nothing in Tinycast responds

#### Scenario: Idle resource use
- **WHEN** the bar is settled with no state change
- **THEN** no animation or timer runs for the bar itself

### Requirement: Bar shows one Ghostty status entry

The expanded bar SHALL show a single entry: an icon, a one-line title and a one-line subtitle. The
entry SHALL describe the selected tab of the frontmost Ghostty window using the existing Ghostty
status service. The icon SHALL be the Codex or Claude artwork only when the service has a verified
association for that tab, and the Ghostty icon otherwise. The title SHALL be the tab title and the
subtitle the tab's working-directory basename, falling back to "Terminal". Overlong text SHALL
truncate. When Ghostty is closed, has no tabs, or cannot be read, the bar SHALL show a neutral
status line and never stale tab data. The bar SHALL NOT request Automation permission.

#### Scenario: Ordinary shell tab
- **WHEN** the selected tab has no verified agent
- **THEN** the entry shows the Ghostty icon, the tab title and its directory

#### Scenario: Verified agent tab
- **WHEN** the selected tab has a verified Codex or Claude association
- **THEN** the entry shows that agent's icon with the same title and subtitle rules

#### Scenario: Ghostty unavailable
- **WHEN** Ghostty is closed, empty, denied or fails to answer
- **THEN** the entry shows a neutral status and no tab details

#### Scenario: Content changes while expanded
- **WHEN** the selected tab's title or agent changes
- **THEN** the entry updates in place without re-running the slide animation

### Requirement: Reduce Motion replaces the slide

With Reduce Motion enabled, expanding and retracting SHALL replace the geometric slide with an
immediate change to the final shape and at most a 0.15-second fade. Focus, session lifecycle and
final geometry SHALL match normal-motion behavior.

#### Scenario: Reduce Motion enabled
- **WHEN** the bar expands or retracts with Reduce Motion on
- **THEN** no growth or translation animation runs
