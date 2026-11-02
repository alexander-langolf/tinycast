## Why

Monaco's built-in appearance differs from Sasha's preferred editor font, theme, and wrapping.
A project configuration keeps these choices editable alongside Tinycast's server files.

## What Changes

- Monaco reads `editor/monaco.json` under the active fork policy directory on every editor open.
- The project ships Geist Mono at size 16, line height 1.7, disabled minimap, and enabled wrapping.
- The project ships an unchanged copy of the Monokai Pro (Filter Spectrum) theme JSON.
- The page converts theme colours and token scopes into a Monaco theme that takes precedence over app appearance.
- Invalid files and unavailable fonts restore the built-in appearance and produce a typed event without file contents.

## Capabilities

### New Capabilities

- `monaco-project-settings`: project-local editor configuration, theme conversion, reload behaviour, and fallback diagnostics.

### Modified Capabilities

None.

## Impact

- Configuration: `server/editor/monaco.json` and `server/editor/themes/monokai-pro-filter-spectrum.json`.
- Swift: Monaco editor models, settings loader, and web host.
- Page: `Scripts/monaco-bundle/src/main.js`.
- Coverage: `Tests/monaco-settings-test.swift` and its runner registration.
- Documentation: `docs/features/monaco-editor.md` and the `monaco-editor` section of `docs/fork.md`.
- The separate `monaco-vscode-settings-and-return` proposal retains its VS Code settings import scope.
- VS Code extensions, live VS Code settings import, font distribution, and editor return behaviour are outside this change.
