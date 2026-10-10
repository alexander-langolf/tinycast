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

Choose an interface font and a monospaced font in Settings → General → Appearance. The monospaced
picker is the same `ForkFontRow` with `kind: .monospaced`, listing only families with a fixed-pitch
face (`FontCatalog.monospacedFamilies`); `ForkTypography.monoFace` resolves them from the system
monospaced font so weight and italic carry over. Notes' editor code styles and `TerminalLogView`
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
fork choices; the font picker remains the user-facing preference.

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
live in `project.fork.yml`; regenerate the Xcode project after changing them.

## Background agent runs

The [AgentRuns feature](features/agent-runs.md) is fork-owned under `Tinycast/Features/AgentRuns/`
and `Tinycast/Windows/AgentRuns/`, with its own documentation and `Tests/agent-runs-test.swift`.
`AppCore` owns its monitor, coordinator and panel presenter. Palette integration consists of tagged
lifecycle and geometry calls; the presenter owns observation, child-panel management and placement.
Feature-only dimensions live in `AgentRunsMetrics`, leaving Theme and InterfaceMetrics unchanged.
Polling runs only while the palette is visible and retains the last snapshot when hidden.

## Search

Every list input matches with one fzf v2 scorer, fork-owned in `Tinycast/Fork/Search/`
(`ForkFzf` scores, `ForkSearch` parses syntax and adapts it to upstream callers). `ForkSearch.setEnabled`
is the switch, turned on in `ForkAppearance.start()`; off, every hook falls through to upstream behaviour.
The scorer and syntax were settled in `prototype/fuzzy-search`; clipboard and file retrieval now
follow the owner's revised fuzzy-search decision:

- Words are ANDed in any order; fzf extended syntax: `'exact`, `^prefix`, `suffix$`, `!exclude`. No typo tolerance.
- Every search surface uses the **fuzzy** profile (letters may be skipped); `'word` keeps an exact
  contiguous word. Clipboard positives must each clear the launcher's medium score bar, based on
  that word's folded length. File root matching uses the same per-word `ForkSearch.score` bar.
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
- File search keeps upstream's substring Spotlight query as the fast batch. Both batches apply
  negated words to filenames only, through `!=` clauses; folder names never exclude a result.
  Queries with 3+ positive letters start a separate subsequence-glob task after publishing the fast
  batch, then merge the supplemental results by path and rerank the full union. Each query retains the
  1,000-candidate cap; the final list retains the 200-row cap. fzf scores filename and folder separately
  (folder weight 0.6), then breaks ties by shorter filename and incoming index. Short queries use
  upstream ranking before the display cap, so an exact short filename survives unsorted candidates.
  `'`, `^`, `$` and `!` produce exact, anchored or negated glob clauses.
  Retrieval still queries filenames, so folder-only terms cannot discover extra paths on their own.
- Each file session owns a `ForkFileSearchService`, which awaits only the substring batch and owns
  a separate task for the supplemental glob and merge. New requests and session cancellation cancel
  that task immediately; the session worker can then process the next request without waiting for
  the old glob. A fork revision also prevents a superseded substring batch from starting a glob.
  Both publications stay behind the session's existing revision/request guards. Injected harness
  operations, blank-screen recents and switch-off behaviour stay upstream. A supplemental failure
  retains the fast results. Synchronous Spotlight calls cannot be interrupted mid-execution; their
  detached work may finish after cancellation, but the obsolete merge never publishes or blocks the
  next request. The spike in `docs/fork-search-spike.md` remains historical evidence that glob
  retrieval is slower; it is a supplement to the fast query.
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

## Palette chips

Tab in the collapsed compact launcher toggles a pill with Applications, Files, Shortcuts and
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

## Upstream hooks

| File | Tag | Purpose |
| --- | --- | --- |
| `Scripts/run-tests.sh` | `// FORK: agent-runs` | Register the AgentRuns decoding harness. |
| `Tinycast/App/AppCore.swift` | `// FORK: agent-runs` | Own the monitor, coordinator and presenter; stop work at termination. |
| `Tinycast/Features/CustomCommands/Service/ShellCommandRunner.swift` | `// FORK: agent-runs` | Allow a per-call stdout limit for complete status JSON, preserving the default. |
| `Tinycast/Palette/PaletteEnvironment.swift` | `// FORK: agent-runs` | Inject the AgentRuns coordinator into the hosted stack. |
| `Tinycast/Palette/PaletteWindowController.swift` | `// FORK: agent-runs` | Forward palette visibility and geometry events to the feature. |
| `Scripts/run-tests.sh` | `// FORK: fork-search` | Register the fork search harness with the real file-query models. |
| `Tinycast/Features/Launcher/Model/SearchRelevance.swift` | `// FORK: search` | `FuzzyMatch.match` answers via fzf, tiers kept. |
| `Tinycast/Features/Launcher/Model/LauncherMatch.swift` | `// FORK: search` | Launcher alignment and sensitivity via fzf. |
| `Tinycast/Features/Snippets/UI/SnippetsScreen.swift` | `// FORK: search` | Snippet filter via fzf. |
| `Tinycast/Features/Quicklinks/UI/QuicklinkListScreen.swift` | `// FORK: search` | Quicklink filter via fzf. |
| `Tinycast/Features/Clipboard/Model/ClipboardStore.swift` | `// FORK: search` | FTS/resident union, fuzzy medium-threshold filter and rank; upstream pins. |
| `Tinycast/Features/FileSearch/Model/FileSearchQuery.swift` | `// FORK: search` | Optional supplemental glob, fuzzy root matching and filename/folder ranking. |
| `Tinycast/Features/FileSearch/Service/FileSearchService.swift` | `// FORK: search` | Run either predicate and return batches before the display cap for the merge. |
| `Tinycast/Features/FileSearch/Service/FileSearchSession.swift` | `// FORK: search` | Production two-query runner, fast publication and revision guards. |
| `AGENTS.md` | `// FORK: documentation` | Link the fork maintenance guide. |
| `Tinycast/DesignSystem/Scrolling/OverflowFade.swift` | `// FORK: overflow-double` | Compile fix: explicit `Double` for the fade strengths. |
| `Scripts/run-tests.sh` | `// FORK: fork-harness` | Register the fork-layer harness. |
| `Scripts/run-tests.sh` | `// FORK: harness-sources` | Compile affected harnesses with real fork dependencies, including the file-session runner. |
| `Tinycast/App/AppCore.swift` | `// FORK: appearance-observation` | Refresh AppKit palette geometry after font changes. |
| `Tinycast/App/AppCore.swift` | `// FORK: appearance-owner` | Single AppCore owner. |
| `Tinycast/App/AppCore.swift` | `// FORK: appearance-start` | Publish the current appearance at startup. |
| `Tinycast/App/MenuBarItem.swift` | `// FORK: status-icon` | Prefer the fork menu-bar image. |
| `Tinycast/DesignSystem/BarButton.swift` | `// FORK: named-asset` | Prefer the namespaced fork image, then upstream. |
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
| `Tinycast/Features/Settings/Panes/GeneralSettingsView.swift` | `// FORK: font-picker` | Render the Fork-owned font preference. |
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
| `Tinycast/Palette/RootPaletteView.swift` | `// FORK: terminal-instances` | Route standalone `$` launcher queries to the terminal command screen. |
| `Tinycast/Palette/RootPaletteView.swift` | `// FORK: palette-chips` | Toggle chips with Tab in the collapsed bar; handle empty-query Escape; set pill radius, show the `⌘1–4` hint and hide compact favourites. |
| `Tinycast/Palette/PaletteWindowController.swift` | `// FORK: palette-chips` | Route number-row favourite slots to active chips and consume unused slots; set collapsed pill width. |
| `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | `// FORK: palette-chips` | Scope ordinary launcher results to Applications or Shortcuts while preserving pinned command results. |

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
| `Tinycast/Features/CustomCommands/UI/CommandOutputView.swift` | `typography` | 5 | 3 |
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
