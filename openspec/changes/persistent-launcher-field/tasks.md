## 1. Presentation policy and integration boundaries

- [x] 1.1 Audit palette physical-visibility consumers, all summon/dismiss routes, focus restoration, pop-to-root timers and active feature hooks; identify which require logical session activity.
- [x] 1.2 Implement a pure resting/opening/active/closing transition policy with identities and exactly-once session effects; cover startup, reversal, stale completion and quit in the standalone harness.
- [x] 1.3 Implement pure half-scale/safe-edge geometry using injected display frames, safe insets and resolved metrics; test notched/rectangular displays, scale factors, saved active placement and removal fallback.

## 2. Passive field and owned lifecycle

- [x] 2.1 Add the fork-owned passive host and AppCore-owned presentation coordinator; wire startup, display/Space observation and teardown without starting active palette work.
- [x] 2.2 Render the neutral launcher header with shared appearance at uniform 0.5 scale and exact visible hit bounds; exclude results, favourites, chips and retained text.
- [x] 2.3 Route click and accessibility activation through the main-launcher summon path; expose Open Tinycast without making the idle panel key or editable.
- [x] 2.4 Separate logical palette activity from passive visibility in the audited callers; preserve search cancellation, clipboard/input-source session boundaries and previous-app capture.

## 3. Coordinated transition and active behavior

- [x] 3.1 Add centralized uniform-scale/translation motion and a single-visible-header handoff at the existing active destination; support compact/full active geometry and direct feature entry.
- [x] 3.2 Give the real input focus at invocation and keep transitional text synchronized; verify that handoff neither drops typed characters nor resets query/selection/first responder.
- [x] 3.6 Guard deferred key retries, resign-key dismissal re-entry, active feature anchors/child windows and saved-placement writes against stale or passive presentation; verify IME marked text and candidate placement.
- [x] 3.3 Integrate reverse dismissal with neutral header rendering, exactly-once teardown/focus restoration and existing Escape/pop-to-root semantics.
- [x] 3.4 Retarget in-flight transitions by identity and current geometry, including geometry/theme/font updates; stop display links and release temporary presentation resources at rest or cancellation.
- [x] 3.5 Implement Reduce Motion immediate geometry with optional short fade, keeping session and focus behavior identical.

## 4. Displays, documentation and verification

- [x] 4.1 Verify one idle field across cursor/primary policies, mixed-resolution displays, display removal, Space changes, fullscreen and menu-bar auto-hide; correct public AppKit window behavior as needed.
- [x] 4.2 Run focused policy/geometry/lifecycle harnesses for all new requirements, including idle inactivity, direct feature invocation, restoration and rapid summon/dismiss reversal.
- [x] 4.3 In Tinycast Dev, capture resting/opening/active/closing evidence over light and dark desktops with adaptive and custom themes and all three Interface Sizes; verify visual scale, safe top placement, no duplicate fields, immediate typing and reduced motion.
- [x] 4.4 Verify outside-click and action-completion focus behavior, menus/dialogs, File Navigator, Quick AI and clipboard workflows; confirm the idle field does not expose retained feature text or keep active-only work running.
- [x] 4.5 Update palette, appearance and motion documentation for the delivered behavior. Regenerate the Xcode project if project.yml changes; preserve the protected scrolling primitives.
- [x] 4.6 Run ./Scripts/run-tests.sh, ./Scripts/lint.sh, the model-import purity check and a Debug build with no new warnings, plus the applicable fork audit from repository guidance. Record runtime evidence separately from static checks.

## Implementation evidence (2026-10-12)

- All 104 harnesses pass in the direct host run (`build/PersistentLauncherFinal/tests.log`).
- Debug build, lint, model purity, fork audit and OpenSpec validation pass.
- A new real-AppKit input harness covers immediate key input, synchronous focus, retained selection
  and marked text, handoff, hidden native-editor focus and Reduce Motion.
- The user reproduced lost typing after physical Command-Space. The corrected build keeps native
  window alpha at 1, masks only rendering, and establishes focus/selection synchronously.
  The user then confirmed physical immediate typing and dismissal both work.
- Live click activation, neutral dismissal, three sizes, adaptive Light/Dark and custom theme,
  File Navigator/actions, Clipboard History and Quick AI were checked. Original preferences restored.
- Native acceptance combines endpoint screenshots, real-AppKit regression tests and user observation.
  The user confirmed Spaces/fullscreen, outside-click and applicable external-display/IME checks.
  Display-removal geometry and Reduce Motion are covered by injected native/geometry tests, not
  claimed as physical unplug or system-setting tests. No frame-by-frame recording was captured.
  See `docs/persistent-launcher-verification.md` for the evidence boundaries.
- No commit, push, new worktree or archive was performed. Existing OpenSpec baselines preserved.
