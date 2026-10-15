## 1. Pure models

- [x] 1.1 Add `NotchGeometry` (collapsed/expanded frames, shoulder radius, virtual notch) as an AppKit-free model with a harness covering notched, notchless, small-display and clamped cases.
- [x] 1.2 Add the two-phase notch policy with transition identity and a harness for reversal, stale completion and quit.
- [x] 1.3 Add `NotchEntry` derivation (selected tab of frontmost window, verified-agent icon rule, subtitle fallback, neutral unavailable state) and a harness; confirm what the Ghostty snapshot already exposes.

## 2. Notch surface

- [x] 2.1 Implement the mouse-transparent non-key panel at a level above the menu bar, with the menu-material effect view and shape mask; verify the working level on device.
- [x] 2.2 Implement the mask-path expand/retract animation, content fade ordering, retargeting and Reduce Motion behavior.
- [x] 2.3 Build the read-only icon/title/subtitle content view fed by the Ghostty status coordinator.
- [x] 2.4 Add `NotchBarCoordinator` owned by `AppCore`: main-display placement, screen/main-display observers, session start/end hooks, quit teardown.

## 3. Launcher and Agent Runs

- [x] 3.1 Revert palette show/hide to direct presentation and remove the header snapshot, rendering mask and frame-flight code from `PaletteWindowController` paths.
- [x] 3.2 Remove the Agent Runs card stack presentation and its palette hooks while keeping the feature, data and settings.
- [x] 3.3 Re-audit the visibility/lifecycle table: global toggle, mode shortcuts, Escape, outside click, deferred first key and quit each still behave once.

## 4. Cleanup

- [x] 4.1 Delete `PersistentLauncherCoordinator`, header, travel geometry and unused policy/presentation types plus the card, overflow, tooltip, permission-row and metrics UI; remove the Ghostty tab-selection entry point.
- [x] 4.2 Remove or rewrite the harnesses that covered deleted code; register new ones in `Scripts/run-tests.sh`; regenerate the Xcode project if files moved.

## 5. Verification and documentation

- [ ] 5.1 Native check on the notched display in light and dark and over varied wallpapers: shape seam, menu-material match, no overlap with menu bar items, slide in, reverse on invoke, rapid toggle.
- [ ] 5.2 Native check: external/notchless display, main-display change, Spaces and fullscreen, Reduce Motion, click-through, immediate typing after the hotkey.
- [x] 5.3 Update `persistent-launcher-field.md`, `ghostty-tab-status.md`, `agent-runs.md`, `docs/fork.md` and the verification record; mark the `notch-status-bar` change superseded.
- [x] 5.4 Run `./Scripts/run-tests.sh`, lint, model purity check, fork audit, OpenSpec validation and a Debug build with no new warnings.
