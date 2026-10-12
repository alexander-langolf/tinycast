# Notch status bar verification

Acceptance recorded on 2026-10-12 for `openspec/changes/notch-status-bar`.

## Native observations

- The signed canonical Tinycast Dev build enumerated the running Ghostty Tip build `24da727f6`.
- Two live tab cards rendered distinct Codex and Claude artwork. Detection used terminal TTY and
  foreground process-group identity, with executable signature verification; titles were labels only.
- A changing live tab title refreshed without reopening Tinycast. Long labels truncated while their
  full descriptions remained in the accessibility tree.
- Default, Large and Larger interface sizes rendered both cards and the separate launcher control
  within the resting bar. The original Large setting and Yorumi Abyss colours were restored.
- The user confirmed that physical Command-Space focuses search, accepts immediate typing and
  dismisses back to the bar. Native automation also retained all five letters of `hello`.
- The user confirmed that clicking each card selects the matching existing Ghostty tab without
  opening another tab.
- The user confirmed that `+N` overflow selects the correct tab and that closing temporary shell
  tabs updates the bar and overflow list.
- After the final restart, the formerly Claude-labelled tab showed its ordinary Ghostty icon and
  shell title while the Codex card retained its provider icon.

The initial `-1700` inventory failure came from a malformed Apple Event absolute ordinal. The
descriptor regression now checks both `typeAbsoluteOrdinal` and Foundation's native `kAEAll` bytes.
Live loading passed after that correction.

## Evidence boundaries

The running Tip app and the separately installed Ghostty release are different bundles. Capability
detection reads the running app's dictionary; older dictionaries without terminal PID/TTY show generic
icons. The generic-capability branch is covered by the harness, not by changing the user's live app.

Automated model and coordinator checks cover identity reuse, absent/ambiguous agents, misleading
titles, split terminals, bounded overflow layout, cancellation, coalescing and obsolete responses.
They do not establish native permission-denial UI, sleep/lock timing or display-removal behavior.
Those native scenarios were not repeated for this change. Existing persistent-launcher acceptance
remains documented in [persistent-launcher-verification.md](persistent-launcher-verification.md).

Native rendering was inspected in the user's Yorumi Abyss colours. Light/dark variants reuse the
existing agent-card tokens but were not separately rendered during this acceptance pass.

## Final gates

- Full suite: all 106 harnesses passed. The native launcher input harness passed again after final
  formatting and the mouse-event guard cleanup.
- Formatting: `./Scripts/format.sh --check` passed across 1,104 files after formatting the three
  launcher files that the implementation worker had left to the parent.
- Lint, model import purity, fork audit (207 documented hooks), `git diff --check` and strict
  OpenSpec validation passed. Lint permits advisory warnings; its error gate was clean.
- The canonical signed Debug build passed with no new compiler warnings. Xcode emitted its
  multiple-destination selection warning. Strict code-signature verification passed.
- The extra repository-local Dev bundle was unregistered and removed. The sole running Dev process
  uses the canonical DerivedData `Tinycast Dev.app`, restarted after the final build.

No commit or push was made for this change.

## Animation refinement

The later launcher-field refinement uses a frozen rendering of the mounted header on dismissal.
`PaletteWindowController` starts that capture before menu cleanup, window hiding and any search reset.
The travelling field keeps its own half-scale rectangle, even when the resting status cards have a
different height. Cards replace the field only when closing arrives; opening swaps at the top before
travel. The native editor stays mounted and receives input synchronously.

The native input harness checked closing image retention after a search reset, status timing,
opening reversal, immediate typing and marked-text continuity. The geometry harness checked uniform
scale with a taller resting status bar. All 106 harnesses, formatting, lint, model import purity,
fork audit, diff whitespace and strict OpenSpec validation passed. The canonical signed Debug build
passed with no Swift compiler warnings, and its app signature passed strict verification. Xcode's
App Intents metadata processor reported only its existing skipped-extraction warning.

The canonical Dev instance was restarted with this build. Native automation retained `hello` in the
focused field and dismissed back to the status cards. The user then confirmed that the revised
movement feels better. This confirmation applies to the new animation, separately from the earlier
status-card acceptance above.
