# Persistent launcher verification

2026-10-12. Implemented in the existing checkout using Sol. Uncommitted; no push, archive,
new worktree, dependency installation or browser control. Existing OpenSpec baselines and
protected scrolling sources are preserved.

## Behavior

The neutral launcher field rests at uniform 0.5 scale below the safe top edge. Click/accessibility
activation and existing hotkeys open the real mounted editor at its existing destination through
a bounded scale/translation animation. Dismissal ends the logical session immediately and returns
the neutral field. Idle presentation does not expose retained text or run active feature work.

The first live physical-hotkey test exposed lost typing. The correction keeps the native window
at alpha 1, masks only its content layer and shadow, and establishes search focus and preserved-query
selection synchronously. The user confirmed that immediate typing and dismissal both work after
restarting the corrected build. Handoff never replaces or reselects the native editor.

## Automated evidence

| Check | Result and log |
| --- | --- |
| Full suite | All 104 harnesses passed; `build/PersistentLauncherFinal/tests.log` |
| Debug build | Succeeded with the normal compiler settings; `build/PersistentLauncherFinal/build.log` |
| Lint | Passed; existing warning-only diagnostics remain; `build/PersistentLauncherFinal/lint.log` |
| Fork audit | Passed; `build/PersistentLauncherFinal/fork-audit.log` |
| Model import purity | No prohibited imports; `build/PersistentLauncherFinal/purity.log` |
| Whitespace | `git diff --check` passed |
| OpenSpec | Strict validation passed |

The build emits the existing AppIntents metadata extraction notice, with no Swift source warnings.
The direct host build avoids the delegated sandbox's Icon Composer/XPC service restriction.
No checked-in sandbox workaround or compiler setting was added.

The pure policy/geometry harness covers identities, reversals, stale completion, safe edges,
three interface scales, backing alignment and display fallback. The lifecycle harness compiles
real coordinator sources with injected effects. The native-input harness compiles the real panel
and presentation coordinator: first-key delivery during travel, synchronous focus from another
field, unchanged editor identity, marked text/selection across handoff and Reduce Motion.

Three previously failing harnesses were repaired while retaining their assertions:

- Form rendering measured bright pixels only and missed black Aqua text. Alpha-based ink bounds
  now check both Aqua and Dark Aqua with the existing baseline/alignment assertions.
- Settings search omitted Automation anchor declarations because they lived in a SwiftUI view file.
  The shared declarations now have their own feature-owned file, compiled by the harness.
- Icon rows fetched a second native icon instead of resizing the cached full-size raster. Rows now
  use the same captured source; exact-byte assertions pass on the host.

## Live evidence

The Dev application was cleanly restarted via Activity Monitor, then launched from the built app.
The final direct host product is `build/PersistentLauncher/Build/Products/Debug/Tinycast Dev.app`.

- One resting Open Tinycast accessibility button, with no editable field or retained query.
- Click activation, immediate ASCII typing, select-all, Unicode paste and neutral Escape dismissal.
- Default, Large and Larger resting headers without clipping. Larger captures are 900 pixels wide
  at rest and 1800 pixels wide at the active compact destination.
- Adaptive Light and Dark resting/active headers, plus the custom Yorumi Abyss theme.
- Original Large size, System appearance and Yorumi Abyss theme restored after testing.
- File Navigator path entry and its actions menu; Clipboard History and Quick AI focus/dismissal.
  No AI prompt was submitted and no clipboard content was exposed in the report.
- Immediate click/Escape returns to one resting field.
- User-confirmed physical Command-Space, immediate typing of hello, and return to top on dismissal.

## Acceptance evidence boundaries

App-targeted synthetic keys do not exercise the global hotkey, so physical user confirmation is
recorded separately. After confirming typing and dismissal, the user also confirmed the requested
Spaces/fullscreen, outside-click, and applicable external-display/IME checks worked. This is
user-reported evidence, not an automated observation of IME candidate windows or display hardware.

The display-removal fallback, notch/visible-frame geometry and Reduce Motion behavior are established
by injected geometry/native tests. No physical unplug test or frame-by-frame animation recording was
captured. Endpoint screenshots and the user's motion observation establish the live visual result.
Acceptance is complete for this delivery with those evidence boundaries; all 19 OpenSpec tasks are
checked. No archive or commit was requested.

The final native-input and changing-icon-source regression reruns also pass after the last edits:
`build/PersistentLauncherFinal/input-final.log` and `icon-cache-final.log`.
