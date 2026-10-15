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
