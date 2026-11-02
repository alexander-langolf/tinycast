## Why

Monaco opens with Tinycast's own defaults, so a file edited there looks and behaves differently from the same
file in VS Code: another font size, tab width, wrapping and minimap.

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
- Returning to the originating palette screen on close is the separate change `monaco-close-returns`.

## Capabilities

### New Capabilities
- `monaco-vscode-settings`: reading, parsing and mapping the user's VS Code settings onto Monaco options,
  the opt-out setting, language overrides, and the failure behaviour.

### Modified Capabilities
None.

## Impact

- **New code**: a VS Code settings reader in `Features/MonacoEditor/Service/` and a JSONC parser and option
  mapper in `Model/` (Foundation only), with a harness in `Tests/`.
- **Touched code**: `MonacoEditorCoordinator` (options passed to the page), `MonacoWebHost` and
  `Scripts/monaco-bundle/src/main.js` (accept an options object), `AppSettings`,
  `SettingsFileKey`/`SettingsFileSchema`, backup coverage and the File Navigator pane.
- **Reads outside the app**: the VS Code user folder, read-only and only when the setting is on. No file is
  written there, and nothing from it leaves the machine.
- **Docs**: `docs/features/monaco-editor.md`.
- **Out of scope**: VS Code keybindings, extensions, snippets, workspace and folder settings, Settings Sync,
  and writing back to VS Code.
