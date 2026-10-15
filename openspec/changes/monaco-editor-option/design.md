## Context

Edit in the file browser (`FileNavigatorCoordinator.run(.edit)`) builds a quoted `fresh` command and calls
`TerminalInstancesCoordinator.open(command:directory:isEditor:)`. The embedded grid is
`GhosttyGridNSView`, fed by `GhosttyTerminalGrid` (libghostty-vt only, no renderer). In a mouse-tracking
alternate-screen editor each wheel tick becomes a pty write, Fresh repaints, `refresh()` rebuilds a
`[[Cell]]` snapshot per chunk, and `draw()` repaints every cell on the CPU. That is the sluggishness.

The app has no WebKit use today. Extensions run in JavaScriptCore, and the one bundled JS asset,
`Resources/RaycastRuntime.generated.js`, is committed so building never needs Node. The posture is zero
third-party dependencies, modern APIs, `@MainActor` by default, and dialogs through `DialogController`.

## Goals / Non-Goals

**Goals:**
- Let the user choose Monaco as the Edit target, leaving Terminal as the default.
- Smooth scrolling and typing for ordinary source files, with no pty in the loop.
- Fully offline: no network, no remote scripts, no remote file access from the web view.
- Keep every new type inside `Features/MonacoEditor/`, with a Model that imports neither AppKit nor SwiftUI.

**Non-Goals:**
- Replacing or removing the terminal editor path.
- Multi-tab or multi-file editing, split views, LSP, Monaco extensions, or workspace features.
- Fixing the libghostty grid's own scroll performance (tracked separately: per-frame coalescing and
  dirty-row read-out).
- Editing non-UTF-8 or very large files.

## Decisions

**1. Settings shape: a kind enum beside the existing command.** Add `FileNavigatorEditorKind`
(`terminal`, `monaco`) persisted as `fileNavigatorEditorKind` and mirrored as `fileNavigator.editorKind`
in `SettingsFileKey`/`SettingsFileSchema`. The command field stays and is shown only for Terminal. It is
not a capability flag, so backups carry it. *Alternative:* a magic command string such as `monaco`. Rejected:
it mixes a mode into a shell field and breaks the rule that blank means Fresh.

**2. Host: WKWebView, not a bundled JS engine in JavaScriptCore.** Monaco needs a DOM, workers and layout.
`WKWebView` is the only modern, supported way to run it on macOS. *Alternative:* a native Swift editor
(Notes' editor is the closest). Rejected for this change: syntax highlighting, minimap, find/replace and
multi-cursor are the reason for choosing Monaco.

**3. Offline bundle, committed and generated.** `Scripts/monaco-bundle/build.mjs` (esbuild, same shape as
`Scripts/raycast-runtime/build.mjs`) emits `Tinycast/Resources/MonacoEditor/` containing `index.html`, the
editor JS and CSS, the codicon font, and the editor worker, with only the languages and features Tinycast
wants. The output is committed so building never needs Node, and is listed with the other generated files.
The page is loaded with `loadFileURL(_:allowingReadAccessTo:)` scoped to that one folder. *Alternative:*
fetch Monaco from a CDN. Rejected: violates the offline and ephemeral-session rules and would break without
network.

**4. A locked-down web view.** A non-persistent `WKWebsiteDataStore`, JavaScript enabled only for the
bundled page, no navigation away (a `WKNavigationDelegate` cancels everything except the initial load),
`window.open` and new-window requests refused, and no `file://` access beyond the bundle folder. The file's
text never goes through a URL: Swift sends it with `callAsyncJavaScript` as a typed argument, and the page
reports edits through one `WKScriptMessageHandler`. Messages are a closed set decoded into a Swift enum, so
a malformed message is dropped.

**5. Swift owns the file; the page owns the buffer.** `MonacoEditorSession` (`@MainActor`, `@Observable`)
holds the URL, last-saved text and dirty flag. Save reads the buffer from the page, then writes atomically
off the main actor with a `@concurrent` function, and compares the file's modification date taken at load
to detect an external change before overwriting. Stale results are checked against the session identity
before applying, per the async rule in AGENTS.md. *Alternative:* let the page save through a message
without Swift. Rejected: the web view must hold no write capability.

**6. Hosting surface: its own panel, like terminal instances.** Terminal editors do not live inside the
palette: `TerminalInstancesCoordinator.open` hides the palette and a presenter shows a floating
`NSPanel`. Monaco follows that shape: `MonacoEditorCoordinator` (on `AppCore`), `MonacoEditorPresenter` and
`MonacoEditorPanel` under `Windows/MonacoEditor/`, hosting a title bar and the web view. One editor panel
exists at a time; opening another file while one is dirty asks first. This keeps the palette's
type-ahead and arrow handling out of the picture entirely. *Alternative:* a palette screen. Rejected: the
palette's key routing is large and the palette is a transient surface, whereas an editor must survive the
palette hiding. The Model file `MonacoLanguageMap.swift` maps extensions to Monaco language ids and is
covered by a standalone harness in `Tests/`.

**7. Keyboard.** The panel takes key without activating Tinycast, like the terminal panel, and the web
view is first responder. ⌘S saves and Esc and ⌘W close, handled inside the page so Monaco's own widgets
(find, suggest) get Esc first; the panel also claims ⌘W and ⌘S ahead of the page when focus is elsewhere in
the panel. Every other chord goes to Monaco.

**8. Single IIFE bundle.** The page is loaded from `file://`, where module scripts and workers are
blocked, so the bundle is one IIFE and only the editor core plus syntax tokenizers ship. The CSS, HTML and
TypeScript language services and the JSON service need workers and are left out; JSON keeps its tokenizer.

**9. Theme.** Tinycast sets Monaco's theme to a built-in dark or light theme from `AppAppearance` and
`ForkAppearance` (mono font family and size), updated live through the message channel. Dark is the
baseline.

## Risks / Trade-offs

- [Bundle size: Monaco is several MB] → Ship only the editor core and the languages in the map; measure
  and record the size in `docs/features/monaco-editor.md`; the bundle is stored once in `Resources/`.
- [First open is slow while WebKit spins up] → Create the web view lazily on first use and keep one warm
  instance for the session; show the palette immediately with a loading state.
- [Memory held by a warm WKWebView] → Tear it down when the palette hides for longer than a short idle
  period and when the setting flips back to Terminal.
- [A non-activating panel may not give a WKWebView keyboard focus] → Same recipe as
  `TerminalInstancePanel`; verify with a native check and record the result in the feature doc.
- [Unsaved edits lost on close or quit] → Closing, replacing the file or quitting with a dirty session
  routes through the dialog controller; the dialog offers Save, Discard and Cancel.
- [Binary, huge or non-UTF-8 files] → Refuse to open with a HUD message (size cap and UTF-8 decode check)
  and fall back to nothing rather than corrupting the file.
- [First third-party web code in the app] → Isolated to the feature folder, loaded offline, no
  privileged bridge beyond the closed message set; listed in `docs/fork.md`.

## Migration Plan

Default stays Terminal, so no data migration. The new key is absent on existing installs and decodes to
Terminal. Rollback is deleting the feature folder and the setting; no stored data depends on it.

## Open Questions

- Which exact file-size cap is acceptable for a first release (proposal: 2 MB)?
- Should Monaco get its own `CommandID` so it can be bound to a hotkey, or stay reachable only through
  Edit? Defaulting to the latter.
- Does a non-activating panel keep first-responder keyboard input for a `WKWebView`? Needs a native check
  in Debug (task 5.6).
- Monaco's editor worker cannot start from `file://` in WKWebView, so Monaco runs it on the main thread; if
  large files stutter, serve the page through a custom `WKURLSchemeHandler` and use a real worker.
