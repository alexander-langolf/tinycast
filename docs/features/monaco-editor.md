# Monaco editor

An opt-in alternative to the terminal editor behind File Navigator's Edit. Settings → File Navigator →
**Editor kind** chooses Terminal (the default, [file-navigator.md](file-navigator.md#edit-in-a-terminal-view))
or Monaco. Behaviour is specified in `openspec/specs/monaco-editor/spec.md`.

## Invariants

- **The page is offline and locked down.** `MonacoWebHost` loads `Resources/MonacoEditor/index.html` with
  `loadFileURL(_:allowingReadAccessTo:)` scoped to that folder, on a non-persistent data store. Its CSP is
  `default-src 'none'` with only the bundle's own script, style and font. Navigation to any other URL is
  cancelled and new-window requests return nil.
- **Swift owns the file; the page owns the buffer.** The page can only send the closed
  `MonacoBridgeMessage` set (`ready`, `dirty`, `save`, `close`); anything else is dropped. Text goes in
  through `callAsyncJavaScript` arguments, never a URL or string-built script. Reads and writes live in
  `MonacoFileIO` and run off the main actor. Saves are atomic, follow symlinks and keep permissions.
- **Dirty is the page's undo version.** The page compares Monaco's alternative version id with the one
  recorded at the last save, so undoing back to the saved text clears the marker. `markSaved` receives the
  version captured before the write, so edits typed during a save stay dirty.
- **Stale results never apply.** Every `await` in `MonacoEditorCoordinator` re-checks that the session is
  still the one that started the work.
- **One editor at a time, in its own panel.** Like a terminal instance, the palette hides and a floating
  `MonacoEditorPanel` takes key without activating Tinycast. The presenter lives in
  `Windows/MonacoEditor/`; the feature folder never builds windows.
- **Unsaved changes always ask.** Close (⌘W, Esc, the button), opening another file, and quitting go through
  `AppCore.choose`: Save, Don't Save, Cancel. Saving over a file whose modification date moved asks first.
- **`Model/` is Foundation-only.** Language map, document rules and message decoding are covered by
  `Tests/monaco-editor-test.swift`.

- **Search Files shares Edit.** `FileNavigatorCoordinator.edit(_:)` is the one implementation; File
  Navigator's Edit action and Search Files' actions menu (`editAction(for:)`, a marked hook in
  `FileSearchActionsMenu`) both call it, so the editor kind and command apply to both. The row reads
  "Edit in Monaco" or "Edit in Fresh".

## Returning to the palette

Closing Monaco returns to File Navigator or Search Files when that screen opened the editor.
Esc, ⌘W, the close button, Save, and Don't Save use the same close path.
Cancel and a failed save keep the editor open with the palette hidden.
An editor opened without an origin closes without showing the palette.

The caller passes an optional return closure to `MonacoEditorCoordinator.open(path:origin:)`.
Each screen captures its own snapshot before the palette hides.
File Navigator restores its folder, filter, picks, and focused row, then reloads the folder.
A deleted folder shows the navigator's missing-folder recovery state.
Search Files restores its query and type filter, then re-runs the search.
The selection follows the same result by path or the nearest remaining row by index.
Replacing the file keeps the first origin, including an absent origin.
The editor dismisses its panel before invoking the return closure.

The `monaco-close-returns-test` harness compiles the shipped coordinators with platform stand-ins.
Harness execution and native keyboard and focus checks belong to the verification pass.

## Project editor settings

<!-- // FORK: monaco-editor -->

Monaco reads `editor/monaco.json` under the active `ForkPolicyStore.directory` whenever an editor opens.
The default directory is `~/github/tinycast/server`.
Closing and reopening the editor applies file edits without rebuilding the app or page bundle.
Focusing an editor that already shows the requested file keeps the open session's settings.

The project file contains these options:

```json
{
  "theme": "themes/monokai-pro-filter-spectrum.json",
  "fontFamily": "Geist Mono",
  "fontSize": 16,
  "lineHeight": 1.7,
  "minimap": false,
  "wordWrap": "on"
}
```

The theme path resolves relative to `monaco.json`.
The shipped theme is an unchanged copy of Monokai Pro (Filter Spectrum)'s theme JSON.
The configuration contains no extension code and imports no VS Code settings at runtime.
Geist Mono uses the installed system font.
Monaco treats a line height below 8 as a font-size multiplier.
Wrapping supports `off`, `on`, `wordWrapColumn`, and `bounded`.

`MonacoSettingsLoader` reads and decodes the settings and theme off the main actor.
`MonacoEditorOptions`, exposed as `MonacoWebHost.Options`, maps the parsed profile into page arguments without a web view.
The page converts VS Code `tokenColors` into one rule per scope and preserves foreground alpha and `fontStyle`.
The page passes theme `colors` to Monaco with their original colour identifiers.
The theme's `type` selects `vs-dark` or `vs` as the inherited base.
An active project theme and font take precedence over app appearance and monospaced-font changes.

A missing or malformed settings or theme file discards the project profile.
An unavailable font also discards the profile.
The editor then follows the app's built-in dark or light theme and Tinycast's monospaced-font preference at size 13.
The fallback keeps the minimap enabled, wrapping off, and automatic line height.
Failures produce a typed `ForkEvent` through `ForkLog`, with no dialog or file contents.
The event uses category `supervision`, operation `health`, step `fallback`, and a typed `policyFailure` reason.
Missing fonts use `invalidValue`; unreadable files use `unreadable`; decoding failures use `invalidJSON`.
The `tinycast logs` command exposes these events.

`Tests/monaco-settings-test.swift` covers the shipped configuration, relative paths, reloads, fallback, and the options mapper.
The harness evaluates the shipped page glue in JavaScriptCore with a Monaco stand-in to cover theme conversion and appearance precedence.
The harness does not render Monaco or verify font installation.

## Limits

- UTF-8 text only, no NUL bytes, at most 2 MB (`MonacoDocument.sizeLimit`). Otherwise a HUD names the reason.
- Several selected files open only the first.
- Languages: Monaco's Monarch tokenizers plus a JSON tokenizer. The CSS, HTML, TypeScript and JSON language
  *services* (diagnostics, completion) are left out because they need workers, which `file://` blocks in
  WKWebView. Monaco runs its own worker on the main thread.
- ⌘S and ⌘W are claimed by the panel ahead of the page; Esc goes to Monaco first, so it dismisses find and
  suggestions before it closes the editor.

## The bundle

`Resources/MonacoEditor/` is generated and committed (about 4.5 MB: `editor.js`, `editor.css`,
`codicon.ttf`, `index.html`). Never hand-edit it. Rebuild with:

```sh
cd Scripts/monaco-bundle && pnpm install && node build.mjs
```

`build.mjs` takes `editor.main.js` from `monaco-editor` and drops the language services and the LSP client,
then bundles it with `src/main.js` (the page glue) into one IIFE. Bump the pinned `monaco-editor` version in
`package.json` deliberately and re-run the native checks below.

## Verified and not

Verified by harness and by a throwaway WKWebView driver: the page loads from `file://`, Monaco initialises,
text round-trips, an edit raises `dirty(true)`, `markSaved` clears it, and an attempted navigation away is
blocked. **Not yet verified on screen** (the driver's window was occluded, so WebKit never ran its render
loop): glyph rendering, the panel taking keyboard focus as a non-activating panel, ⌘S / ⌘W / Esc, theme and
font switching, and scroll smoothness against the terminal editor.
