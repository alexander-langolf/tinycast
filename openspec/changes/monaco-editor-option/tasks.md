## 1. Spike and bundle

- [ ] 1.1 Spike in Debug: a `WKWebView` in a non-activating panel taking keyboard focus; record the result in the design's open questions (done as task 5.6 once a panel exists)
- [x] 1.2 Create `Scripts/monaco-bundle/` (package.json, build.mjs, entry) that bundles Monaco core, the editor worker and the language set with esbuild
- [x] 1.3 Generate and commit `Tinycast/Resources/MonacoEditor/` (index.html, JS, CSS, codicon font, worker); record its size
- [x] 1.4 Add the folder to `project.yml` resources, run `xcodegen generate`, commit both
- [x] 1.5 List the bundle among generated files in `AGENTS.md`, `docs/development.md` and `Scripts/lint.sh` if it checks generated files

## 2. Model (no AppKit or SwiftUI)

- [x] 2.1 Add `FileNavigatorEditorKind` (`terminal`, `monaco`) with a raw-value init that falls back to Terminal
- [x] 2.2 Add `MonacoLanguageMap` (extension to Monaco language id, plain text fallback)
- [x] 2.3 Add `MonacoDocument` value: URL, saved text, modification date, dirty computation, size cap and UTF-8 validation as injected parameters
- [x] 2.4 Add `MonacoBridgeMessage` closed enum and decoder for page-to-Swift messages
- [x] 2.5 Add `Tests/monaco-editor-test.swift` harness covering language map, kind fallback, dirty and size/UTF-8 rules, and message decoding; register it in `Scripts/run-tests.sh`

## 3. Settings

- [x] 3.1 Add `fileNavigatorEditorKind` to `AppSettings`, `AppSettingsKey` and the defaults load path
- [x] 3.2 Add `fileNavigator.editorKind` to `SettingsFileKey` and bind it in `SettingsFileSchema`; confirm `SettingsBackupCoverage` and its test include it
- [x] 3.3 Add the Editor picker to `FileNavigatorSettingsView`, showing the command field only for Terminal
- [x] 3.4 Add the row to `SettingsSearchCatalog` and `FileNavigatorSettingsSearch`; run `node Scripts/check-settings-search.js`

## 4. Service

- [x] 4.1 Implement load: size cap, UTF-8 decode, modification date, as a `@concurrent` function
- [x] 4.2 Implement atomic save with external-change detection; stale results validated against session identity before applying
- [x] 4.3 Add `MonacoEditorSession` (`@MainActor @Observable`) owning the document, dirty flag and save/close flow
- [x] 4.4 Wire `DialogController` prompts for overwrite-on-external-change and Save/Discard/Cancel

## 5. UI

- [x] 5.1 Implement the locked-down WebKit host: non-persistent data store, `loadFileURL` scoped to the bundle folder, navigation and new-window refusal, `WKScriptMessageHandler` for the closed message set
- [x] 5.2 Send text, language, theme and font to the page with `callAsyncJavaScript`; read the buffer back for Save
- [x] 5.3 Add `MonacoEditorPanel` and `MonacoEditorPresenter` under `Windows/MonacoEditor/` with a title bar, dirty marker and loading state; handle ⌘S and ⌘W ahead of the page
- [x] 5.4 Create the web view lazily per opened file and release it when the editor closes (a warm spare is a possible follow-up if first open feels slow)
- [x] 5.5 Route theme and mono-font changes live without resetting buffer, selection or undo
- [ ] 5.6 Native check: the panel gives the web view keyboard focus and typing, ⌘S, ⌘W and Esc work

## 6. Integration

- [x] 6.1 Add `MonacoEditorCoordinator` on `AppCore`, wired in `start()`, reached by views through `@Environment`
- [x] 6.2 Branch `FileNavigatorCoordinator.run(.edit)` on the editor kind; Monaco takes the first file target only
- [x] 6.3 On close, release the panel and web view after the idle period
- [x] 6.4 Route replacing the file and app quit with a dirty session through the confirmation dialog

## 7. Docs and verification

- [x] 7.1 Update `docs/features/file-navigator.md` and add `docs/features/monaco-editor.md` (invariants, bundle regeneration, size, offline guarantee)
- [x] 7.2 Add the Monaco integration point to `docs/fork.md` and mark touched upstream lines `// FORK:`
- [ ] 7.3 Native checks in Debug: open, scroll a large file, edit, save, external change, dirty close, appearance switch, offline
- [ ] 7.4 Compare scroll smoothness against the terminal editor on the same large file and record the result
- [x] 7.5 Run `./Scripts/format.sh`, `./Scripts/run-tests.sh`, `./Scripts/lint.sh`, the Model import grep, and confirm no new Debug warnings
