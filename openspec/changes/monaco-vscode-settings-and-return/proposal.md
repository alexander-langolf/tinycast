## Why

Monaco opens with Tinycast's own defaults, so a file edited there looks and behaves differently from the same
file in VS Code: another font size, tab width, wrapping and minimap. Closing the editor also leaves the
palette hidden, so Esc ends the whole browse-and-edit flow instead of returning to the results or folder the
file came from.

## What Changes

- Monaco reads the user's VS Code `settings.json` (`~/Library/Application Support/Code/User/settings.json`,
  JSONC) and applies the `editor.*` keys Monaco supports, such as `fontFamily`, `fontSize`, `tabSize`,
  `insertSpaces`, `wordWrap`, `minimap.enabled`, `lineNumbers`, `renderWhitespace` and `cursorStyle`.
  Unsupported or malformed keys are ignored; a missing file changes nothing.
- A new setting, **Use VS Code settings** (on by default), controls this and is mirrored in `settings.json`.
  Tinycast's monospaced font preference stays the fallback when VS Code sets no font.
- Per-language overrides (`"[swift]": { ... }`) apply to the file's language.
- Optional, decided in design: map `workbench.colorTheme` to a Monaco theme by converting the installed
  theme's JSON from `~/.vscode/extensions`; otherwise the dark/light built-in follows the app appearance.
- Closing Monaco (Esc, ⌘W, the close button, after the unsaved-changes dialog) returns to the palette on the
  screen the file was opened from: Search Files with its query and selection, or File Navigator with its
  folder, picks and focus. Opening from anywhere else just closes the editor.
- **BREAKING** (to this unreleased feature only): the editor no longer leaves the palette hidden after close.

## Capabilities

### New Capabilities
- `monaco-vscode-settings`: reading, parsing and mapping the user's VS Code settings onto Monaco options,
  the opt-out setting, language overrides, and the failure behaviour.

### Modified Capabilities
- `monaco-editor`: the close behaviour returns to the originating palette screen. This spec is introduced by
  the unarchived `monaco-editor-option` change, so that change must be archived first.
- `file-browser`: File Navigator restores its folder, picks and focus when the editor it launched closes.
- `fsearch-file-search`: Search Files restores its query and selection when the editor it launched closes.

## Impact

- **New code**: a VS Code settings reader in `Features/MonacoEditor/Service/` and a JSONC parser and option
  mapper in `Model/` (Foundation only), with a harness in `Tests/`.
- **Touched code**: `MonacoEditorCoordinator` (origin capture, return on close, options passed to the page),
  `MonacoWebHost` and `Scripts/monaco-bundle/src/main.js` (accept an options object), `FileNavigatorCoordinator`
  and `FileSearchCoordinator` (supply and restore their palette state), `PaletteCoordinator` (show a given
  mode), `AppSettings`, `SettingsFileKey`/`SettingsFileSchema`, backup coverage and the File Navigator pane.
- **Reads outside the app**: the VS Code user folder, read-only and only when the setting is on. No file is
  written there, and nothing from it leaves the machine.
- **Docs**: `docs/features/monaco-editor.md`, `docs/features/file-navigator.md`, `docs/features/file-search.md`.
- **Out of scope**: VS Code keybindings, extensions, snippets, workspace and folder settings, Settings Sync,
  and writing back to VS Code.
