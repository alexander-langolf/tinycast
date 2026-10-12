## Context

The supplied references show a small top-centred pill in the Droppy position and the normal launcher
below it. They are interpreted as endpoints of one continuous presentation, not two simultaneous
interactive launchers. The user confirmed click and hotkey activation and the proposed placement just
below the menu bar/notch. The resting field is half-size; the active destination remains Tinycast's
existing position on the selected screen.

Current source at `9f065751`:

- `PaletteCoordinator.togglePalette` and `isShowing` use window visibility to decide whether to hide.
- `PaletteWindowController.show` captures the previous app/paste target, prepares input-source and
  feature sessions, makes the panel key and starts active-palette services. `hide` tears these down,
  orders the panel out, restores focus as requested and schedules existing state restoration rules.
- `positionPanel` resolves cursor/primary display, saved placement, compact/full height, palette chips
  and expanded file-browser geometry. `PaletteFrameAnimator` changes frame/radius; it does not uniformly
  scale glyphs or text. Resizing a frame alone therefore cannot deliver the requested half-scale field.
- `RootPaletteView` contains mode-specific input and results. It is too heavy and stateful to keep
  running merely to draw an idle field. Theme and font changes can rebuild its hosting tree.

The existing `ui`, `search` and `file-browser` baselines remain current-state records. This change
adds a UI delta; it does not rewrite them to pretend the requested behavior already exists.

## Goals / Non-Goals

**Goals:**

- An always-present main-launcher field at 0.5 uniform visual scale while Tinycast is running and idle.
- A coherent scale-and-position transition to the full-size interactive launcher, reversible on dismissal.
- Click and existing hotkey activation; no focus or input capture while resting.
- Correct themes, sizes, displays, Spaces, Reduce Motion and interruption behavior.
- Preserve active feature sessions, placement, mode restoration and focus contracts.

**Non-Goals:**

- A second search session, live idle search, a notch replacement, or a new launcher design.
- Changing ranking, compact-mode defaults, saved placement or feature-specific presentation.
- Pinning every feature's input to the top, multiple persistent pills, hover expansion or a new setting.
- Screen dimming from the reference image; the reference establishes position and scale only.

## Decisions

### Presentation state is separate from logical palette activity

Use one AppCore-owned presentation owner with explicit `resting`, `opening`, `active`, `closing`
states and transition identity. Keep palette session visibility/activity false while resting. Existing
public show/hide entry points remain authoritative for session startup, teardown and focus restoration.
Audit callers of both `PaletteState.isVisible` and controller/window `isVisible`; a passive panel's
physical visibility must never masquerade as an active session.

```text
resting -- click / summon --> opening --> active
   ^                            |          |
   |                            | dismiss  | dismiss / action completes
   +----------- closing <-------+----------+
                    |
                    +-- summon --> opening (retarget current presentation)
```

The active session begins once per summon, and teardown runs once per dismissal. Visual completion
does not own those semantics. Late animation callbacks cannot restore a stale state or steal focus.
Quit removes all surfaces rather than producing a resting field.

In particular, gate the deferred first-key retry in `show()` by session identity, not native window
visibility. Dismissal must relinquish key status even with `restoreFocus: false`, without re-entering
hide through resign-key callbacks. `targetApp`, `visibleFrame`, `anchorView`, dialog dimming and Agent
Runs child-window updates require explicit active-session semantics. Guard programmatic animation
moves from `windowDidMove` persistence so they cannot replace the user's saved active anchor.

### Passive host with a coordinated header handoff

Keep the interactive palette's existing controller and lifecycle. Add a lightweight, non-key passive
panel and a fork-owned presentation host under AppCore ownership. Its content uses the same launcher
field appearance/metrics, with a neutral search glyph and placeholder, not the retained live query.
Factor only the rendering needed to maintain visual parity; do not mount another RootPaletteView or
duplicate the interactive field editor. No feature content is copied into DesignSystem.
Keep the existing interactive search field mounted in its host throughout this presentation change;
the passive renderer is not a second editor and must not replace that host on each invocation.

Animate the presentation header at full layout resolution with a uniform transform from 0.5 to 1.0,
coupled with screen-space translation. Frame/clip geometry must follow the transformed bounds so it
does not create a full-size invisible hit region. Coordinate a pixel-aligned handoff to the real header;
there must be only one visible header at each transition stage. Rendering snapshots, if required for
the brief handoff, must be confined to the launcher header and released at completion/cancellation.

The real palette owns keyboard input as soon as invocation begins, allowing immediate typing without
losing characters. The transition representation must follow newly typed launcher text until handoff;
never reset query or first responder on completion. Keep result/feature body hidden during travel,
then reveal at the destination using existing motion. An opening directly into another feature uses
its normal destination/mode; it must not reset that mode to launcher merely to perform the animation.

Alternatives considered:

1. **Reuse the entire live palette while idle:** simpler window count, but visibility gates, field editor,
   background sessions and retained content become coupled to idle presence. Rejected.
2. **Independent decorative pill with unrelated palette fade:** easy isolation, but visibly duplicates
   the field and loses the requested continuous scale/translation. Rejected.
3. **Passive host plus coordinated handoff:** selected; contains idle behavior while reusing the active
   lifecycle, at the cost of explicit transition coordination and handoff verification.

### Geometry and display policy

Resting dimensions are exactly 0.5 times the normal launcher input bar's width and compact header
height after Interface Size and applicable token resolution. Scale typography, glyphs, padding,
radius and border together; do not simulate this using only smaller fonts or a narrower frame.
Exclude favourites, attached chips, result body and footer from the resting bar.

Centre horizontally on the selected display. Place its top at the lesser of the display visible-frame
top and the notch-safe top derived from screen frame/safe-area insets, with a 4-point gap below that
boundary. Clamp to available screen bounds. This places it below reserved menu/notch space rather
than over menu items. Keep placement geometry pure by injecting screen rectangles/insets and metrics.

There is exactly one resting field. Initially use Tinycast's cursor-display/primary-display preference.
Hold that display while idle rather than following every mouse move. On hotkey activation, resolve
the normal target screen; when it differs, relocate the resting endpoint there without animating
across physical displays, then perform the local transition. Clicking anchors that invocation to the
clicked bar's display. After dismissal, dock on the active session's display. Display removal falls
back to the configured available display; screen geometry changes recompute endpoints.

The passive field follows the active Space and can accompany a fullscreen Space using public AppKit
panel collection behavior. It does not activate a Space or cover system-modal/lock surfaces. “Always”
means ordinary unlocked application use, not drawing over OS-protected UI. The screen-safe placement
must work on both notched and rectangular displays.

Active destination is still resolved by existing placement rules, including saved user position and
compact/full behavior. A resting position is never written into saved active-position preferences.

### Dismissal and input

The passive field is an accessible Open Tinycast button, not an editable field. Click, accessibility
activation and hotkey enter the existing summon path. Resting does not become key, change the
frontmost app or start input-source switching. Hit-testing is limited to the visible pill.

Existing Escape/back-navigation semantics run first. Only an actual hide/dismissal starts returning
to rest. Close action menus/auxiliary presentation and hide the results before the travelling header;
return with neutral placeholder rather than showing clipboard/AI/file or other retained query content.
Preserve hidden-session data only according to the existing pop-to-root setting. Clicking the dock
requests the main launcher; the existing hotkey keeps its established restore-any-mode behavior.

### Motion, accessibility and live appearance

Use a centralized 0.34-second non-bouncing transition for uniform scale and translation, sharing
the existing motion policy. Retarget from the current presentation when interrupted instead of
queueing animations or jumping back to an endpoint. No periodic idle animation or display link runs.
Reduce Motion uses an immediate position/scale change with at most the existing 0.15-second fade.
Theme/font/size edits update idle rendering and recompute in-flight geometry without duplicating hosts.

## Risks / Trade-offs

- [Physical visibility leaks into activity] → Audit every visibility consumer and test idle sessions,
  hotkey toggling, search cancellation, clipboard monitoring and focus restoration explicitly.
- [Two hosts flash or diverge] → Match shared metrics and screen-space header bounds; verify opening,
  closing, immediate typing and rapid reversals frame by frame in Dev.
- [AppKit field-editor scaling/focus] → Transform a presentation header, not a live scaled editor;
  keep one real input owner and no animation-completion focus reset.
  Validate IME marked text and candidate-window placement during opening, not only Latin typing.
- [Notch/Spaces/platform behavior] → Use public geometry and window APIs; manually verify fullscreen,
  menu-bar auto-hide, mixed scale displays and display removal before declaring acceptance.
- [Idle power/resource use] → No repeated search refresh, feature lifecycle or animation timer while
  resting. Observe relevant screen/theme events through an owned, torn-down subscription.
  Reconcile presentation after sleep/wake and lock/unlock without stealing focus.
- [Half-scale legibility] → Preserve the exact requested scale and an accessible action name; no text
  entry at half scale. Styling and contrast remain the active theme's responsibility.

## Migration Plan

No stored-setting migration or new preference is required. Implement in the Dev channel, retaining
the current active-state behavior. Run focused geometry/lifecycle tests, repository verification and
the rendered acceptance matrix before delivery. Rollback removes the new idle presentation wiring
and restores full hiding, without rewriting saved geometry, themes or search state.

## Open Questions

No blocking product questions remain for this proposal. Click activation is confirmed. The 4-point
safe-edge gap, single-display idle policy and reverse transition are proposed defaults made explicit
here for review. Pixel alignment and AppKit fullscreen behavior require implementation-time evidence.
