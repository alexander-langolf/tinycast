## Context

The reference is `CardC.swift` in the supplied Lyra prototype, with `Palette.swift` and `KeyCap.swift` beside the card.
Lyra provides original text, suggestion text, mode, loading state, and error text.
`ForkLyraTextSnapshot.targetText` supplies the original text for previews and rewrites.

The existing AppKit panel cannot become key or main.
The coordinator registers global keys and applies completed suggestions through the existing service or workflow callback.

## Goals / Non-Goals

**Goals:**

- Render variant C with system material and semantic colors, following the system appearance.
- Preserve keyboard behavior, host focus, marker expiry, and positioning.
- Keep applying and dismissing on the keyboard.
- Fit the panel to bounded content and retain scrolling for long replacements.

**Non-Goals:**

- Issue paging, spelling and grammar categories, or reason text.
- Model fields, prompt changes, insertion changes, or new logging.
- Upstream UI changes or shared design-system changes.

## Decisions

### 1. AppKit owns the card

The controller uses AppKit views inside the existing `ForkLyraPassivePanel`.
AppKit preserves the panel's responder contract and reuses the existing scroll-view layout.
SwiftUI hosting would add a view boundary and require another source file for this presentation-only change.
The AppKit layout reproduces the prototype's hierarchy with stack views, text fields, and capsule buttons.

### 2. The panel uses system material and semantic colors

`NSVisualEffectView` retains its active popover material.
Cards use a 14-point corner radius and a 400-point width.
The compact marker uses capsule corners.
The panel sets its appearance from the system setting (`AppleInterfaceStyle`), because Tinycast's colour theme sets `NSApp.appearance` and the card sits over another app.
The card has no mode tag and no Accept or Dismiss buttons.
Original text uses secondary label color, a red strikethrough, a 13-point font, and a two-line limit.
The replacement uses a 15-point semibold font beside `arrow.turn.down.right`.
The panel's height follows the stack's fitting size.
Replacement height stays capped at 160 points in previews and 205 points in rewrites, with vertical scrolling.

### 3. Controls preserve host focus

Capsule buttons reject first responder status and never request a key panel.
Buttons accept the first mouse click while Tinycast is inactive.
The panel retains its non-activating style and rejects key and main status.
The copy icon draws without a capsule background.
Copy writes the completed suggestion to the general pasteboard without dismissing the card.

### 4. Response state controls presentation

An absent or empty response shows a small progress indicator and "Reading your text…".
A partial response replaces the loading row with streaming text.
Copy remains disabled until a nonempty response completes.
An error replaces the replacement slot with the existing error string and keeps Copy disabled.
Changing mode clears the previous response and starts the loading state.
The coordinator retains request identity, cancellation, and destination checks.

### 5. Policy order and positioning stay authoritative

The rewrite card shows no mode controls.
Keys 1–3 select the first three modes, and arrow keys cycle through every policy mode.
The existing anchor conversion, display clamp, and vertical flip run whenever the fitting height changes.
The marker retains its eight-second expiry.

## Risks / Trade-offs

- AppKit draws the capsule backgrounds and keycaps directly, so visual parity requires a Dev app check in both appearances.
- Native focus and first-click delivery require checks in a host app.
- Localized literals use the existing localization API. Catalog synchronization requires work outside this brief's file scope.

## Verification

Claude owns the Debug build, strict OpenSpec validation, fork audit, and runtime checks.
The worker performs implementation and source review without tests, builds, typechecking, lint, or app launch.
