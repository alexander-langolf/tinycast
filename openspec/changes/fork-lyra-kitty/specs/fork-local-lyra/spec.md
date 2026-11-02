## ADDED Requirements

### Requirement: Kitty remote-control selection

Tinycast SHALL read the frontmost kitty application's selection through a dedicated `ForkSelectionSource` adapter when the Lyra rewrite command runs.
The adapter SHALL recognise bundle ID `net.kovidgoyal.kitty` and resolve kitten from the running application's bundle URL.
The adapter SHALL invoke kitten directly with `@ --to unix:/tmp/kitty.sock-<pid> get-text --match state:focused --extent selection`.
The process identifier SHALL belong to the frontmost kitty application captured at invocation.
Lyra SHALL use the captured remote-control text as the original without reading kitty's Accessibility value.
The adapter SHALL remain outside the shared quick-action selection chain.

#### Scenario: Rewrite a terminal selection
- **WHEN** the user selects text in the focused kitty window and invokes Rewrite with Lyra
- **THEN** Lyra reads that selection through the captured kitty process's socket
- **AND** the card shows the captured selection as the original and streams the selected policy mode's rewrite
- **AND** no Accessibility value supplies the original text

### Requirement: Bounded selection reads and failure feedback

Tinycast SHALL limit the kitty remote-control read to approximately one second and SHALL cancel and reap its owned child process.
An empty or whitespace-only selection SHALL show “Select text in kitty first” without opening a card.
A failed read SHALL show “Lyra can't read kitty's selection” without opening a card.
Cancellation or a changed destination SHALL discard the read result without presenting stale content.
Selection traces SHALL contain only text length, bundle ID, and numeric error code as read metadata.
Logs SHALL exclude selection text, rewrite text, and socket contents.

#### Scenario: No terminal selection
- **WHEN** kitty returns an empty selection
- **THEN** Lyra shows the selection HUD and leaves the card hidden

#### Scenario: Remote control fails
- **WHEN** the socket is unavailable, kitten fails, or the deadline expires
- **THEN** Lyra shows the read-failure HUD and leaves the card hidden
- **AND** the selection trace records a numeric error code without terminal text

#### Scenario: Selection request becomes stale
- **WHEN** the user changes the frontmost application or dismisses a pending request
- **THEN** Lyra cancels the owned read and discards its result

### Requirement: Copy-only terminal delivery

Tinycast SHALL present kitty rewrites in Copy-only mode and SHALL never type or paste a rewrite into kitty.
Return and keypad Enter SHALL copy a completed rewrite to the general pasteboard and dismiss the card without invoking application.
The copy icon SHALL copy the completed rewrite and keep the card visible.
Loading, partial responses, and errors SHALL disable copying and application.
The plain-text rewrite path SHALL expose no apply option, and Lyra's insertion boundary SHALL reject kitty targets.
The headless rewrite tool SHALL reject kitty before reading Accessibility text.

#### Scenario: Accept a completed terminal rewrite
- **WHEN** the user presses Return or keypad Enter after a kitty rewrite completes
- **THEN** the general pasteboard contains the completed rewrite and the card closes
- **AND** no apply callback, paste action, or simulated keystroke runs

#### Scenario: Copy with the icon
- **WHEN** the user clicks the copy icon on a completed kitty rewrite
- **THEN** the general pasteboard contains the completed rewrite and the card stays visible

#### Scenario: Response is incomplete
- **WHEN** the kitty rewrite is loading, streaming, or showing an error
- **THEN** Return and the copy icon leave the pasteboard unchanged and never apply text

### Requirement: Pointer placement for kitty

Tinycast SHALL anchor the kitty rewrite card near the mouse position captured at invocation in AppKit coordinates.
The card SHALL flip above the pointer when needed and SHALL clamp inside the pointer display's visible frame.
Streaming height changes SHALL retain the captured pointer anchor without using kitty element bounds.

#### Scenario: Pointer on a secondary display
- **WHEN** the user invokes a kitty rewrite with the pointer on a secondary display
- **THEN** the card appears near that pointer and stays inside that display's visible frame during streaming

### Requirement: No automatic terminal Fix

Tinycast SHALL disable Fix on pause in kitty independently of policy text limits.
The focus observer SHALL exclude kitty before reading Accessibility text or subscribing to field changes.

#### Scenario: Permissive Fix policy
- **WHEN** a custom Fix policy accepts kitty's short prompt glyph
- **THEN** Lyra produces no automatic Fix request or marker in kitty
