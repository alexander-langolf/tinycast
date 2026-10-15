## Why

The notch bar (the passive panel at the top of the primary display that shows the selected Ghostty
tab) is always on once Tinycast starts. Not everyone wants a permanent overlay above the menu bar,
and today the only way to get rid of it is to stop the app.

## What Changes

- Add a "Show notch bar" preference in Settings that controls whether the notch bar is shown.
- The preference defaults to **off**: a fresh install, or an existing install that has never set it,
  no longer shows the notch bar. This changes today's behaviour for existing users.
- Turning the preference on shows the bar immediately and turning it off removes it immediately, with
  no relaunch. While it is off, the bar creates no panel and no menu-bar probe, and Ghostty polling
  does not run on its behalf.
- The preference gets a `SettingsFileKey` and a `SettingsFileSchema` binding so the opt-in
  `settings.json` mirror carries it, and a place in the settings backup coverage.

## Capabilities

### New Capabilities
- `notch-bar-visibility`: the user-controlled, default-off preference that decides whether the notch
  bar exists, including live show and hide, persistence and the `settings.json` mirror.

### Modified Capabilities

None. The notch bar's own behaviour while visible is unchanged.

## Impact

- `Tinycast/Fork/Notch/NotchBarCoordinator.swift`: start and stop the bar from the preference.
- `Tinycast/Features/Settings/`: `AppSettings`, `AppSettingsKey`, `SettingsFileKey`,
  `SettingsFileSchema`, and the settings pane that hosts the toggle.
- `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift`: classify the new key.
- `Tinycast/App/AppCore.swift`: the `notchBar.start()` call site in `start()`.
- `docs/features/notch-bar.md` and `docs/fork.md`: state that the bar is off by default.
- No new dependencies. The preference grants no capability, so it may travel in backups and
  `settings.json`.
