## ADDED Requirements

### Requirement: Variant C suggestion cards

Tinycast SHALL present Lyra previews and rewrites with the variant C hierarchy using original text, suggestion text, mode, loading state, and error.
Each card SHALL show original text with a red strikethrough and a replacement beside a turning arrow, with a plain copy icon at the end of the replacement row.
Original text SHALL use a 13-point font and at most two lines.
Replacement text SHALL use a 15-point semibold font.
Cards SHALL use system material and a 14-point corner radius.
Cards SHALL follow the system light or dark appearance, independent of Tinycast's colour theme, because they sit over another app.
Cards SHALL omit a mode tag, Accept and Dismiss buttons, issue paging, spelling and grammar categories, and reason lines.

#### Scenario: Fix preview
- **WHEN** the user presses Tab while a completed Fix marker is visible
- **THEN** the preview shows the captured snapshot's target text as the original and the completed fix as the replacement

#### Scenario: Rewrite card
- **WHEN** the user opens the rewrite panel
- **THEN** the original text comes from the captured snapshot's target text

### Requirement: Passive copy click

Tinycast SHALL make the copy icon clickable without taking focus from the host app.
The panel SHALL remain non-activating and SHALL reject key and main status.
Buttons SHALL accept the first mouse click without requiring the panel to become key or becoming first responder.
Copy SHALL put the completed suggestion on the general pasteboard and SHALL keep the card visible.
Copy SHALL remain disabled during loading, streaming, and errors.
Applying and dismissing SHALL stay on the keyboard: Tab, Return and Escape.

#### Scenario: Copy by mouse
- **WHEN** the user clicks the copy icon on a completed suggestion while the host app has focus
- **THEN** the general pasteboard contains the suggestion and the card remains visible
- **AND** Tinycast does not activate

### Requirement: Keyboard-only rewrite modes

Tinycast SHALL show no mode controls on the rewrite card and SHALL preserve existing keyboard behavior.
Keys 1–3 SHALL select the first three modes, and arrow keys SHALL cycle through all modes.
Tab SHALL open a marker's preview and SHALL apply a completed preview.
Return and keypad Enter SHALL apply a completed rewrite, and Escape SHALL dismiss every visible Lyra surface.

#### Scenario: Switch modes
- **WHEN** the user presses a supported number key or an arrow key
- **THEN** the coordinator selects the corresponding mode and starts a replacement request
- **AND** arrow keys reach every policy mode

### Requirement: Rewrite response states

Tinycast SHALL show "Reading your text…" with a small progress indicator until the rewrite produces nonempty partial text.
The replacement slot SHALL display partial text as the coordinator receives the stream.
A completed response SHALL enable Copy only when the response is nonempty.
The error state SHALL preserve the existing error string and SHALL prevent application or copying of error text.

#### Scenario: Stream a rewrite
- **WHEN** a rewrite request starts
- **THEN** the card shows the loading row and disables Copy
- **WHEN** the first nonempty partial response arrives
- **THEN** the replacement slot shows the partial response and the loading row disappears
- **WHEN** the response completes
- **THEN** Copy becomes available for the completed suggestion

#### Scenario: Rewrite fails
- **WHEN** the rewrite request fails without cancellation
- **THEN** the card displays "The rewrite could not be completed. Check Lyra settings and the focused field."
- **AND** Copy remains disabled
- **AND** Escape and mode switching remain available

### Requirement: Marker lifetime and bounded positioning

Tinycast SHALL present the Fix marker as a small capsule with sparkles, Fix, and a ⇥ keycap and SHALL retain its eight-second expiry.
The panel SHALL fit its content at a card width between 360 and 440 points.
Replacement height SHALL remain capped with scrolling for longer text.
The panel SHALL retain the existing anchor conversion, display clamp, and vertical flip when its fitting size changes.
Lyra logs SHALL contain no original text or suggestion text.

#### Scenario: Long suggestion near a display edge
- **WHEN** a long replacement expands a preview or rewrite near the bottom of a display
- **THEN** replacement height stops at the existing cap and the text scrolls
- **AND** the panel flips above the anchor when needed and stays inside the visible display frame

#### Scenario: Marker expires
- **WHEN** a Fix marker remains visible for eight seconds without opening a preview
- **THEN** the existing dismiss callback closes the marker
