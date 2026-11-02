## 1. Origin

- [x] 1.1 Add an optional palette origin to `MonacoEditorCoordinator.open`, stored with the session and kept when the document is replaced.
- [x] 1.2 Pass the File Navigator or Search Files origin from `FileNavigatorCoordinator.edit(_:)`.

## 2. Snapshots

- [x] 2.1 Capture and restore File Navigator's input, picks and focused row.
- [x] 2.2 Capture and restore Search Files' query, type filter and selected result.

## 3. Return on close

- [x] 3.1 After a successful close, show the palette in the origin's mode with its restored state.
- [x] 3.2 Keep the editor open when the unsaved-changes dialog is cancelled, and show no palette for an editor without an origin.

## 4. Verification

- [x] 4.1 Add a harness for origin capture, replacement and restore, and for the no-origin path.
- [ ] 4.2 Build Debug, relaunch Dev, and check Esc, ⌘W and the close button from both screens, including a deleted folder.
- [x] 4.3 Update `docs/features/monaco-editor.md`, `docs/features/file-navigator.md` and `docs/features/file-search.md`.
