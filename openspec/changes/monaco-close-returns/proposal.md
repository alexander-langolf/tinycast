## Why

Opening a file in the Monaco editor from File Navigator or Search Files hides the palette. Closing the editor leaves the palette hidden. The browse-and-edit flow then ends at the editor: the user has to reopen the palette and find the folder or results again.

## What Changes

- Closing Monaco returns to the palette screen that opened the file. Esc, ⌘W, the close button and a completed unsaved-changes dialog all count as closing.
- From File Navigator, the palette reopens on the same folder, with the same filter, picks and focused row.
- From Search Files, the palette reopens with the same query, type filter and selected result.
- An editor opened from anywhere else closes as before and shows no palette.
- When the origin no longer exists, for example a deleted folder, the palette shows that screen's own recovery state.
- Cancelling the unsaved-changes dialog keeps the editor open, as before.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `file-browser`: File Navigator restores its state when the Monaco editor it launched closes.
- `fsearch-file-search`: Search Files restores its state when the Monaco editor it launched closes.

## Impact

- **Touched code:**
  - `MonacoEditorCoordinator` records the origin when a file opens and returns to it on close.
  - `FileNavigatorCoordinator` supplies and restores the browser's state.
  - The Search Files coordinator supplies and restores its query and selection.
  - `PaletteCoordinator` shows a given mode with the restored state.
- **Dependency:** the Monaco editor itself comes from the unarchived `monaco-editor-option` change.
- **Related:** `monaco-vscode-settings-and-return` keeps only the VS Code settings import.
- **Out of scope:** returning to Tinycast screens other than File Navigator and Search Files, and to embedded or external terminal editors.
