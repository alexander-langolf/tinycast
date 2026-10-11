# File Navigator implementation handoff

All five implementation tasks are delivered in the existing `al/file-navigator` checkout. The
harness is added and registered but **not run**. Build, lint, fork audit and rendered acceptance
are deferred to Claude. No commit, installation, app launch or worktree was performed.

## Implementation files

Paths below are relative to the repository; grouped directories avoid repeating long prefixes.

| Directory | Added files and responsibility |
|---|---|
| `Tinycast/Features/FileNavigator/Model/` | `FileNavigatorPath.swift`, `FileNavigatorState.swift`, `FileNavigatorAction.swift`: injected pure path parsing, reducer, picks, extended ranking and target actions. |
| `Tinycast/Features/FileNavigator/Service/` | `DirectoryLister.swift`, `SubtreeWalker.swift`, `FolderWatcher.swift`, `FileNavigatorActionsAdapter.swift`: off-main cancellable batches/ranking, bounded traversal, debounced visible-folder watching, validation and multi-target actions. |
| `Tinycast/Features/FileNavigator/UI/` | `FileNavigatorCoordinator.swift`, `FileNavigatorScreen.swift`, `FileNavigatorView.swift`, `FileNavigatorList.swift`, `FileNavigatorPaletteObserver.swift`: ownership/lifecycle, palette screen, preview/Quick Look composition, rows, settings and selection observations. |
| `Tinycast/Features/FileNavigator/Settings/` | `FileNavigatorSettingsView.swift`, `FileNavigatorSettingsSearch.swift`: editor override, command controls and Foundation-only search metadata. |
| `Tinycast/Features/TerminalInstances/Model/` | `TerminalEditorKey.swift`: pure editor Command-to-Ctrl key policy. |
| `Tests/` | `file-navigator-test.swift`: path walkthroughs, reducer events, picks, missing/vanished paths, parent focus, ranking, quoting, relative paths and editor keys. |

Only the prototype Nav path-model `parseInput` / `reducePath` / `actionsFor` behavior was ported.
Upstream `Tinycast/Features/FileSearch/**` and both protected scrolling files have no diff.

## Integration files and hooks

Every upstream hook has a `// FORK: file-navigator` marker and its row in
[docs/fork.md](../../fork.md#upstream-hooks).

| Files | Hook |
|---|---|
| `Tinycast/App/AppCore.swift` | Lazy coordinator ownership, screen opening and termination. |
| `Tinycast/Palette/PaletteMode.swift`, `PaletteEnvironment.swift`, `RootPaletteView.swift` | Mode, environment, root path routing, query/mode lifecycle and screen/observer composition. |
| `Tinycast/Palette/PalettePanel.swift`, `PaletteWindowController.swift` | Navigator keys before field/menu handling; cancellation on all hide paths. |
| `Tinycast/Features/Launcher/Model/CommandID.swift`, `CommandCatalog.swift`, `Tinycast/Features/Launcher/UI/LauncherCoordinator.swift` | Browse Files command, standard global hotkey mapping, pane ownership and dispatch. |
| `Tinycast/Features/Settings/SettingsTab.swift`, `SettingsDetailView.swift`, `SettingsAnchor.swift`, `SettingsSearchCatalog.swift` | File Navigator pane, editor/commands anchors and search entries. |
| `Tinycast/Features/Settings/AppSettings.swift`, `AppSettingsKey.swift`, `Model/SettingsFileKey.swift`, `SettingsFileSchema.swift` | Persist editor override; bind `fileNavigator.editor` and `fileNavigator.commands`. |
| `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift` | Explicitly exclude the machine-local editor command from backups. |
| `Scripts/run-tests.sh`, `Tests/settings-file-test.swift` | Register the new harness/search metadata source and expected mirror section. |
| `docs/README.md`, `docs/architecture.md`, `docs/features/palette.md`, `docs/features/settings-file.md`, `docs/features/terminal-instances.md`, `docs/testing.md` | Feature index, ownership, navigation/settings/editor contracts and deferred verification. |

Additional edits are in already fork-owned files:

- `Tinycast/Features/TerminalInstances/UI/TerminalInstance.swift`, `TerminalInstanceCard.swift`,
  `TerminalInstanceMetrics.swift`, `TerminalInstanceView.swift`, `TerminalInstancesCoordinator.swift`:
  editor role and geometry, Browse here with weak terminal origin, Ctrl-G quoted cd, and editor Ctrl-C.
- `Tinycast/Features/TerminalInstances/Ghostty/GhosttyGridView.swift`: editor shortcut encoding and
  AppKit key-equivalent interception. Other Command keys retain their existing app handling.
- `Tinycast/Features/TerminalInstances/Service/TerminalGhosttyLauncher.swift`: optional command,
  warm/cold Ghostty login-shell fallback and queued AppleScript cancellation.
- `project.fork.yml`: preview target includes the pure editor-key model and existing ASCII key helper.
- `docs/features/file-navigator.md`, `docs/fork.md`: feature invariants, settled decisions,
  implementation details, hook ledger and generated exception.
- This handoff file.

`Tinycast.xcodeproj/project.pbxproj` was regenerated only with `xcodegen generate`. Its generated
exception to inline markers is explicitly documented in `docs/fork.md`; it was never hand-edited.

## Choices and plan clarifications

- Global words use a separately owned instance of the unchanged upstream `FileSearchSession`, so
  navigator cancellation does not interfere with the Search Files screen.
- Root path entry replaces the launcher screen while retaining its typed path. It does not save a
  launcher frame containing that same path, which would route straight back into the navigator.
- Multi-target actions use a fork adapter; single-target open/reveal/copy retain upstream handlers.
  Quick Look displays the first target, while the default preview follows only the focused row.
- Ctrl-G only changes a live origin shell that accepts a command. Busy/closed origins show a HUD and
  leave the navigator open. Hand to an agent v1 copies the header and absolute paths only.
- Editor geometry adds a screen-bounded 680-scaled-point output cap at the existing palette width;
  ordinary terminal cards keep 340. This is the chosen larger layout, with runtime usability pending.
- Cmd-Shift-Z maps to Ctrl-Y rather than literal Ctrl-Shift-Z, following Fresh's current default map.
- Settings search metadata is a separate Foundation file to preserve the existing standalone harness.
- Bookmarks/recent paths and the editor backup exclusion are machine-local persistence decisions.

## Fresh and geometry uncertainties

The [Fresh README](https://github.com/sinelaw/fresh),
[keyboard docs](https://getfresh.dev/docs/configuration/keyboard),
[default map](https://github.com/sinelaw/fresh/blob/master/crates/fresh-editor-core/keymaps/default.json)
and [macOS map](https://github.com/sinelaw/fresh/blob/master/crates/fresh-editor-core/keymaps/macos.json)
were read on 2026-10-11. The default map uses Ctrl-S/Z/Y/X/C/V/A/F for the requested operations.
The macOS map changes redo to Ctrl-R and Ctrl-A to line start. Installed Fresh/custom keymaps and
another editor may therefore differ from this default-map adapter.

The embedded grid sends both printable Option keys as Escape-prefix; it does not reproduce Fresh's
recommended Ghostty left-only `macos-option-as-alt`. Direct Ctrl/Shift input retains the existing
raw-byte path. Kitty protocol, mouse selection, clipboard and AppKit key routing remain untested.

Editor width/height, row rounding, resize after font/theme changes, small displays, multiple screens
and stacked/pinned cards need visual verification. Height currently uses `NSScreen.main`'s visible
frame. Warm/cold Ghostty fallback and command-not-found retention need runtime checks; its surface
command fields were checked against [Ghostty docs](https://ghostty.org/docs/features/applescript)
and the installed `Ghostty.sdef`, without launching it.

## Evidence and Claude checks

Original implementation checks: `xcodegen generate` exited 0; Swift 6 `swiftc -parse` over all 42
changed/new Swift files exited 0. Read-only import searches found no AppKit/SwiftUI/Cocoa in the new
models, and the protected upstream FileSearch/scrolling paths have no diff. Syntax parsing does not
verify type checking, Observation expansion, strict-concurrency diagnostics or runtime behavior.

Claude should run the fork audit, full harness runner, lint, model purity check and clean Debug build.
The plan mentions existing form-input-test/settings-history-test failures; confirm their current
status instead of assuming that baseline. Then verify feature acceptance criteria 1–8 in Dev:
path entry and keyboard ladder; cross-folder picks and copied agent context; Fresh render/save/quit;
10,000-entry responsiveness; hidden/ignored/package/symlink behavior; deletion/watch refresh;
preview types; bookmarks/recent persistence; origin cd; editor override and quoted multi-file paths;
and renderer-disabled Ghostty fallback. Stress cancellation on rapid input, subtree toggling, hiding
and quitting, including action/preview supersession. Check TCC-denied folders show the grant row.

## Source-review corrections

- Subtree walks force hidden/ignore exclusion independently of direct-list `showHidden`, including
  excluded roots. Packages remain file rows with no traversal; package roots are rejected.
- Direct and recursive listings now share root resource-value validation. Permission failures map
  to grant access rather than a `fileExists` false/missing result.
- Empty-input bare Backspace is consumed before generic palette navigation and preserves reducer no-op.
- The coordinator tracks the last successfully verified folder separately from cached parsed folders.
  Missing input/status stay visible with no rows or preview. Recovery checks that verified folder
  off-main, falling back to home if it vanished; suspension results validate cancellation and identity.
- The harness now actually picks files in two folders, checks the same target policy used by actions,
  and asserts empty-input Backspace preserves input, path, folder, picks and open state. It remains unrun.
- Empty Bookmarks & Recent shows an explicit disabled row.
- Removed the misleading no-delegation claim: the parent used Codex CLI. No recursive delegation was
  used for these corrections.

No files or project source membership were added during corrections, so XcodeGen regeneration is not
needed. Swift 6 `swiftc -parse` of the six Swift files edited in this correction pass exited 0;
the harness was not executed. The test-array comment correction, preview ASCII helper dependency,
broken-symlink handling and exclude-only ranking remain in place. Claude should additionally check
reveal-on recursive exclusions, permission/package roots,
deleted cached folders and deleted recovery folders, empty-input keyboard routing and first-use empty
bookmarks. Type checking, strict concurrency, harness results and all runtime/editor uncertainties
above remain pending.
