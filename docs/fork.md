# Sasha's Tinycast fork

Fork customisations live in `Tinycast/Fork/`. Upstream integration points are marked
`// FORK:` and listed below. Merge upstream into `main`; never rebase this long-lived fork.

## Ownership and defaults

`AppCore` owns `ForkAppearance`; its `start()` wiring publishes `ForkAppearance.current`
before any views are presented. Font, colour and asset choices live on that observable owner.
The font uses the existing `interfaceFont` defaults key. Choosing System removes that value.
`ForkAppearance.monoFontFamily` is the twin for code, under the `monoFont` defaults key and
`appearance.monoFont` in settings.json; choosing System Mono removes it.
Startup and subsequent changes publish the family to `ForkTypography.shared` and colour/asset
lookup tables to their locks; nonisolated hooks never read the main-actor owner.

With no overrides, typography and colours return upstream's original values. Code keeps its
system monospaced face unless a monospaced font is chosen, and symbols keep the system face. The fork app icon initially copies
upstream's icon; changing fork artwork does not require editing upstream assets.

## Customisation

Choose an interface font and a monospaced font in Settings → Appearance. The monospaced
picker is the same `ForkFontRow` with `kind: .monospaced`, listing only families with a fixed-pitch
face (`FontCatalog.monospacedFamilies`); `ForkTypography.monoFace` resolves them from the system
monospaced font so weight and italic carry over. The terminal instance grid follows it live
(`TerminalInstanceMetrics.faces`, re-measured per family); Notes' editor code styles and `TerminalLogView`
keep the system monospaced face. `ForkTypography.shared` is a nonisolated,
Sendable resolver. Its current family, cached faces and font metadata share one
`OSAllocatedUnfairLock`; lookups preserve font identity across threads. The lock's unchecked
closure is needed because `Mutex.withLock` requires a sending result, which cannot return an
`NSFont` still retained by its cache. The private cache state is not Sendable; fonts are never
stored in Sendable value types. `ForkFontSnapshot` carries names and sizes across actor boundaries.

`ForkAppearance.fontFamily` remains the observable source and publishes to the resolver in
`didSet` and `start()`. `InterfaceMetrics` continues to carry only scale, and its nested
`Typography: Sendable` retains upstream's isolation. Its hooks read the locked family, including
for the standard-size short-circuit, so upstream nonisolated Markdown rendering can use them.
`InterfaceMetrics.Typography` is the single routing point for Theme-based font families;
`Theme.Typography` is byte-for-byte upstream.

Settings panes and `DesignSystem/SettingsComponents.swift` deliberately keep upstream system
fonts, including alias fields. `SteadySegmentedPicker` has only a Settings caller and also stays
upstream. `ShortcutRecorder` and `ShortcutRecorderPopover` are Settings/onboarding controls,
not palette-facing, so their direct Theme reads stay upstream too. Notes, camera surfaces,
command output and the volume HUD use `metrics.typography` for their former direct token reads.
Symbol-only Theme reads elsewhere remain system fonts.

Set `ForkAppearance.colors.accent` to a `ForkColors.Pair` with light and dark `NSColor` values.
For adaptive colours, add an entry to `colors.pairs`, keyed by the upstream dark/light pair:

```swift
appearance.colors.pairs[
    .init(dark: .srgbInk(1, alpha: 0.10), light: .srgbInk(0, alpha: 0.09))
] = .init(dark: .red, light: .blue)
```

This changes both `selection` and `menuHover`: identical upstream pairs intentionally share an
override. Independent named-token overrides are no longer supported. Only tokens using `ramp`
or `adaptive` participate; fixed semantic colours remain upstream, and accent uses the hosting
scopes below. Remove a pair (or set accent to `nil`) to return to upstream. These are source-level
fork choices. The user-facing colour choice is a colour theme (Settings → Appearance → Colours):
`colors.theme`, a resolved `ForkColorPalette`, which `adaptive` asks before the pairs and which also
supplies the accent and pins `NSApp.appearance`; see
[appearance-theme.md](features/appearance-theme.md#colour-themes).

The only Theme edit is the `adaptive` resolver body; `ramp` already calls it. Upstream's stored
colour tokens remain intact. `ForkAppearance` publishes a locked value snapshot of its pairs at
startup and after changes, so AppKit's dynamic colour providers can read the current values
without accessing the main-actor owner from a rendering callback.

Named image replacements live in `Tinycast/Fork/ForkAssets.xcassets`. The fork lookup
prefers its namespaced replacement and otherwise returns the upstream image. Put an imageset
with the same logical name inside the catalog's `Fork/` namespace: `Fork/MenuBarIcon` replaces
the status icon, for example. Preserve template rendering for monochrome menu-bar artwork.
`assets.names` can map a logical name to a different catalog name when needed. Startup and
changes publish the map under a mutex; `ForkAssets.name` and `image` remain nonisolated.

`ForkAppearanceScope` observes `ForkAppearance.current?.fontFamily` and applies
`.id(fontFamily ?? "system")` to its content, rebuilding that tree once when the font changes.
It covers the palette root through `paletteEnvironment`, the Notes root, both AI Chat hosting
roots, shared settings roots and independent hosting windows. Changing the font resets local
view state in these trees; that is acceptable because font changes are rare. The scope also
applies an optional accent. AppKit-rendered fonts and Notes retain explicit refresh hooks
because a SwiftUI font token cannot restyle an existing attributed text buffer on its own.

The app icon uses `Tinycast/Fork/ForkAppIcon.icon`, copied from upstream's Icon Composer
document. This adapts the requested catalog icon to upstream's modern layered icon format:
flattening it into an `.appiconset` would change the default appearance. Fork build settings
live in `project.fork.yml`; regenerate the Xcode project after changing them. The same file defines
`TinycastPreviews`, a small app target (bundle id `com.tinycast.previews`) that compiles only the
AgentRuns UI, the terminal-instance card (`TerminalInstanceCard` and its metrics) and the design-system, fork-typography, theme-token and shell-runner files they read, so Xcode's canvas
can preview without libghostty or AppCore. Its entry point is `PreviewsApp/`; run it for a card playground.
Debug builds sign with upstream's `Tinycast Self-Signed` identity by default (create it once per
`signing.md` §1; with OpenSSL 3+, add `-legacy` to `openssl pkcs12 -export` or `security import` fails
its MAC check). This checkout can opt into an Apple Development identity through the ignored
`DebugSigning.local.xcconfig`; the same selection applies to the app, previews and embedded helpers.
See [signing.md](signing.md#switching-a-debug-checkout-to-apple-development) for the one-time
permission migration.

## Appearance pane and theme tokens

Settings → Appearance is a fork-owned pane (`Tinycast/Fork/Appearance/`) placed right after General.
It renders General's former Appearance section, unchanged, and the theme tokens: design values for
the agent card, the terminal instance and the palette, each defaulting to today's value, persisted,
mirrored as `appearance.tokens` in settings.json and carried in backups. See
[appearance-theme.md](features/appearance-theme.md) for the token list, keys and seams.

**A fork-owned pane plus small hooks beats editing upstream's General pane inline.** Upstream's
General keeps everything except the section, which is replaced by one marker line; the two private
rows it used become internal so the fork pane renders them, and the existing settings keys,
`settings.json` keys and search entries stay exactly as they were. The `generalAppearance` anchor now
names the Appearance pane (titled "General" there), so upstream's own search entries follow it with no
edit. The cost is a merge conflict if upstream edits that section: port the change into
`AppearanceSettingsView`. Inline editing would have threaded three token sections and their previews
through an upstream file instead.

Fork components read tokens directly through `ForkTheme.current`. The palette is upstream's, so its
tokens reach it only through `InterfaceMetrics` (the central seam), the fork-owned
`PaletteChipsCoordinator.paletteRadius` and `PaletteFrameClip`, and one scrim line in `RootPaletteView`.
Row padding needed a named metric, `spacing.rowVertical`, adopted by every list row's one padding line.
Colour themes need no upstream view edits: they ride the existing `adaptive` resolver hook, plus
two `color-theme` lines in `AppCore` for the appearance.

## Background agent runs

The [AgentRuns feature](features/agent-runs.md) is fork-owned under `Tinycast/Features/AgentRuns/`
and `Tinycast/Windows/AgentRuns/`, with its own documentation and `Tests/agent-runs-test.swift`.
`AppCore` owns its monitor, coordinator and panel presenter. Palette integration consists of tagged
lifecycle and geometry calls; the presenter owns observation, child-panel management and placement.
Feature-only dimensions live in `AgentRunsMetrics`, leaving Theme and InterfaceMetrics unchanged.
Polling runs while the palette is visible or an automation subscriber holds it open
(`setAutomationHold`), and retains the last snapshot otherwise.

## Inbound automation

The [automation feature](features/automation.md) is fork-owned under `Tinycast/Features/Automation/`.
`AppCore` lazily owns `AutomationCoordinator`, which owns the router, runner, audit log, client
store, approval queue, question store and HTTP endpoint. It is separate from the MCP client. The
`tinycast` stdio bridge is its own target in `project.fork.yml`, sources in `TinycastCLI/`, embedded
in the app's `Contents/Helpers`.
Tinycast owns UI tools and approved terminal commands; background dispatch belongs to the separate
agentkit MCP ([Agentkit MCP](../../agentkit/README.md#agentkit-mcp)).

## Search

Search Files and navigator global words get their candidates from the local `fsearch` daemon through
one long-lived `fsearch stdio` child that `FileSearchSession` owns (see
[file-search.md](features/file-search.md)). This is the one external-tool dependency, in the same
category as the `rg` the navigator's ⌘F scan still uses: nothing is bundled or linked, and a missing
`fsearch` shows "File search is unavailable" with no fallback engine. fsearch's order is the ranking;
the fork's fzf scorer below serves the launcher, clipboard, snippets, quicklinks and the navigator's
in-folder filter. The blank-screen recents stay on Spotlight, since fsearch has no `mtime` sort.
Settings → File Navigator shows the discovered `fsearch` path and whether it has Full Disk Access.

Every list input matches with one fzf v2 scorer, fork-owned in `Tinycast/Fork/Search/`
(`ForkFzf` scores, `ForkSearch` parses syntax and adapts it to upstream callers). `ForkSearch.setEnabled`
is the switch, turned on in `ForkAppearance.start()`; off, every hook falls through to upstream behaviour.
The scorer and syntax were settled in `prototype/fuzzy-search`; clipboard retrieval follows the owner's
revised fuzzy-search decision:

- Words are ANDed in any order; fzf extended syntax: `'exact`, `^prefix`, `suffix$`, `!exclude`. No typo tolerance.
- Every search surface uses the **fuzzy** profile (letters may be skipped); `'word` keeps an exact
  contiguous word. Clipboard positives must each clear the launcher's medium score bar, based on
  that word's folded length.
  The item filter and OCR in-loop filter use `clipboardScore`; the clipboard union carries each
  item's score through pin handling and ranking, without scoring duplicates again.
- Clipboard retrieval unions the full-history trigram FTS hits for positive words of 3+ letters
  with fuzzy-filtered resident items (the newest ~1,000, plus resident pins), deduplicating by item ID.
  FTS retains its 200-newest-hit cap and only retrieves literal long words: older skipped-letter
  matches outside the resident window remain unavailable. Plain long `!words` become FTS exclusions;
  anchored or short exclusions stay in the memory filter. Ordinary text matches rank by fzf score,
  ties newest-first; 1–2 non-space characters keep newest-first. Pins retain upstream's first-place
  handling. Fuzzy clipboard scoring scans only the first 4,096 characters of each item, including
  OCR text; skipped-letter matches beyond that prefix are unavailable. Past the prefix, words (any
  length, and `suffix$` words) match literally against the whole text and `!words` found anywhere
  reject the item; `^prefix` words are judged on the prefix. ASCII words do that literal check as a
  byte scan, so past the prefix `cafe` misses "café" (non-ASCII words fold accents). Literal matches
  use the word's self-match score when no accepted prefix alignment exists. OCR-only matches retain
  upstream's retrieval and insertion order. The scorer lowercases ASCII bytes directly and rejects
  absent subsequences before computing bonuses or alignment; non-ASCII characters keep the shared fold.
- A query of only `!words` matches nothing. Lone syntax tokens (`!`, `'`, `^`, `$`) match literally.
- File search sends the typed words to fsearch untouched, pushing only the type filter, and enforces
  scopes, ignore patterns, hidden paths and `~/Library` locally on the returned paths before the 200-row
  cap; a full page that filtering leaves short is re-queried once with a larger limit.
- Plain substring filters in Uninstall, calculator history, AI chat lists, window layouts and settings
  lists are unchanged.

## Terminal instances

The [terminal instances feature](features/terminal-instances.md) is fork-owned under
`Tinycast/Features/TerminalInstances/` and `Tinycast/Windows/TerminalInstances/`, with
`Tests/terminal-instances-test.swift` and `Tests/terminal-process-test.swift`. `AppCore` lazily
owns the coordinator and presenter and asks every shell to hang up at termination. One
`RootPaletteView.screen` branch routes a `$ command` launcher query to `TerminalCommandScreen`;
a bare `$` shows an instruction. Opening a command replaces the palette with an independent,
initially pinned panel running the feature's own persistent `forkpty` zsh session. The upstream
`Platform/PseudoTerminal.swift` and `TerminalLogView` remain unchanged.
`TerminalGhosttyLauncher` owns ⌘O's separate Ghostty shell, with the running bundle path, escaped
AppleScript and coordinator-owned cancellation described in the feature doc.

The embedded renderer links `libghostty-vt` and owns a terminal and encoders, not a full Ghostty
surface. Mouse buttons, drags, movement and captured wheel events use its mouse encoder and the
existing PTY input path on the main actor. Uncaptured scrolling retains grid scrollback; focus,
coordinate conversion and trackpad handling are described in the terminal feature doc.

## Palette chips

**Disabled** (`PaletteChipsCoordinator.isEnabled = false`, 2026-10-10): the code and hooks stay, but
every event is unhandled, so Tab, Escape and ⌘1–4 behave as upstream. When enabled, Tab in the collapsed
compact launcher toggles a pill with Applications, Files, Shortcuts and
Clipboard chips in a separate non-key child panel. The feature is fork-owned under
`Tinycast/Features/PaletteChips/` and `Tinycast/Windows/PaletteChips/`, with
`Tests/palette-chips-test.swift`; `AppCore` lazily owns its coordinator and presenter.
Clipboard is disabled when clipboard history is off. Applications and Shortcuts scope launcher
results by kind; Files and Clipboard open their existing screens carrying the query.

`RootPaletteView` hooks cover Tab, Escape, pill radius, the `⌘1–4` hint and hidden compact
favourites. `PaletteWindowController` hooks adjust the collapsed width and route number-row
favourite slots to chips, consuming unused slots while chip mode is active. `LauncherScreen`
scopes ordinary results to Applications or Shortcuts, preserving pinned command results.
With chip mode off, these hooks retain upstream behaviour. The
[feature doc](features/terminal-instances.md#tab-chips) describes navigation and placement.

## Palette presentation

A palette screen declares how the expanded window presents it: a fork-owned `PalettePresentation`
(`Tinycast/Fork/Palette/`) with a height (`.standard`, `.bar`: the search bar alone, or `.fitted(rows:)`: the bar plus exactly its
rows, capped at the standard height) and a footer policy (`.shown`, or `.hidden` with ↵ still
acting). `PalettePresentationResolver` maps the active mode and query to one; the `$` terminal
command declares `.bar` with a hidden footer. See [palette-presentation.md](features/palette-presentation.md).

## Notch bar

`AppCore.notchBar` owns a passive panel at the top of the primary display that slides out of the
notch and retracts while the launcher is active. The palette shows and hides directly. See
[notch-bar.md](features/notch-bar.md).

`AppCore.ghosttyStatus` owns the external Ghostty inventory and bounded polling. Its pure tab model
keeps Ghostty tab IDs distinct from agent runs. The [status feature note](features/ghostty-tab-status.md)
records permission, selection and agent-association verification boundaries.

## Palette motion

The palette window animates between presentations, and its header glyph, placeholder, Quick AI
menus, body and footer enter with a staggered reveal and leave with a fade. Everything is
fork-owned in `Tinycast/Fork/Motion/`: `PaletteMotion` (tokens), `PaletteFrameAnimator`
(spring-driven frame, live corner radius, fixed layout height), `paletteFrameLayout`,
`paletteFrameClip`, `paletteReveal` and `PaletteRevealSlot`. `positionPanel` stays the only
place that sizes the window; it hands the frame to the animator instead of setting it. With
Reduce Motion on, every resize is instant. See [palette-motion.md](features/palette-motion.md).

## AI working directory

The [AI working directory](features/ai-working-directory.md) lets Quick AI and AI Chat start installed
agents in a chosen folder, so Claude Code and Codex load its `CLAUDE.md` or `AGENTS.md`. The owner,
row and wiring are fork-owned: `Tinycast/Fork/ForkAIWorkingDirectory.swift`,
`ForkAIWorkingDirectoryRow.swift` and `ForkAIWorkingDirectoryWiring.swift`. `AppCore` owns it; the
wiring file adds a computed `cwd` to `InstalledCLITurnRunner` and `CodexAppServerClient` that reads
`ForkAIWorkingDirectory.current`. Upstream's `workspace` keeps its meaning, the private scratch
folder; the hooks read `cwd` only where a process starts or a directory flag is passed. Unset, `cwd`
is `workspace` and every route is upstream.

## File navigator

`Tinycast/Features/FileNavigator/` is fork-owned, alongside TerminalInstances. Browse Files, root
`~/` / `/` queries, and a terminal card's Browse here action enter a path-input palette screen.
AppCore owns the lazy coordinator and the palette environment injects it. The coordinator owns
cancellable off-main directory/subtree work, the visible-folder watcher, a separate upstream
FileSearchSession for global words, focused preview state and bookmark/recent persistence.
Upstream `Features/FileSearch/` is reused through one marked action-menu hook: Show in File Navigator
opens a result's parent folder and focuses that result after the listing loads.

The preview's expansion and scroll adapter live in FileNavigator. The split reuses `FileSearchPreview`;
expansion renders `FileSearchSurface` across the body. A weak hosting-view target reaches native text,
PDF and exposed Quick Look scroll views without changing first responder. A marked sizing hook in
`PaletteWindowController` applies fork-owned, screen-bounded 680-point body geometry while expanded.
The existing `PalettePanel` keyboard hook delivers ⌘⇧Y and Option-arrow chords before the path editor;
its native wheel delivery is unchanged. Remote Quick Look providers without scroll views ignore
keyboard scroll commands.

The editor command defaults to `fresh`; a nonblank override supplies the shell command and arguments.
The editor override lives on AppSettings and in `fileNavigator.editor` in settings.json; the new
pane owns Browse Files' alias, visibility and shortcut controls through `SettingsTab.ownedCommands`.
Backups deliberately exclude the local editor command. Bookmarks and recent paths are local,
explicitly bundle-scoped defaults and do not travel through settings.json or backups.

TerminalInstances owns editor-role geometry and key delivery. Editor cards use the largest
screen-bounded output viewport (680 scaled points rather than 340). The grid maps the requested
Command shortcuts to Fresh's default Ctrl bindings, with Cmd-Shift-Z mapped to Ctrl-Y, and otherwise
retains app chords. The log renderer falls back to a real Ghostty tab running login zsh with the same
quoted command, waiting after command exit so command-not-found output remains visible.
Hand to an agent v1 only copies an absolute-path context block; it dispatches nothing.

The path reducer and harness port only Nav's `parseInput` / `reducePath` / `actionsFor` behavior
from `proto/file-navigator`; no prototype UI, fake filesystem or alternate navigation model is copied.
See [file-navigator.md](features/file-navigator.md) for ownership, keys, bounds and runtime gaps.

### Monaco editor

`Tinycast/Features/MonacoEditor/` and `Windows/MonacoEditor/` are fork-owned: an opt-in Edit target for the
File Navigator, hosted in an offline WKWebView. Hooks, each marked `// FORK: monaco-editor`: the editor-kind
setting (`AppSettings`, `AppSettingsKey`, `SettingsFileKey`/`SettingsFileSchema`, backup coverage), the Edit
branch in `FileNavigatorCoordinator.run`, and the two lazy owners on `AppCore`. The page bundle is
generated by `Scripts/monaco-bundle`. See [monaco-editor.md](features/monaco-editor.md).
The harness is registered but implementation-session execution is prohibited.

`Tinycast.xcodeproj/project.pbxproj` is an explicit **generated exception** to inline hook markers:
XcodeGen owns it and adds the new files from `project.yml`'s source directory. It is never hand-edited;
`project.fork.yml` also adds the pure editor-key policy and its ASCII keyboard-layout helper to
TinycastPreviews' explicit source list.

## Quick AI Start Work

`Tinycast/Fork/QuickAIRoot/ForkQuickAIHandoff.swift` builds the handoff text and a single-line zsh
command using ANSI-C quoting for every argument. The first user message stays verbatim at the
front; later turns and attachment placeholders spill into the existing log owner's handoff file
when the inline prompt exceeds 32 KB of UTF-8. The first message is never shortened.

`AppCore` owns `ForkQuickAIHandoffCoordinator`. Quick AI resolves Claude Code and Codex lazily,
caching executable lookup results for the current command-path override. A set path wins or fails.
The action panel and ⌘↵ / ⌃⌘↵ use the same eligibility check; chats reopened from history are
excluded. Start Work opens an interactive CLI in the working folder (home when unset or missing),
logs only handoff metadata, clears the composer and calls `QuickAICoordinator.startNewChat()`.
Overflow writes revalidate the source chat, draft, attachments, settings and directory before
launching; a stale result leaves the current chat untouched. Start Work retires the warm root
with reason `newChat` through `startNewChat`, which also prewarms the next root.

## Claude session chat

Groups 1–4 of [Claude session chat](features/claude-session-chat.md) live in
`Tinycast/Fork/ClaudeSession/`: the background host, hook settings writer, atomic metadata registry,
transcript reader, hidden attach writer and chat provider. `AppCore` owns their coordinator,
loads the registry cache and prepares hooks at launch. Termination cancels readers and closes attach
clients without stopping daemon sessions. Groups 3–4 are implemented, unverified. Quick AI's existing handoff
uses the same fork-owned executable resolver, with its override and missing-path behaviour preserved.

Storage is channel-specific under `AppPaths.applicationSupport()/ClaudeSessions/`. All seven hooks
append stdin to one `events.jsonl`, whose payloads carry `session_id`; transcript paths come from the
agents listing or hook payloads. `registry.json` maps chat UUIDs to session metadata and offsets,
without message text; an optional ended flag persists End Session. A registered chat selects the session provider synchronously from the cache;
other chats keep upstream routing. Readers are connected on first provider use and retained for
foreign turns. Claude Start Work registers a background session and moves the chat to AI Chat; its first reply
is read without typing the handoff prompt again. Approvals offer Attach, which pauses the writer
until its terminal closes or exits. Session chats replace the model picker with a folder label
and offer Open in Terminal, End Session and Resume. Deferred launch reconciliation checks one
`agents --json --all` listing, reconnects live readers through that same provider path and marks
stopped or missing sessions ended; the writer's attach client still starts only on demand.
Resume already runs in the saved folder and retains the offset for an unchanged transcript path.
Deletion offers stop-and-remove, chat-only deletion, or cancellation through Tinycast's dialog
presenter. Only stop-and-remove runs `claude rm`; both deletion choices unregister and disconnect
before removing history. Bulk deletion preserves pinned chats and uses the original target IDs.

The reader watches the shared events file, filters by session ID, and polls the transcript every
0.5 seconds during a turn. It retains incomplete lines and waits for Stop plus a final assistant
text block, with a two-second deadline. A foreign turn's persisted offset stays at its user record
until its messages are appended, so reading part of a turn does not lose its user text on restart.
Foreign turns that precede a queued send are inserted before that send; a turn after a delivered
reply waits for its streaming bubble to finish before appending.

The writer directly spawns `claude attach <shortID>` through `TerminalProcess`, with the host's
clean environment and a PTY TERM value. Direct children expose raw output without shell marks;
shell instances keep their existing parser. The writer waits for bracketed-paste mode, queues behind
turns, approvals and an open Attach terminal, and checks the guard again before Return. Delivery
requires a matching UserPromptSubmit within five seconds; failure uses the chat's existing Retry
path and never resends automatically. The client drops after ten idle minutes. Group 3 can publish
Attach state with `setAttachTerminalOpen(_:chatID:)` and read `queuedCount(chatID:)`.
Registered chats skip upstream automatic title requests, which would otherwise start a separate
noninteractive provider invocation.

`ForkClaudeSessionDebug.swift` is a temporary `#if DEBUG` scratch hook, marked for removal before
merge. Its callable entry point and the manual Group 1 verification steps are in the spec.

## Quick AI warm root

`AppCore` owns `ForkQuickAIRoot`, wired to `CodexTurnRunner` at startup. The fork-owned state
machine has a pure reducer and logs warmed, claimed and retired roots through the existing log.
Retirement forgets the root and invalidates any pending warming result; it deletes no Codex thread.
Turning the preference off retires the root without changing the runner's normal send path.

Quick AI showing and starting a new chat schedule a background prewarm owned by the root.
`AIChatCoordinator.forkRootSnapshot` reuses the send route, composer address and scoped tool-server
session; `AIChatState.forkRequestSnapshot` is shared with normal replies. Its caller supplies the
selected Codex model and a Quick AI `AIRequest` snapshot carrying the current web-search flag, request instructions and system messages, plus the same scoped tool-server
session a send would use. The runner resolves that session's servers and computes the exact existing
`developerInstructions(for:hasTools:)` text. It supplies thread creation as a closure to the root;
the fork never owns or accesses the client. Warming and ordinary sends share one parameter builder,
including the client's working folder, ephemeral flag, sandbox, approval policy and search config.

Only a fresh Quick AI first send can claim a ready root: identity uses `chats.quickAI.holds(id)`,
the existing reopened-chat marker excludes history chats, and the request must have no preceding
non-system messages. Model, web search and complete developer instructions must match. Claiming
skips thread creation and history injection; later turns use the existing conversation cache.
A mismatch retires the ready root and falls through to ordinary thread preparation. Automatic
prewarming never blocks the palette. While warm root is enabled the app-server skips idle shutdown;
turning it off re-arms the existing 10-minute timer. New-chat entry points retire once with `newChat`,
including Start Work and the open policy. Server resets and relaunches invalidate the root with
`unavailable` or `serverRelaunched`, logging retirement and fallback metadata. The runner clears its
conversation cache as before, so a dead claimed thread takes ordinary preparation on the next send.
The next show retries warming, including when the current chat has a transcript. Reopened history
chats remain excluded. Prewarm cancellation and operation identity reject stale results; connection
and any tool-list relaunch finish before warming starts. Termination cancels owned prewarming.

## Search Google

`Tinycast/Fork/ChromeSearch/` is fork-owned. The Search Google command opens a palette screen
(`.googleSearch`) that suggests as you type, with local history and matching pages from Chrome's
history, read from a private copy. ↵ and ⌘↵ open Google's results
page in Chrome as a new tab, and the fallback does the same for the typed launcher query. Tinycast
never scripts Chrome. See [chrome-google-search.md](features/chrome-google-search.md).

## Merge playbook

1. Work from `main` and run `git merge upstream/main`. Never rebase.
2. `rerere` is enabled in this checkout. Check with `git config --get rerere.enabled`;
   enable it in a fresh clone with `git config rerere.enabled true`.
3. For a conflict in `Tinycast.xcodeproj/project.pbxproj`, take theirs:
   `git checkout --theirs -- Tinycast.xcodeproj/project.pbxproj`, then run `xcodegen generate`.
   Generated project changes do not carry hand-written hook comments.
4. Preserve the hooks below when resolving source conflicts; keep upstream's surrounding text.
5. Run `Scripts/fork-audit.sh`, then `Scripts/run-tests.sh`, then the Debug build described
   in [development.md](development.md). Run the project's lint and formatting checks too.
6. Review `git diff upstream/main --stat`; new upstream-file edits need a named hook here.

## Audit boundaries

The audit checks documented hook presence, unlisted hooks, removed fork API references in app and harness
sources, and raw font calls throughout the app, including multiline calls. Fork files and
the three typography implementations are allowed to resolve fonts. Other exceptions name
exact expressions with occurrence limits: SF Symbols, emoji/image glyphs, the Interface Size
specimen, Chat Markdown's one-point layout sentinels, Notes' snapshot fallbacks, and the
Settings alias field and segmented control's upstream fonts. Adding prose to a symbol file
does not exempt its font call. The audit also pins Theme typography and the restored Settings,
and recorder files to upstream, and rejects direct Theme font reads outside Settings
unless they have an explicit symbol-only allowance. The audit is a static guard, not a compiler or visual check.

`OverflowFade.swift` keeps explicit `Double(...)` conversions: upstream's `min(overflow.top / band, 1)` is an ambiguous operand under the local Xcode 26 toolchain (verified 2026-10-08 by a failed build). Drop the hook once upstream compiles without it.

`HyperKeyEngine.swift` declares `init(route:includesShift:)`: Xcode 26.2 makes the memberwise initializer private because the struct has private stored properties, so `HyperKeyTap` cannot call it (verified 2026-10-26 by a failed build). Drop the hook once the local toolchain matches upstream's CI Xcode.

## Upstream hooks

FileNavigator and TerminalInstances are fork-owned feature folders; terminal role, card, grid and
launcher changes live there without upstream hooks. The generated pbxproj exception is described above.


| File | Tag | Purpose |
| --- | --- | --- |
| `Tinycast/App/AppCore.swift` | `// FORK: search` | Own/wire the home index; refresh on palette opening, invalidate on preference changes, stop at quit and rerun visible searches. |
| `Tinycast/Features/Settings/AppSettings.swift` | `// FORK: search` | Load/persist the engine preference and choose its discovery-dependent default. |
| `Tinycast/Features/Settings/AppSettingsKey.swift` | `// FORK: search` | Name the bundle-local experimental engine preference. |
| `Tinycast/Features/Settings/Model/SettingsFileKey.swift` | `// FORK: search` | Declare fileNavigator.searchHidden. |
| `Tinycast/Features/Settings/SettingsFileSchema.swift` | `// FORK: search` | Bind the engine mirror. |
| `Tinycast/Features/Settings/SettingsAnchor.swift` | `// FORK: search` | Search/scroll anchor for the fork-owned engine picker. |
| `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift` | `// FORK: search` | Exclude the machine-dependent experiment from backups. |
| `docs/README.md` | `// FORK: search` | Index the ripgrep feature document. |
| `docs/features/file-search.md` | `// FORK: search` | Distinguish upstream Spotlight behavior from the fork's candidate experiment. |
| `docs/features/settings-file.md` | `// FORK: search` | Document the engine mirror. |
| `Tinycast/App/AppCore.swift` | `// FORK: file-navigator` | Own the lazy coordinator; resume on screen opening and stop at termination. |
| `Tinycast/Features/FileSearch/UI/FileSearchScreen.swift` | `// FORK: file-navigator` | Add the fork-owned Show in File Navigator action to a result's menu. |
| `Tinycast/Palette/PaletteMode.swift` | `// FORK: file-navigator` | Add fileNavigator mode, symbol and path/words placeholder. |
| `Tinycast/Palette/RootPaletteView.swift` | `// FORK: file-navigator` | Route root paths, compose the screen, query/mode lifecycle and keyboard/observers. |
| `Tinycast/Palette/PaletteEnvironment.swift` | `// FORK: file-navigator` | Inject the coordinator into palette and hosted menus. |
| `Tinycast/Palette/PalettePanel.swift` | `// FORK: file-navigator` | Forward navigator keys ahead of field/menu equivalents, including Space, Ctrl-G, ⌘⇧Y and Option-arrow preview scrolling. |
| `Tinycast/Palette/PaletteWindowController.swift` | `// FORK: file-navigator` | Stop listing, watcher, preview and pending actions on every hide; apply fork-owned screen-bounded geometry for the expanded preview. |
| `Tinycast/Features/Launcher/Model/CommandID.swift` | `// FORK: file-navigator` | Register Browse Files with symbol and normal command hotkey mapping. |
| `Tinycast/Features/Launcher/Model/CommandCatalog.swift` | `// FORK: file-navigator` | File Navigator pane owns Browse Files. |
| `Tinycast/Features/Launcher/UI/LauncherCoordinator.swift` | `// FORK: file-navigator` | Dispatch Browse Files to the coordinator. |
| `Tinycast/Features/Settings/SettingsTab.swift` | `// FORK: file-navigator` | Add the fork-owned File Navigator pane and sidebar position. |
| `Tinycast/Features/Settings/SettingsDetailView.swift` | `// FORK: file-navigator` | Render FileNavigatorSettingsView. |
| `Tinycast/Features/Settings/SettingsAnchor.swift` | `// FORK: file-navigator` | Editor and Commands search/scroll anchors. |
| `Tinycast/Features/Settings/SettingsSearchCatalog.swift` | `// FORK: file-navigator` | Include the fork-owned navigator settings search entries. |
| `Tinycast/Features/Settings/AppSettings.swift` | `// FORK: file-navigator` | Persist and load the editor override in normal bundle defaults. |
| `Tinycast/Features/Settings/AppSettingsKey.swift` | `// FORK: file-navigator` | Name the editor override preference. |
| `Tinycast/Features/Settings/Model/SettingsFileKey.swift` | `// FORK: file-navigator` | Declare fileNavigator.editor and fileNavigator.commands. |
| `Tinycast/Features/Settings/SettingsFileSchema.swift` | `// FORK: file-navigator` | Bind editor and command mirror keys using existing conventions. |
| `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift` | `// FORK: file-navigator` | Exclude the machine-local editor override from backups. |
| `Scripts/run-tests.sh` | `// FORK: file-navigator` | Register the model/editor-key harness and settings search source dependency. |
| `Tests/settings-file-test.swift` | `// FORK: file-navigator` | Account for the new fileNavigator settings mirror section. |
| `docs/README.md` | `// FORK: file-navigator` | Index the fork feature documentation. |
| `docs/architecture.md` | `// FORK: file-navigator` | Record the fork coordinator and ownership. |
| `docs/features/palette.md` | `// FORK: file-navigator` | Document the path route, mode and navigator key ownership. |
| `docs/features/terminal-instances.md` | `// FORK: file-navigator` | Document editor-role geometry, keys and Browse here origin. |
| `docs/features/settings-file.md` | `// FORK: file-navigator` | Document mirror keys and local persistence boundaries. |
| `docs/testing.md` | `// FORK: file-navigator` | Register the harness contract and deferred acceptance sweep. |
| `Tinycast/App/AppCore.swift` | `// FORK: claude-session-chat` | Own the Claude host, registry and session coordinator; load the registry cache, write hooks and schedule session reconciliation at launch; close readers and attach clients at termination without stopping daemon sessions. |
| `Tinycast/Features/AI/UI/AIChatSurfacesState.swift` | `// FORK: claude-session-chat` | Intercept single and bulk deletion for registered Claude chats; defer history removal until the session choice and unregistering finish, preserving pinned chats and the requested target IDs. |
| `Tinycast/Features/AI/UI/AIChatCoordinator.swift` | `// FORK: claude-session-chat` | Expose session controls, select the session provider for registered chat IDs, keep ended sessions read-only, reject file staging and regeneration, and skip separate automatic title requests. |
| `Tinycast/Features/AI/UI/AIChatState.swift` | `// FORK: claude-session-chat` | Start the already-submitted handoff reply without duplicating its user turn; append and save foreign turns, preserving a queued user message and its streaming reply. |
| `Tinycast/Features/AI/UI/AIChatDetailView.swift` | `// FORK: claude-session-chat` | Render fork-owned session labels and approval notices; replace the ended session composer with Resume. |
| `Tinycast/Features/AI/UI/AIChatWindowChrome.swift` | `// FORK: claude-session-chat` | Add session actions to the chat menu and suppress session regeneration. |
| `Tinycast/Features/AI/UI/AIChatSidebarView.swift` | `// FORK: claude-session-chat` | Show an approval badge on a session chat. |
| `Tinycast/Features/TerminalInstances/Service/TerminalProcess.swift` | `// FORK: claude-session-chat` | Spawn an executable directly with supplied arguments and environment; capture its raw output without shell marks while preserving shell instances. |
| `Scripts/run-tests.sh` | `// FORK: agent-runs` | Register the AgentRuns decoding harness. |
| `Tinycast/App/AppDelegate.swift` | `// FORK: previews` | Skip AppCore start and termination work when Xcode's canvas hosts the app. |
| `Tinycast/App/AppCore.swift` | `// FORK: agent-runs` | Own the monitor and coordinator; stop work at termination. |
| `Tinycast/Features/CustomCommands/Service/ShellCommandRunner.swift` | `// FORK: agent-runs` | Allow a per-call stdout limit for complete status JSON, preserving the default. |
| `Tinycast/Palette/PaletteEnvironment.swift` | `// FORK: agent-runs` | Inject the AgentRuns coordinator into the hosted stack. |
| `Tinycast/Palette/PaletteWindowController.swift` | `// FORK: agent-runs` | Forward palette visibility events to the feature. |
| `Scripts/run-tests.sh` | `// FORK: fork-search` | Register the fork search harness with the real file-query models. |
| `Tinycast/Features/Launcher/Model/SearchRelevance.swift` | `// FORK: search` | `FuzzyMatch.match` answers via fzf, tiers kept. |
| `Tinycast/Features/Launcher/Model/LauncherMatch.swift` | `// FORK: search` | Launcher alignment and sensitivity via fzf. |
| `Tinycast/Features/Snippets/UI/SnippetsScreen.swift` | `// FORK: search` | Snippet filter via fzf. |
| `Tinycast/Features/Quicklinks/UI/QuicklinkListScreen.swift` | `// FORK: search` | Quicklink filter via fzf. |
| `Tinycast/Features/Clipboard/Model/ClipboardStore.swift` | `// FORK: search` | FTS/resident union, fuzzy medium-threshold filter and rank; upstream pins. |
| `Tinycast/Features/FileSearch/Model/FileSearchQuery.swift` | `// FORK: search` | Optional supplemental glob, fuzzy root matching and filename/folder ranking. |
| `Tinycast/Features/FileSearch/Service/FileSearchService.swift` | `// FORK: search` | Run either predicate and return batches before the display cap for the merge. |
| `Tinycast/Features/FileSearch/Service/FileSearchSession.swift` | `// FORK: search` | Attach the shared index and route production nonblank queries to the fork service; injected operations and recents remain upstream. |
| `Tinycast/App/AppCore.swift` | `// FORK: notch-bar` | Own the notch bar and Ghostty status; the `notchBarEnabled` switch starts and stops both. |
| `Tinycast/Palette/PaletteWindowController.swift` | `// FORK: notch-bar` | Report session start and end to the notch bar. |
| `Scripts/run-tests.sh` | `// FORK: notch-bar` | Compile the notch geometry, policy and status-entry harness. |
| `Scripts/run-tests.sh` | `// FORK: ripgrep-ranking` | Register the existing whole-path file ranking regression harness. |
| `Tinycast/Features/FileSearch/UI/FileSearchCoordinator.swift` | `// FORK: file-navigator` | Route folder activation to the existing File Navigator. |
| `docs/features/file-search.md` | `// FORK: file-navigator` | Document existing folder activation and File Navigator actions. |
| `AGENTS.md` | `// FORK: documentation` | Link the fork maintenance guide. |
| `Tinycast/DesignSystem/Scrolling/OverflowFade.swift` | `// FORK: overflow-double` | Compile fix: explicit `Double` for the fade strengths. |
| `Tinycast/Features/HotKeys/Model/HyperKeyEngine.swift` | `// FORK: memberwise-init` | Compile fix: explicit `init(route:includesShift:)` for the local toolchain. |
| `Tinycast/Palette/RootPaletteView.swift` | `// FORK: palette-type-check` | Move upstream's compact-selection observers out of `stateObservers` so the chain type-checks. |
| `Scripts/run-tests.sh` | `// FORK: fork-harness` | Register the fork-layer harness. |
| `Scripts/run-tests.sh` | `// FORK: harness-sources` | Compile affected harnesses with real fork dependencies, including the file-session runner. |
| `Tinycast/App/AppCore.swift` | `// FORK: appearance-observation` | Refresh AppKit palette geometry after font or theme-token changes. |
| `Tinycast/App/AppCore.swift` | `// FORK: appearance-owner` | Single AppCore owner. |
| `Tinycast/App/AppCore.swift` | `// FORK: appearance-start` | Publish the current appearance at startup. |
| `Tinycast/App/MenuBarItem.swift` | `// FORK: status-icon` | Prefer the fork menu-bar image. |
| `Tinycast/DesignSystem/BarButton.swift` | `// FORK: named-asset` | Prefer the namespaced fork image, then upstream. |
| `Tinycast/DesignSystem/BarButton.swift` | `// FORK: bar-button` | `BarButtonChrome` and `BarButton` live in their own file so the preview target compiles them alone. |
| `Tinycast/DesignSystem/InterfaceMetrics.swift` | `// FORK: code-font` | Route code and inline code through the chosen monospaced family, else the system face. |
| `Tinycast/DesignSystem/InterfaceMetrics.swift` | `// FORK: symbol-font` | Keep symbol sizing on the system face. |
| `Tinycast/DesignSystem/InterfaceMetrics.swift` | `// FORK: typography-metrics` | Resolve standard and scaled prose through the fork typography cache. |
| `Tinycast/DesignSystem/PopoverMenu.swift` | `// FORK: named-asset` | Prefer the namespaced fork image, then upstream. |
| `Tinycast/DesignSystem/SymbolImage.swift` | `// FORK: named-asset` | Prefer the namespaced fork image, then upstream. |
| `Tinycast/DesignSystem/Theme.swift` | `// FORK: color-tokens` | Resolve optional dark/light pair overrides at adaptive; ramp delegates here. |
| `Tinycast/Features/AI/Settings/AIProvidersPanel.swift` | `// FORK: named-asset` | Prefer the namespaced fork image, then upstream. |
| `Tinycast/Features/AI/UI/AIChatDetailView.swift` | `// FORK: named-asset` | Prefer the namespaced fork image, then upstream. |
| `Tinycast/Features/AI/UI/AIChatSplitViewController.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Features/AI/UI/ChatComposerTextView.swift` | `// FORK: prose-font` | Route AppKit or explicit-size prose through fork typography. |
| `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift` | `// FORK: font-persistence` | Retain the existing font key and backup exclusion. |
| `Tinycast/Features/Calendar/UI/CameraPreviewController.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Features/Calendar/UI/CameraPreviewView.swift` | `// FORK: typography` | Route non-Settings token reads through metrics; symbols stay system. |
| `Tinycast/Features/Camera/UI/CameraCoordinator.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Features/Camera/UI/CameraStage.swift` | `// FORK: typography` | Route non-Settings token reads through metrics; symbols stay system. |
| `Tinycast/Features/Clipboard/UI/ClipDrag.swift` | `// FORK: prose-font` | Route AppKit or explicit-size prose through fork typography. |
| `Tinycast/Features/CustomCommands/UI/CommandOutputView.swift` | `// FORK: command-duration` | `CommandDuration` lives in its own file so the preview target compiles it alone. |
| `Tinycast/Features/CustomCommands/UI/CommandOutputPresenter.swift` | `// FORK: command-run` | `CommandOutcome` and `CommandRun` live in their own file so the preview target compiles them alone. |
| `Tinycast/Features/CustomCommands/UI/CommandOutputView.swift` | `// FORK: typography` | Route non-Settings token reads through metrics; symbols stay system. |
| `Tinycast/Features/Dictation/UI/DictationPanel.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Features/Extensions/UI/ExtensionDetailView.swift` | `// FORK: prose-font` | Route AppKit or explicit-size prose through fork typography. |
| `Tinycast/Features/Extensions/UI/ExtensionListPanel.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Features/Launcher/Settings/LauncherItemsTable.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Features/Notes/UI/NoteBlockDecoration.swift` | `// FORK: notes-font-snapshot` | Carry font name and size across the Sendable decoration boundary. |
| `Tinycast/Features/Notes/UI/NoteBlockLayoutFragment.swift` | `// FORK: notes-font-snapshot` | Carry font name and size across the Sendable decoration boundary. |
| `Tinycast/Features/Notes/UI/NoteEditorView.swift` | `// FORK: notes-font-refresh` | Restyle the open editor when the font changes. |
| `Tinycast/Features/Notes/UI/NoteHeadingMenuView.swift` | `// FORK: typography` | Route non-Settings token reads through metrics; symbols stay system. |
| `Tinycast/Features/Notes/UI/NoteHeadingMenuWindowController.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Features/Notes/UI/NoteMarkdownStyler.swift` | `// FORK: notes-font-refresh` | Restyle the open editor when the font changes. |
| `Tinycast/Features/Notes/UI/NoteMarkdownStyler.swift` | `// FORK: notes-font-snapshot` | Carry font name and size across the Sendable decoration boundary. |
| `Tinycast/Features/Notes/UI/NoteMarkdownTypography.swift` | `// FORK: notes-font` | Resolve Notes prose through the fork cache. |
| `Tinycast/Features/Notes/UI/NoteSwitcherView.swift` | `// FORK: typography` | Route non-Settings token reads through metrics; symbols stay system. |
| `Tinycast/Features/Notes/UI/NoteSwitcherWindowController.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Features/Notes/UI/NotesView.swift` | `// FORK: typography` | Route non-Settings token reads through metrics; symbols stay system. |
| `Tinycast/Features/Notes/UI/NotesWindowController.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Features/QuickActions/UI/QuickActionPanelController.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Features/Settings/AppSettingsKey.swift` | `// FORK: font-persistence` | Retain the existing font key and backup exclusion. |
| `Tinycast/Features/Settings/Model/SettingsFileKey.swift` | `// FORK: font-persistence` | Retain the existing font key and backup exclusion. |
| `Tinycast/Features/Settings/Panes/GeneralSettingsView.swift` | `// FORK: named-asset` | Prefer the namespaced fork image, then upstream. |
| `Tinycast/Features/Settings/SettingsEditorPresenter.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Features/Settings/SettingsFileSchema.swift` | `// FORK: font-mirror` | Bind settings.json directly to ForkAppearance. |
| `Tinycast/Features/Settings/SettingsSearchCatalog.swift` | `// FORK: font-search` | Register the Fork-owned settings search entry. |
| `Tinycast/Features/WindowManagement/UI/RoomPreviewController.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Palette/PaletteEnvironment.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Platform/Images/IconCache.swift` | `// FORK: named-asset` | Prefer the namespaced fork image, then upstream. |
| `Tinycast/Windows/About/AboutView.swift` | `// FORK: named-asset` | Prefer the namespaced fork image, then upstream. |
| `Tinycast/Windows/AppWindowController.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Windows/Dialog/DialogController.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Windows/HUD/HUDPresenter.swift` | `// FORK: accent-scope` | Apply the optional accent at a hosting boundary. |
| `Tinycast/Windows/HUD/VolumeHUDView.swift` | `// FORK: typography` | Route non-Settings token reads through metrics; symbols stay system. |
| `project.yml` | `// FORK: project-include` | Include fork build configuration. |
| `Scripts/run-tests.sh` | `// FORK: terminal-instances` | Register the terminal model and real-zsh process harnesses. |
| `Scripts/run-tests.sh` | `// FORK: palette-chips` | Register the chip state-machine and layout harness. |
| `Tinycast/App/AppCore.swift` | `// FORK: terminal-instances` | Lazily own the coordinator and presenter; hang up every session at termination. |
| `Tinycast/App/AppCore.swift` | `// FORK: palette-chips` | Lazily own the chips coordinator and presenter. |
| `Tinycast/App/AppCore.swift` | `// FORK: automation` | Lazily own the inbound automation coordinator; start it after MCP, offer it each opened URL first, stop it at termination. |
| `Tinycast/Features/Settings/Panes/GeneralSettingsView.swift` | `// FORK: automation-settings` | Marks where the Automation section left for its own pane. |
| `Tinycast/Features/Settings/SettingsTab.swift` | `// FORK: automation-settings` | The `automation` tab: title, icon, and its place at the end of Features. |
| `Tinycast/Features/Settings/SettingsDetailView.swift` | `// FORK: automation-settings` | Route the tab to `AutomationSettingsView`. |
| `Tinycast/Features/Settings/SettingsSearchCatalog.swift` | `// FORK: automation-settings` | Index the pane's entries (`ForkSettingsSearch.automation`). |
| `Tinycast/App/AppCore.swift` | `// FORK: automation` | Route the automation approval dialog to `DialogController`. |
| `Tinycast/Windows/Dialog/DialogRequest.swift` | `// FORK: automation` | The `automationApproval` accessory case. |
| `Tinycast/Windows/Dialog/DialogController.swift` | `// FORK: automation` | `approveAutomation`, its width, and the hook that lets an expired approval close its dialog. |
| `Tinycast/Windows/Dialog/DialogView.swift` | `// FORK: automation` | Render the approval's labelled fields. |
| `Tinycast/Info.plist` | `FORK: automation` (XML comment) | Claim the bundle id as a second URL scheme so automation links reach one channel. |
| `Tinycast/Info.plist` | `// FORK: terminal-ghostty` | Preserve the system-action permission explanation and add Ghostty handoff. |
| `Tinycast/Palette/RootPaletteView.swift` | `// FORK: terminal-instances` | Route standalone `$` launcher queries to the terminal command screen. |
| `Tinycast/Palette/RootPaletteView.swift` | `// FORK: palette-chips` | Toggle chips with Tab in the collapsed bar; handle empty-query Escape; set pill radius, show the `⌘1–4` hint and hide compact favourites. |
| `Tinycast/Palette/PaletteWindowController.swift` | `// FORK: palette-chips` | Route number-row favourite slots to active chips and consume unused slots; set collapsed pill width. |
| `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | `// FORK: palette-chips` | Scope ordinary launcher results to Applications or Shortcuts while preserving pinned command results. |
| `Tinycast/Palette/PaletteWindowController.swift` | `// FORK: palette-presentation` | Ask the active presentation for the expanded window height. |
| `Tinycast/Palette/RootPaletteView.swift` | `// FORK: palette-presentation` | Resolve the presentation, hide the body and footer when it says so and resize the window when it changes. |
| `Tinycast/Palette/PaletteWindowController.swift` | `// FORK: palette-motion` | Own the frame animator, inject it into the palette tree and move the panel through it. |
| `Tinycast/Palette/RootPaletteView.swift` | `// FORK: palette-motion` | Put the body and footer in reveal slots, lay out at the animated height, clip to the live radius and reveal the header glyph, placeholder and Quick AI menus. |
| `Tinycast/App/AppCore.swift` | `// FORK: ai-working-directory` | Own the working-directory setting and wire it at startup. |
| `Tinycast/Features/AI/Service/InstalledCLIProvider.swift` | `// FORK: ai-working-directory` | Widen the runner and its `workspace` for the fork's `cwd`; use `cwd` for the process and directory flags. |
| `Tinycast/Features/AI/Service/CodexAppServerClient.swift` | `// FORK: ai-working-directory` | Use the fork's `cwd` for the app-server and `mcp list`; `workspace` stays scratch. |
| `Tinycast/Features/AI/Service/CodexTurnRunner.swift` | `// FORK: ai-working-directory` | Start threads in the client's `cwd`. |
| `Tinycast/Features/AI/Settings/AISettingsView.swift` | `// FORK: ai-working-directory` | Show the Working folder row in the Chat section. |
| `Tinycast/Features/Settings/AppSettingsKey.swift` | `// FORK: ai-working-directory` | Name the `aiWorkingDirectory` defaults key. |
| `Tinycast/Features/Settings/Model/SettingsFileKey.swift` | `// FORK: ai-working-directory` | Mirror it as `ai.workingDirectory`. |
| `Tinycast/Features/Settings/SettingsFileSchema.swift` | `// FORK: ai-working-directory` | Bind the mirror with the folder rule. |
| `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift` | `// FORK: ai-working-directory` | Keep the folder out of backups. |
| `Tinycast/Features/Settings/SettingsSearchCatalog.swift` | `// FORK: ai-working-directory` | Make the row searchable. |
| `Tinycast/App/AppCore.swift` | `// FORK: quick-ai-root` | Own the Quick AI root state machine, settings, log and handoff coordinator; wire the root to the runner at startup, start pruning at launch and stop pruning, prewarming and pending handoffs on termination. |
| `Tinycast/Features/AI/Service/CodexTurnRunner.swift` | `// FORK: quick-ai-root` | Hold the injected fork root; expose explicit warming with existing developer instructions and runner-owned client effects; share thread-start parameters; claim matching fresh Quick AI roots before ordinary thread creation; invalidate roots on reset/exit and tool-list relaunch while retaining existing conversation cleanup. |
| `Tinycast/Features/AI/Service/ChatGPTSubscriptionManager.swift` | `// FORK: quick-ai-root` | Accept the fork's keep-alive flag, cancel idle shutdown while enabled and re-arm the original timer when disabled. |
| `Tinycast/Features/AI/UI/AIChatState.swift` | `// FORK: quick-ai-root` | Share the existing request snapshot builder between replies and prewarming. |
| `Tinycast/Features/AI/UI/AIChatCoordinator.swift` | `// FORK: quick-ai-root` | Expose a prewarm snapshot using the existing model, provider, composer address, tool session, instructions, web search and context budget. |
| `Tinycast/Features/AI/UI/AIScreen.swift` | `// FORK: quick-ai-root` | Add fork-owned Start Work menu items and secondary/tertiary actions; resolve engines in a view-owned task. |
| `Tinycast/Features/AI/UI/QuickAICoordinator.swift` | `// FORK: quick-ai-root` | Expose the fork-owned handoff coordinator and mark history chats as reopened; schedule prewarming after show/new chat; retire roots on explicit new chat, open-policy reset and ask. |
| `Tinycast/Features/AI/Settings/AISettingsView.swift` | `// FORK: quick-ai-root` | Show the fork-owned Quick AI settings section. |
| `Tinycast/Features/Settings/AppSettingsKey.swift` | `// FORK: quick-ai-root` | Name the warm-root, Start Work engine and log-retention defaults keys. |
| `Tinycast/Features/Settings/Model/SettingsFileKey.swift` | `// FORK: quick-ai-root` | Mirror the three preferences under `ai`. |
| `Tinycast/Features/Settings/SettingsFileSchema.swift` | `// FORK: quick-ai-root` | Bind the three mirror keys to the fork-owned settings. |
| `Tinycast/Features/Backup/Model/SettingsBackup.swift` | `// FORK: quick-ai-root` | Carry the three optional preferences; gather and restore them through fork-owned helpers. |
| `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift` | `// FORK: quick-ai-root` | Include all three Quick AI root preferences in backups. |
| `Tinycast/Features/Settings/SettingsSearchCatalog.swift` | `// FORK: quick-ai-root` | Add the fork-owned Quick AI settings search entries. |
| `Tinycast/App/AppCore.swift` | `// FORK: appearance-theme` | Own the theme-token store and publish it at startup. |
| `Tinycast/App/AppCore.swift` | `// FORK: color-theme` | A colour theme pins `NSApp.appearance` to its base; re-apply when it changes. |
| `Tinycast/DesignSystem/InterfaceMetrics.swift` | `// FORK: appearance-theme` | Palette tokens at the metrics seam: `spacing.rowVertical`, `radius.row`, `size.headerPadding`, `typography.searchFieldSize`. |
| `Tinycast/Palette/RootPaletteView.swift` | `// FORK: appearance-theme` | Draw the palette scrim from the theme tokens. |
| `Tinycast/Features/AI/UI/ChatHistoryView.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/Calculator/UI/CalculatorHistoryView.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/Calendar/UI/ScheduleView.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/Clipboard/UI/ClipboardView.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/CustomCommands/UI/CustomCommandListView.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/Extensions/UI/ExtensionListView.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/FileSearch/UI/FileSearchList.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/Launcher/UI/LauncherList.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/MenuSearch/UI/MenuSearchList.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/Quicklinks/UI/QuicklinkListView.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/Snippets/UI/SnippetsListView.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/Uninstall/UI/UninstallView.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/WindowManagement/UI/RoomPickerList.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/WindowManagement/UI/RoomsList.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/WindowSwitcher/UI/WindowSwitchList.swift` | `// FORK: appearance-theme` | Row vertical padding through `spacing.rowVertical`. |
| `Tinycast/Features/Settings/AppSettingsKey.swift` | `// FORK: appearance-theme` | Name the `forkTheme` defaults key. |
| `Tinycast/Features/Settings/Model/SettingsFileKey.swift` | `// FORK: appearance-theme` | Mirror the tokens as `appearance.tokens`. |
| `Tinycast/Features/Settings/SettingsFileSchema.swift` | `// FORK: appearance-theme` | Bind `appearance.tokens` to the token store. |
| `Tinycast/Features/Backup/Model/SettingsBackup.swift` | `// FORK: appearance-theme` | Carry `appearanceTokens` in the settings backup and restore it on import. |
| `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift` | `// FORK: appearance-theme` | Pair `appearanceTokens` with the `forkTheme` key. |
| `Tinycast/Features/Settings/SettingsTab.swift` | `// FORK: appearance-pane` | The Appearance tab: case, title, symbol and its sidebar slot after General. |
| `Tinycast/Features/Settings/SettingsDetailView.swift` | `// FORK: appearance-pane` | Route the tab to `AppearanceSettingsView`. |
| `Tinycast/Features/Settings/SettingsAnchor.swift` | `// FORK: appearance-pane` | Point `generalAppearance` at the Appearance pane, titled General. |
| `Tinycast/Features/Settings/SettingsSearchCatalog.swift` | `// FORK: appearance-pane` | List the pane, its sections and every token row. |
| `Tinycast/Features/Settings/Panes/GeneralSettingsView.swift` | `// FORK: appearance-pane` | Drop the Appearance section; make `WindowModeRow` and `InterfaceSizeRow` internal for the fork pane. |
| `Tinycast/App/AppCore.swift` | `// FORK: chrome-search` | Own the Search Google session (with its Chrome history reader), history and its lazy coordinator. |
| `Tinycast/Palette/PaletteMode.swift` | `// FORK: chrome-search` | Add the `googleSearch` mode with its symbol and placeholder. |
| `Tinycast/Palette/PaletteEnvironment.swift` | `// FORK: chrome-search` | Inject the Search Google session into the palette. |
| `Tinycast/Palette/RootPaletteView.swift` | `// FORK: chrome-search` | Route the screen; feed the query to the session, and reset it on leaving the mode or hiding. |
| `Tinycast/Features/Launcher/Model/CommandID.swift` | `// FORK: chrome-search` | Register Search Google with its title and symbol. |
| `Tinycast/Features/Launcher/Model/Fallback.swift` | `// FORK: chrome-search` | Add the Search Google fallback, its command and open verb. |
| `Tinycast/Features/Launcher/UI/LauncherCoordinator.swift` | `// FORK: chrome-search` | Dispatch the Search Google command. |
| `Tinycast/Features/Launcher/UI/FallbackCoordinator.swift` | `// FORK: chrome-search` | Open the typed query on Google in Chrome; gate it on the command's visibility. |
| `Scripts/run-tests.sh` | `// FORK: chrome-search` | Register the Search Google harness. |

## Refactor inventory

Snapshot against `upstream/main` (`71279c8d`) after refactoring `a506eda`. Counts are added
and removed lines, not net lines. New Fork-owned files are excluded from the upstream footprint.

| Upstream file | FORK tags | Added | Removed |
| --- | --- | ---: | ---: |
| `AGENTS.md` | `documentation` | 2 | 0 |
| `Scripts/run-tests.sh` | `fork-harness`, `harness-sources` | 17 | 0 |
| `Tinycast.xcodeproj/project.pbxproj` | Generated by XcodeGen | 54 | 2 |
| `Tinycast/App/AppCore.swift` | `appearance-observation`, `appearance-owner`, `appearance-start` | 4 | 0 |
| `Tinycast/App/MenuBarItem.swift` | `status-icon` | 1 | 1 |
| `Tinycast/DesignSystem/BarButton.swift` | `named-asset` | 1 | 1 |
| `Tinycast/DesignSystem/InterfaceMetrics.swift` | `code-font`, `symbol-font`, `typography-metrics` | 48 | 16 |
| `Tinycast/DesignSystem/PopoverMenu.swift` | `named-asset` | 1 | 1 |
| `Tinycast/DesignSystem/SymbolImage.swift` | `named-asset` | 2 | 2 |
| `Tinycast/DesignSystem/Theme.swift` | `color-tokens` | 1 | 1 |
| `Tinycast/Features/AI/Settings/AIProvidersPanel.swift` | `named-asset` | 2 | 1 |
| `Tinycast/Features/AI/UI/AIChatDetailView.swift` | `named-asset` | 1 | 1 |
| `Tinycast/Features/AI/UI/AIChatSplitViewController.swift` | `accent-scope` | 5 | 2 |
| `Tinycast/Features/AI/UI/ChatComposerTextView.swift` | `prose-font` | 3 | 1 |
| `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift` | `font-persistence` | 4 | 0 |
| `Tinycast/Features/Calendar/UI/CameraPreviewController.swift` | `accent-scope` | 1 | 1 |
| `Tinycast/Features/Calendar/UI/CameraPreviewView.swift` | `typography` | 3 | 2 |
| `Tinycast/Features/Camera/UI/CameraCoordinator.swift` | `accent-scope` | 2 | 1 |
| `Tinycast/Features/Camera/UI/CameraStage.swift` | `typography` | 2 | 1 |
| `Tinycast/Features/Clipboard/UI/ClipDrag.swift` | `prose-font` | 2 | 1 |
| `Tinycast/Features/CustomCommands/UI/CommandOutputView.swift` | `command-duration`, `typography` | 7 | 13 |
| `Tinycast/Features/Dictation/UI/DictationPanel.swift` | `accent-scope` | 4 | 1 |
| `Tinycast/Features/Extensions/UI/ExtensionDetailView.swift` | `prose-font` | 5 | 1 |
| `Tinycast/Features/Extensions/UI/ExtensionListPanel.swift` | `accent-scope` | 1 | 0 |
| `Tinycast/Features/Launcher/Settings/LauncherItemsTable.swift` | `accent-scope` | 1 | 0 |
| `Tinycast/Features/Notes/UI/NoteBlockDecoration.swift` | `notes-font-snapshot` | 8 | 2 |
| `Tinycast/Features/Notes/UI/NoteBlockLayoutFragment.swift` | `notes-font-snapshot` | 6 | 2 |
| `Tinycast/Features/Notes/UI/NoteEditorView.swift` | `notes-font-refresh` | 11 | 0 |
| `Tinycast/Features/Notes/UI/NoteHeadingMenuView.swift` | `typography` | 5 | 2 |
| `Tinycast/Features/Notes/UI/NoteHeadingMenuWindowController.swift` | `accent-scope` | 2 | 1 |
| `Tinycast/Features/Notes/UI/NoteMarkdownStyler.swift` | `notes-font-refresh`, `notes-font-snapshot` | 19 | 9 |
| `Tinycast/Features/Notes/UI/NoteMarkdownTypography.swift` | `notes-font` | 11 | 4 |
| `Tinycast/Features/Notes/UI/NoteSwitcherView.swift` | `typography` | 2 | 1 |
| `Tinycast/Features/Notes/UI/NoteSwitcherWindowController.swift` | `accent-scope` | 1 | 1 |
| `Tinycast/Features/Notes/UI/NotesView.swift` | `typography` | 5 | 4 |
| `Tinycast/Features/Notes/UI/NotesWindowController.swift` | `accent-scope` | 1 | 1 |
| `Tinycast/Features/QuickActions/UI/QuickActionPanelController.swift` | `accent-scope` | 1 | 1 |
| `Tinycast/Features/Settings/AppSettingsKey.swift` | `font-persistence` | 2 | 0 |
| `Tinycast/Features/Settings/Model/SettingsFileKey.swift` | `font-persistence` | 2 | 0 |
| `Tinycast/Features/Settings/Panes/GeneralSettingsView.swift` | `font-picker`, `named-asset` | 3 | 1 |
| `Tinycast/Features/Settings/SettingsEditorPresenter.swift` | `accent-scope` | 2 | 1 |
| `Tinycast/Features/Settings/SettingsFileSchema.swift` | `font-mirror` | 3 | 0 |
| `Tinycast/Features/Settings/SettingsSearchCatalog.swift` | `font-search` | 2 | 0 |
| `Tinycast/Features/WindowManagement/UI/RoomPreviewController.swift` | `accent-scope` | 2 | 1 |
| `Tinycast/Palette/PaletteEnvironment.swift` | `accent-scope` | 1 | 0 |
| `Tinycast/Platform/Images/IconCache.swift` | `named-asset` | 1 | 1 |
| `Tinycast/Windows/About/AboutView.swift` | `named-asset` | 1 | 1 |
| `Tinycast/Windows/AppWindowController.swift` | `accent-scope` | 2 | 1 |
| `Tinycast/Windows/Dialog/DialogController.swift` | `accent-scope` | 2 | 1 |
| `Tinycast/Windows/HUD/HUDPresenter.swift` | `accent-scope` | 1 | 1 |
| `Tinycast/Windows/HUD/VolumeHUDView.swift` | `typography` | 2 | 1 |
| `project.yml` | `project-include` | 1 | 0 |

Total: **52 upstream files, +255/−76 lines**. Excluding the generated project: **51 files, +201/−74 lines**.

All files changed from `a506eda` (including files restored exactly to upstream):

- `AGENTS.md` — edited.
- `Scripts/run-tests.sh` — edited.
- `Tests/interface-font-test.swift` — deleted.
- `Tests/interface-size-test.swift` — restored to upstream.
- `Tests/notes-editor-performance.swift` — restored to upstream.
- `Tests/notes-editor-test.swift` — restored to upstream.
- `Tests/palette-placement-test.swift` — restored to upstream.
- `Tests/quicklink-coordinator-test.swift` — restored to upstream.
- `Tinycast.xcodeproj/project.pbxproj` — edited.
- `Tinycast/App/AppCore.swift` — edited.
- `Tinycast/App/MenuBarItem.swift` — edited.
- `Tinycast/DesignSystem/BarButton.swift` — edited.
- `Tinycast/DesignSystem/InterfaceMetrics.swift` — edited.
- `Tinycast/DesignSystem/PopoverMenu.swift` — edited.
- `Tinycast/DesignSystem/Scrolling/OverflowFade.swift` — `overflow-double` compile fix.
- `Tinycast/Features/HotKeys/Model/HyperKeyEngine.swift` — `memberwise-init` compile fix.
- `Tinycast/DesignSystem/SettingsComponents.swift` — restored to upstream.
- `Tinycast/DesignSystem/SteadySegmentedPicker.swift` — restored to upstream.
- `Tinycast/DesignSystem/SymbolImage.swift` — edited.
- `Tinycast/DesignSystem/Theme.swift` — edited.
- `Tinycast/Features/AI/Settings/AIProvidersPanel.swift` — edited.
- `Tinycast/Features/AI/UI/AIChatCoordinator.swift` — restored to upstream.
- `Tinycast/Features/AI/UI/AIChatDetailView.swift` — edited.
- `Tinycast/Features/AI/UI/AIChatSidebarView.swift` — restored to upstream.
- `Tinycast/Features/AI/UI/AIChatSplitViewController.swift` — edited.
- `Tinycast/Features/AI/UI/AIChatWindowChrome.swift` — restored to upstream.
- `Tinycast/Features/AI/UI/AIEmptyState.swift` — restored to upstream.
- `Tinycast/Features/AI/UI/ChatComposerTextView.swift` — edited.
- `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift` — edited.
- `Tinycast/Features/Calculator/UI/CalculatorCardView.swift` — restored to upstream.
- `Tinycast/Features/Calendar/UI/CalendarCoordinator.swift` — restored to upstream.
- `Tinycast/Features/Calendar/UI/CameraPreviewController.swift` — edited.
- `Tinycast/Features/Calendar/UI/CameraPreviewView.swift` — edited.
- `Tinycast/Features/Camera/UI/CameraCoordinator.swift` — edited.
- `Tinycast/Features/Camera/UI/CameraStage.swift` — edited.
- `Tinycast/Features/Camera/UI/CameraView.swift` — restored to upstream.
- `Tinycast/Features/Clipboard/UI/ClipDrag.swift` — edited.
- `Tinycast/Features/Clipboard/UI/ClipboardScreen.swift` — restored to upstream.
- `Tinycast/Features/Clipboard/UI/ClipboardView.swift` — restored to upstream.
- `Tinycast/Features/Clipboard/UI/ColorPreview.swift` — restored to upstream.
- `Tinycast/Features/Clipboard/UI/FilePreviewStage.swift` — restored to upstream.
- `Tinycast/Features/CustomCommands/UI/CommandOutputPresenter.swift` — restored to upstream.
- `Tinycast/Features/CustomCommands/UI/CommandOutputView.swift` — edited.
- `Tinycast/Features/CustomCommands/UI/TerminalLogView.swift` — restored to upstream.
- `Tinycast/Features/Dictation/UI/DictationPanel.swift` — edited.
- `Tinycast/Features/Extensions/UI/ExtensionDetailView.swift` — edited.
- `Tinycast/Features/Extensions/UI/ExtensionListPanel.swift` — edited.
- `Tinycast/Features/FileSearch/UI/FileSearchPreview.swift` — restored to upstream.
- `Tinycast/Features/FileSearch/UI/FileSearchScreen.swift` — restored to upstream.
- `Tinycast/Features/Launcher/Settings/LauncherItemsTable.swift` — edited.
- `Tinycast/Features/Launcher/UI/ColorCard.swift` — restored to upstream.
- `Tinycast/Features/Launcher/UI/LauncherScreen.swift` — restored to upstream.
- `Tinycast/Features/Notes/UI/NoteBlockDecoration.swift` — edited.
- `Tinycast/Features/Notes/UI/NoteBlockLayoutFragment.swift` — edited.
- `Tinycast/Features/Notes/UI/NoteEditorView.swift` — edited.
- `Tinycast/Features/Notes/UI/NoteFormattingBar.swift` — restored to upstream.
- `Tinycast/Features/Notes/UI/NoteHeadingMenuView.swift` — edited.
- `Tinycast/Features/Notes/UI/NoteHeadingMenuWindowController.swift` — edited.
- `Tinycast/Features/Notes/UI/NoteMarkdownRenderer.swift` — restored to upstream.
- `Tinycast/Features/Notes/UI/NoteMarkdownStyler.swift` — edited.
- `Tinycast/Features/Notes/UI/NoteMarkdownTypography.swift` — edited.
- `Tinycast/Features/Notes/UI/NoteSwitcherView.swift` — edited.
- `Tinycast/Features/Notes/UI/NoteSwitcherWindowController.swift` — edited.
- `Tinycast/Features/Notes/UI/NoteTextView.swift` — restored to upstream.
- `Tinycast/Features/Notes/UI/NotesView.swift` — edited.
- `Tinycast/Features/Notes/UI/NotesWindowController.swift` — edited.
- `Tinycast/Features/QuickActions/UI/QuickActionCoordinator.swift` — restored to upstream.
- `Tinycast/Features/QuickActions/UI/QuickActionPanelController.swift` — edited.
- `Tinycast/Features/Quicklinks/UI/QuicklinkArgumentsAccessory.swift` — restored to upstream.
- `Tinycast/Features/Quicklinks/UI/QuicklinkListScreen.swift` — restored to upstream.
- `Tinycast/Features/Settings/AppSettings.swift` — restored to upstream.
- `Tinycast/Features/Settings/AppSettingsKey.swift` — edited.
- `Tinycast/Features/Settings/FontCatalog.swift` — deleted.
- `Tinycast/Features/Settings/InterfaceSize.swift` — restored to upstream.
- `Tinycast/Features/Settings/Model/SettingsFileKey.swift` — edited.
- `Tinycast/Features/Settings/Panes/GeneralSettingsView.swift` — edited.
- `Tinycast/Features/Settings/SettingsEditorPresenter.swift` — edited.
- `Tinycast/Features/Settings/SettingsFileSchema.swift` — edited.
- `Tinycast/Features/Settings/SettingsSearchCatalog.swift` — edited.
- `Tinycast/Features/Snippets/UI/SnippetsListView.swift` — restored to upstream.
- `Tinycast/Features/Snippets/UI/SnippetsScreen.swift` — restored to upstream.
- `Tinycast/Features/WindowManagement/UI/RoomCoordinator.swift` — restored to upstream.
- `Tinycast/Features/WindowManagement/UI/RoomPreviewController.swift` — edited.
- `Tinycast/Features/WindowManagement/UI/RoomPreviewView.swift` — restored to upstream.
- `Tinycast/Palette/EmptyResults.swift` — restored to upstream.
- `Tinycast/Palette/MenuPanel.swift` — restored to upstream.
- `Tinycast/Palette/PaletteEnvironment.swift` — edited.
- `Tinycast/Palette/PaletteWindowController.swift` — restored to upstream.
- `Tinycast/Platform/Images/IconCache.swift` — edited.
- `Tinycast/Windows/About/AboutView.swift` — edited.
- `Tinycast/Windows/AppWindowController.swift` — edited.
- `Tinycast/Windows/Dialog/DialogController.swift` — edited.
- `Tinycast/Windows/HUD/HUDPresenter.swift` — edited.
- `Tinycast/Windows/HUD/MessageHUDController.swift` — restored to upstream.
- `Tinycast/Windows/HUD/VolumeHUDController.swift` — restored to upstream.
- `Tinycast/Windows/HUD/VolumeHUDView.swift` — edited.
- `docs/features/notes.md` — restored to upstream.
- `docs/features/settings-file.md` — restored to upstream.
- `docs/testing.md` — restored to upstream.
- `docs/ui.md` — restored to upstream.
- `project.yml` — edited.
- `Scripts/fork-audit.sh` — new.
- `Tests/fork-layer-test.swift` — new.
- `Tinycast/Fork/FontCatalog.swift` — new.
- `Tinycast/Fork/ForkAppIcon.icon/Assets/thunder.svg` — new.
- `Tinycast/Fork/ForkAppIcon.icon/icon.json` — new.
- `Tinycast/Fork/ForkAppearance.swift` — new.
- `Tinycast/Fork/ForkAppearanceScope.swift` — new.
- `Tinycast/Fork/ForkAssets.swift` — new.
- `Tinycast/Fork/ForkAssets.xcassets/Contents.json` — new.
- `Tinycast/Fork/ForkAssets.xcassets/Fork/Contents.json` — new.
- `Tinycast/Fork/ForkColors.swift` — new.
- `Tinycast/Fork/ForkFontRow.swift` — new.
- `Tinycast/Fork/ForkFontSnapshot.swift` — new.
- `Tinycast/Fork/ForkSettingsSearch.swift` — new.
- `Tinycast/Fork/ForkTypography.swift` — new.
- `docs/fork.md` — new.
- `project.fork.yml` — new.
