## Context

`MonacoEditorCoordinator.open(path:)` hides the palette with `hidePalette(restoreFocus: false)` before it presents the editor. `close()` dismisses the editor and never shows the palette again. Only `FileNavigatorCoordinator.edit(_:)` opens Monaco. Search Files reaches it through the same `edit(_:)` path from its Edit row.

## Goals / Non-Goals

**Goals:**

- Return to the originating palette screen with its state after every successful close.
- Keep the current behaviour when the editor has no palette origin.

**Non-Goals:**

- Restoring scroll position or the preview pane's own scroll.
- Returning from terminal editors such as Fresh in Ghostty.

## Decisions

### 1. The caller passes an origin

`open(path:origin:)` takes an optional origin value. `FileNavigatorCoordinator.edit(_:)` builds that value from the current screen: File Navigator or Search Files, with that screen's state. Monaco stores the origin with its session and doesn't inspect it. A caller that passes no origin gets the old behaviour.

The origin is a main-actor return closure with a weak reference to the owning coordinator.
Each closure captures that screen's snapshot.
Monaco retains the closure until a successful close.

### 2. Each screen owns its own state snapshot

File Navigator's snapshot holds the input (folder and filter), the picks and the focused row. Search Files' snapshot holds the query, the type filter and the selected result. Each coordinator captures and restores its own snapshot, so the editor needs no knowledge of either screen.

The palette's preserved-state path cannot satisfy this contract.
`PaletteWindowController.hide` stops File Navigator, clearing picks and rows.
The Pop to Root timer can also clear the mode, query, and Search Files session during editing.
The Immediately setting performs that reset as the palette hides.
Explicit snapshots preserve state independently of that timeout.

File Navigator captures its value state and focused path, then reloads through its existing listing path.
Search Files captures the selected path and index alongside the query and type filter.
Search Files cancels the prior request before searching, so an identical query also re-runs.
Observation waits for refreshed results before selecting the captured path or nearest remaining index.
The palette passes the active type filter when opening Search Files.

`monaco-close-returns-test` drives the shipped coordinators with an immediate-reset palette-window stand-in.
The harness checks that hiding clears picks and mode before restoration.
The harness also covers a deleted folder and a selected result removed or reordered during editing.
Harness execution belongs to Claude's verification pass.

### 3. Restore happens after the editor closes

The palette shows only after `close()` has dismissed the editor, so focus moves straight from the editor to the palette. Restoring re-runs the screen's normal load: File Navigator lists the folder, and Search Files re-runs the query. A folder that has gone missing shows File Navigator's missing-folder state. A result that has gone shows the refreshed list with the nearest row selected.

### 4. Replacing the open file keeps the first origin

Opening a second file while the editor is open replaces the document. The first origin stays, because the user started from that screen.

## Risks / Trade-offs

- A slow fsearch query can show results a moment after the palette appears. The screen's existing loading state covers this.
