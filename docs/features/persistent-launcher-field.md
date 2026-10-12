# Persistent launcher field

Fork-owned in `Tinycast/Fork/Palette/`, owned by `AppCore.persistentLauncher`. The approved
OpenSpec change is `persistent-launcher-field`. No new preference or persisted geometry is added.

## Invariants

- Resting is a non-key, non-editable Open Tinycast button. Its neutral launcher header uses resolved
  InterfaceMetrics, the live fork scrim, fonts, corner and border tokens. The whole header scales
  uniformly to 0.5, including decoration; results, favourites, chips and retained text are excluded.
- Exactly one passive panel is created at startup. Startup does not mount RootPaletteView or start
  a palette session. Its rounded content shape and panel frame match the scaled visible bounds.
- The idle display is held until an invocation, removal or geometry change. The field is centred
  4 points below the lesser of visible-frame top and screen top minus safe-area inset. Origins
  align to backing pixels without rounding away the exact half-size dimensions.
- Click and accessibility activation request the main launcher on the field's display. Hotkeys
  preserve existing mode restoration and normal cursor/primary display selection. Cross-display
  invocation first relocates the resting endpoint and then animates on that display only.
- The real PalettePanel and its hosting tree remain mounted between invocations. The editor stays
  unscaled at the resolved active destination and receives key status at invocation. During opening
  the native window keeps alpha 1 and ignores mouse input; its content layer masks rendering while
  the passive host presents a header-only
  bitmap captured from that mounted tree, refreshed during the bounded transition to include live
  text, selection and marked composition. Search focus and preserved-query selection are established
  synchronously on summon. Snapshotting never replaces the editor or moves focus.
- Only the compact header rectangle is captured. Temporary images are released at handoff,
  dismissal, cancellation and quit. The result body/footer reveal at the destination through the
  existing motion slots. Bodies stay mounted according to their original compact/mode rules; travel
  gates opacity and hit testing rather than discarding native editor drafts. Opening a menu during travel completes the handoff before anchoring it.
- Opening and closing retarget from current presentation geometry, with transition identities
  rejecting old completions. Input-session identity survives geometry retargets and changes on a
  new summon; deferred key retries validate that identity and logical activity.
- Actual dismissal immediately ends logical activity, closes menus, orders the key panel out,
  cancels active services, restores requested focus and schedules the existing pop-to-root policy.
  Returning neutral presentation does not extend that session. Duplicate hides have no effects.
- Reduce Motion changes position and scale immediately, without a display link or staggered travel.
  Normal travel uses the centralized non-bouncing 0.34-second handoff duration and window spring.
- Display/Space/accessibility changes recompute presentation through owned observations. Sleep or
  session deactivation suppresses the passive host and ends any interactive session without focus
  restoration. Suspended/stopped requests are rejected before navigating or starting feature work.
  Wake/session activation reconciles the field without making either panel key.
  System-protected surfaces retain precedence; fullscreen behavior requires runtime verification.
- No resting move writes saved active placement. Only a real active drag can persist an anchor.
  Quit orders out both surfaces, cancels animation, timers and observers, and prevents reopening.

## Visibility and lifecycle audit

`PaletteWindowController.isVisible` now means logical session activity (opening or active).
`PaletteCoordinator.isVisible/isShowing/navigate/targetApp` inherit that boundary. The passive panel
is private and is never returned as the palette's frame, view, key window or previous target.
`PaletteState.isVisible` remains the active-service flag, never passive physical visibility.

| Consumers/routes | Boundary |
| --- | --- |
| Global toggle, mode shortcuts, open URLs, reopen, launcher/feature commands | Existing PaletteCoordinator summon routes; click requests launcher without restoreAnyMode |
| Escape/backspace/back button, drag completion, completed actions, outside click, menus | Existing navigation runs first; only hidePalette starts closing |
| FileSearch, MenuSearch, WindowSwitch and File Navigator | Logical state gates work; hide cancels once; idle does not start searches |
| Clipboard text search, preview playback and Quick Look | PaletteState active flag remains authoritative |
| Calendar, rooms, Agent Runs and input-source switching | Start/end once per logical session, independent of visual completion |
| Agent Runs child-window observation and geometry | Only settled active presentation can attach/show its child |
| Paste/selection/window actions, own-window restoration and dialogs | Active palette exposes recorded targets and destination geometry; passive host exposes none |
| Deferred first key | Validate activity plus input-session identity; preserved-query selection is synchronous |
| Drag guides and stored positions | Active drag only; presentation moves never write settings |
| Pop-to-root delay | Cancelled/consumed by existing show path; dismissal schedules once; quit cancels |

## Automated versus runtime evidence

`persistent-launcher-test` compiles the shipped policy/geometry without AppKit or SwiftUI.
It covers startup, exactly-once effects, reversals, retarget/stale completion, quit, three injected
size scales, notch/rectangular safe edges, backing alignment and held-display/removal fallback.
`persistent-launcher-lifecycle-test` compiles the real PaletteCoordinator and PaletteState with
injected effect doubles. It covers idle inactivity, seeded Search Files, preserved mode/query/row,
click-to-root, active feature navigation, Escape back, reversal and duplicate hide cancellation.
These tests do not establish native focus, rendering, Spaces or IME behavior.

Dev screenshots and user-confirmed physical acceptance complement these tests. See
[the verification report](../persistent-launcher-verification.md) for the exact evidence boundaries,
including injected display-removal tests and user-reported native behavior.

`persistent-launcher-input-test` compiles the real native panel and presentation coordinator with
injected surroundings. It checks input-window opacity, synchronous focus, retained-field input during
travel and handoff, marked-text preservation, restoration from another focused field and reduced motion.
Physical hotkey behavior remains a distinct live acceptance check.
