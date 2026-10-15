## Why

Edit in the file browser runs a terminal editor (Fresh) inside the embedded libghostty grid. In an
alternate-screen editor with mouse tracking, every wheel tick round-trips through the pty and forces a
full-grid snapshot rebuild and CPU redraw, so scrolling feels sluggish. A native-feeling editor surface
with its own scrolling avoids the pty round-trip entirely, and the user wants it as a choice, not a
replacement.

## What Changes

- Add an **Editor** choice in Settings → File Navigator: **Terminal** (today's command, Fresh by default)
  or **Monaco**. Terminal stays the default, so nothing changes until the user opts in.
- When Monaco is selected, Edit opens the first file in a Monaco editor hosted in a `WKWebView` in its own
  floating panel, instead of starting a terminal instance.
- Monaco is vendored as a committed, generated bundle in `Resources/` and loaded from disk with no network
  access, following the `RaycastRuntime.generated.js` precedent, so building the app never needs Node.
- The editor loads and saves UTF-8 text files, shows a dirty marker, saves with ⌘S, and closes with Esc or
  ⌘W, asking through `DialogController` before discarding unsaved edits.
- Language is chosen from the file extension; theme follows the app's appearance (dark baseline).
- A new `SettingsFileKey` (`fileNavigator.editorKind`) mirrors the choice into `settings.json`.
- Multi-file Edit opens the first file only in Monaco; the terminal path keeps passing every file.

## Capabilities

### New Capabilities
- `monaco-editor`: the embedded Monaco editor surface: bundle, file load/save, dirty tracking, language and
  theme mapping, keyboard behaviour, and failure handling.

### Modified Capabilities
- `file-browser`: the "Editor and terminal actions preserve their distinct destinations" requirement gains
  an editor-kind choice that routes Edit to either the terminal editor or Monaco.

## Impact

- **New code**: `Tinycast/Features/MonacoEditor/` with `Model/` (language map, document state, no
  AppKit or SwiftUI), `Service/` (file IO, external-change check), `UI/` (WebKit host, coordinator), plus
  `Windows/MonacoEditor/` for the panel and presenter.
- **Touched code**: `FileNavigatorCoordinator.run(.edit)`, `FileNavigatorSettingsView`, `AppSettings`,
  `AppSettingsKey`, `SettingsFileKey` and `SettingsFileSchema`, `SettingsSearchCatalog`, `AppCore` wiring,
  and `SettingsBackupCoverage`.
- **New resources**: a generated Monaco bundle and `Scripts/monaco-bundle/` to rebuild it.
- **Dependencies**: introduces WebKit and a vendored Monaco bundle, the first third-party code in the app
  besides the Raycast runtime; it is isolated behind the feature folder and loaded offline.
- **Docs**: `docs/features/file-navigator.md`, a new `docs/features/monaco-editor.md`, `docs/fork.md`.
- **Out of scope**: replacing Fresh, multi-tab editing, LSP, extensions, remote files, and using Monaco as a
  general text-viewing surface.
