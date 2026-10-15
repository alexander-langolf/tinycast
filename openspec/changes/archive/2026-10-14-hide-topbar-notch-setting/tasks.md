## 1. Preference and settings plumbing

- [x] 1.1 Add `notchBarEnabled` (default `false`) to `AppSettings` and `AppSettingsKey`, marked `// FORK: notch-bar`, persisted under the existing bundle-keyed defaults
- [x] 1.2 Add a `SettingsFileKey` case (`notchBar.enabled`) and bind it in `SettingsFileSchema`, so the exhaustive switch builds
- [x] 1.3 Classify the key in `SettingsBackupCoverage` and carry it through `SettingsBackup` (export and import), since it grants no capability
- [x] 1.4 Add the "Show notch bar" toggle to the General pane next to "Show in menu bar", plus a `SettingsSearchCatalog` entry so it is findable

## 2. Notch bar coordinator

- [x] 2.1 Extract one teardown helper from `NotchBarCoordinator.stop()` covering observers, appearance observation, backdrop task, probe, panel and surface
- [x] 2.2 Add `hide()`: run the teardown helper, call `core.ghosttyStatus.stop()` and reset `policy` to a fresh `NotchPolicy()`; keep `stop()` as the terminal shutdown path
- [x] 2.3 Make `start()` call `core.ghosttyStatus.start()` and retract immediately when `core.palette.isVisible` is true, so a bar enabled during an open palette session does not sit expanded
- [x] 2.4 Add `applyEnabled()` that shows or hides from `core.settings.notchBarEnabled` and is idempotent
- [x] 2.5 In `AppCore`, replace the unconditional `ghosttyStatus.start()` and `notchBar.start()` with a `track({ _ = $0.notchBarEnabled }, reproject: { $0.notchBar.applyEnabled() })` entry in `observeFeatureSwitches()`, keeping the `FORK: notch-bar` markers

## 3. Tests

- [x] 3.1 Extend `Tests/notch-test.swift`: after `stop()` the policy stays terminal, and a fresh policy after a hide accepts new transitions and rejects an identity captured before the hide
- [x] 3.2 Extend `Tests/settings-backup-test.swift` so `notchBarEnabled` is asserted as carried
- [x] 3.3 Run `./Scripts/run-tests.sh` and confirm it passes, including the settings-file and backup harnesses

## 4. Docs

- [x] 4.1 Update `docs/features/notch-bar.md`: off by default, the Settings toggle, live show and hide, and that Ghostty polling follows the bar
- [x] 4.2 Update `docs/fork.md` for the moved `ghosttyStatus.start()` call and the new `AppCore` tracking entry
- [x] 4.3 Update `docs/features/settings-file.md` if it lists keys

## 5. Verification

- [x] 5.1 Build the Debug app with no new warnings, then run `./Scripts/lint.sh` and the `Features/*/Model/` import grep from `AGENTS.md`
- [x] 5.2 In `Tinycast Dev`, check: fresh defaults show no bar; toggling on shows it; toggling off removes it; five rapid toggles leave one bar; the palette opens normally with the bar hidden
- [x] 5.3 Check enabling the bar while the palette is open, and that a relaunch keeps the preference
- [x] 5.4 Confirm Ghostty polling is idle while the bar is hidden
