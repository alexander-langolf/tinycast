# Terminal-style text keys — implementation plan

> **For agentic workers:** Execute this plan task-by-task per the global CLAUDE.md Orchestration policy (delegate to executor/mech-executor roles, verifier pass before done). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Basic bash/readline chords (⌃U, ⌃W, ⌥B/F/D/C/U/L/T, ⌃_ and ⌃/) in the palette's and terminal cards' single-line fields.

**Architecture:** A pure `ReadlineBinding` table maps a physical chord to a command and the command to
standard `NSResponder` selector names. A small AppKit router, `ReadlineFieldKeys`, runs those
selectors on the key window's field editor through `doCommand(by:)`. Two `sendEvent` hooks call it:
`PalettePanel`, an upstream file with a `// FORK: readline-keys` marker, and `TerminalInstancePanel`,
which is fork-owned.

**Tech Stack:** Swift 6 (strict concurrency), AppKit field editor / Cocoa text system selectors, XcodeGen, `Scripts/run-tests.sh` harnesses.

Spec: [docs/features/readline-keys.md](../../features/readline-keys.md). Rules: `AGENTS.md`, `docs/fork.md`.
Every upstream hook carries `// FORK: readline-keys` and a row in the fork.md Upstream hooks table, and
`Scripts/fork-audit.sh` must pass. Fork-owned code lives in `Tinycast/Fork/TextKeys/`.

**Order (Sasha's rule):** Tasks 1–5 implement with **no test files**. Implementers do not run builds,
tests or lint; Claude runs all verification in Task 6. Task 7, the harness, runs only after Sasha has
checked the behaviour in Dev.

---

## File structure

| File | Responsibility |
|---|---|
| Create `Tinycast/Fork/TextKeys/ReadlineBinding.swift` | Foundation-only chord → command → selector-name table |
| Create `Tinycast/Fork/TextKeys/ReadlineFieldKeys.swift` | `@MainActor` router: event → chord → field-editor selectors |
| Modify `Tinycast/Palette/PalettePanel.swift` (`sendEvent`, after the menu-open freeze block ~line 211–217) | upstream hook |
| Modify `Tinycast/Windows/TerminalInstances/TerminalInstancePanel.swift:58-59` | fork-owned hook |
| Modify `docs/fork.md`, `docs/README.md`, `docs/features/palette.md`, `docs/features/terminal-instances.md` | ledger, index, cross-links |
| Task 7 only: create `Tests/readline-keys-test.swift`, modify `Scripts/run-tests.sh` | harness |

---

### Task 0: Branch

- [ ] **Step 1:** In the existing checkout (no worktrees): `git switch -c al/readline-keys main`. If the
  spec and plan commit already exists on `al/readline-keys`, use `git switch al/readline-keys`.

### Task 1: Binding table (pure)

**Files:** Create `Tinycast/Fork/TextKeys/ReadlineBinding.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// Readline chords for single-line fields. See docs/features/readline-keys.md.
/// Foundation-only: the router turns `selectors` into `NSTextView.doCommand(by:)` calls.
enum ReadlineBinding {
    /// One key press, by the key's base character in the ASCII-capable layout.
    struct Chord: Equatable, Sendable {
        var key: String
        var control = false
        var option = false
        var shift = false
        var command = false
    }

    enum Command: String, CaseIterable, Sendable {
        case killToStart, killWordBackward, killWordForward
        case wordBackward, wordForward
        case capitalizeWord, uppercaseWord, lowercaseWord, transposeWords
        case undo

        /// Standard `NSResponder` action names, run in order. Kills go through the mark so the cut
        /// text lands in AppKit's kill buffer and ⌃Y yanks it back.
        var selectors: [String] {
            switch self {
            case .killToStart: ["deleteToBeginningOfLine:"]
            case .killWordBackward: ["setMark:", "moveWordBackward:", "deleteToMark:"]
            case .killWordForward: ["setMark:", "moveWordForward:", "deleteToMark:"]
            case .wordBackward: ["moveWordBackward:"]
            case .wordForward: ["moveWordForward:"]
            case .capitalizeWord: ["capitalizeWord:"]
            case .uppercaseWord: ["uppercaseWord:"]
            case .lowercaseWord: ["lowercaseWord:"]
            case .transposeWords: ["transposeWords:"]
            case .undo: ["undo:"]
            }
        }
    }

    /// Nil for anything not in the spec's table, including every ⌘ chord and the app's own
    /// ⌃N/⌃P/⌃F/⌃B/⌃X/⌃G/⌃C.
    static func command(for chord: Chord) -> Command? {
        guard !chord.command else { return nil }
        if chord.control, !chord.option {
            switch (chord.key, chord.shift) {
            case ("u", false): return .killToStart
            case ("w", false): return .killWordBackward
            case ("-", true), ("/", false): return .undo
            default: return nil
            }
        }
        if chord.option, !chord.control, !chord.shift {
            return optionCommands[chord.key]
        }
        return nil
    }

    private static let optionCommands: [String: Command] = [
        "b": .wordBackward, "f": .wordForward, "d": .killWordForward,
        "c": .capitalizeWord, "u": .uppercaseWord, "l": .lowercaseWord, "t": .transposeWords,
    ]
}
```

- [ ] **Step 2: Commit**

```bash
git add Tinycast/Fork/TextKeys/ReadlineBinding.swift
git commit -m "Fork: readline chord table for single-line fields"
```

### Task 2: Field-editor router

**Files:** Create `Tinycast/Fork/TextKeys/ReadlineFieldKeys.swift`

- [ ] **Step 1: Write the file**

```swift
import AppKit

/// Runs a readline chord in the key window's single-line field editor.
/// See docs/features/readline-keys.md for the table, surfaces and invariants.
@MainActor
enum ReadlineFieldKeys {
    /// True when the press was a readline chord and the field editor ran it; the caller then
    /// swallows the event, so ⌥B never types `∫` even at a word boundary.
    static func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard event.type == .keyDown,
            let editor = window.firstResponder as? NSTextView,
            editor.isFieldEditor, editor.isEditable, !editor.hasMarkedText(),
            let key = ASCIIKeyboardLayout.character(for: Int(event.keyCode))?.lowercased()
        else { return false }
        let flags = event.modifierFlags
        let chord = ReadlineBinding.Chord(
            key: key, control: flags.contains(.control), option: flags.contains(.option),
            shift: flags.contains(.shift), command: flags.contains(.command))
        guard let command = ReadlineBinding.command(for: chord) else { return false }
        perform(command, in: editor)
        return true
    }

    /// Through `doCommand(by:)`, so the field's delegate, undo and the kill buffer all see it.
    static func perform(_ command: ReadlineBinding.Command, in editor: NSTextView) {
        for name in command.selectors {
            editor.doCommand(by: NSSelectorFromString(name))
        }
    }
}
```

- [ ] **Step 2: Regenerate the project** (new sources): `xcodegen generate`. Never hand-edit the pbxproj.

- [ ] **Step 3: Commit**

```bash
git add Tinycast/Fork/TextKeys/ReadlineFieldKeys.swift Tinycast.xcodeproj/project.pbxproj
git commit -m "Fork: route readline chords to the field editor"
```

### Task 3: Palette hook (upstream file)

**Files:** Modify `Tinycast/Palette/PalettePanel.swift`, in `sendEvent(_:)`, directly after the
"A palette menu owns the keyboard" block. That block returns while `menuOpen` for keys without
⌘/⌃, so it must run first.

- [ ] **Step 1: Insert**

```swift
        // FORK: readline-keys
        if event.type == .keyDown, paletteState?.menuOpen != true,
            ReadlineFieldKeys.handle(event, in: self)
        {
            return
        }
```

Placement check: the File Navigator hook (`onFileNavigatorKey`) and `emacsArrow` run earlier and
keep ⌃G, ⌃N/⌃P and ⌃F/⌃B. The table returns nil for those keys anyway.

- [ ] **Step 2: Ledger row** in `docs/fork.md` → Upstream hooks table:

```markdown
| `Tinycast/Palette/PalettePanel.swift` | `// FORK: readline-keys` | Run readline chords in the search/argument field editor after the navigator, emacs-arrow and menu-freeze rules. |
```

- [ ] **Step 3: Commit**

```bash
git add Tinycast/Palette/PalettePanel.swift docs/fork.md
git commit -m "Fork: readline chords in the palette field"
```

### Task 4: Terminal card hook (fork-owned)

**Files:** Modify `Tinycast/Windows/TerminalInstances/TerminalInstancePanel.swift:58-59`

- [ ] **Step 1: Replace the first line of `sendEvent`**

```swift
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        // The command field only; the libghostty grid is not an NSTextView and keeps zsh's editing.
        if ReadlineFieldKeys.handle(event, in: self) { return }
```

(`onKey` first keeps ⌃C → interrupt and ⌘W.)

- [ ] **Step 2: Commit**

```bash
git add Tinycast/Windows/TerminalInstances/TerminalInstancePanel.swift
git commit -m "Fork: readline chords in a terminal card's command field"
```

### Task 5: Docs

**Files:** `docs/fork.md`, `docs/README.md`, `docs/features/palette.md`, `docs/features/terminal-instances.md`

- [ ] **Step 1: fork.md section.** Add after the terminal-instances paragraph:

```markdown
[Terminal-style text keys](features/readline-keys.md) are fork-owned under `Tinycast/Fork/TextKeys/`:
a pure chord table plus a field-editor router. They have one upstream hook in `PalettePanel.sendEvent`
and one fork-owned call in `TerminalInstancePanel`. Editing goes through standard `NSResponder`
selectors, so no field string is rewritten by hand.
```

- [ ] **Step 2: README index.** Next to the File Navigator entry, using the same marker style:

```markdown
<!-- // FORK: readline-keys --> [Terminal-style text keys](features/readline-keys.md) ·
```

Add the matching `docs/README.md` row to the fork.md hooks table. Copy the shape of the existing
`docs/README.md` / `// FORK: file-navigator` row.

- [ ] **Step 3: Cross-links.** One sentence in `palette.md` under its keyboard section, and one in
  `terminal-instances.md` under Shell and lifecycle: "Readline chords (⌃U, ⌃W, ⌥B/F/D…) in the
  field: see [readline-keys.md](readline-keys.md)."

- [ ] **Step 4: Commit**

```bash
git add docs/
git commit -m "Docs: terminal-style text keys"
```

### Task 6: Verification (Claude)

- [ ] `./Scripts/fork-audit.sh` → "Fork audit passed".
- [ ] `./Scripts/lint.sh` → `✓ lint-clean`, no new warnings in `Tinycast/Fork/TextKeys/`.
- [ ] `grep -n 'import AppKit\|import SwiftUI' Tinycast/Fork/TextKeys/ReadlineBinding.swift` → no output.
- [ ] `xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug -derivedDataPath build/DerivedData build` → `BUILD SUCCEEDED`, no new warnings.
- [ ] `./Scripts/run-tests.sh`: only `form-input-test` and `settings-history-test` fail, as on `main`.
- [ ] Relaunch Dev with a clean environment (strip `CLAUDE*`/`CODEX_*`) and run spec acceptance
  criteria 1–14. Record any selector that misbehaves, especially `undo:` (7), the kill buffer after
  `deleteToMark:` (2 and 4) and the IME case (12). Fix or drop each one, and update the spec table
  to match.
- [ ] Hand to Sasha for his Dev check.

### Task 7: Harness (only after Sasha's check)

**Files:** Create `Tests/readline-keys-test.swift`; modify `Scripts/run-tests.sh` (next to `ascii-layout-test`)

- [ ] **Step 1: Write the harness** (AppKit: it exercises the real Cocoa text system selectors)

```swift
import AppKit

@main
struct ReadlineKeysTest {
    @MainActor static func main() {
        func chord(_ key: String, control: Bool = false, option: Bool = false, shift: Bool = false,
                   command: Bool = false) -> ReadlineBinding.Chord {
            .init(key: key, control: control, option: option, shift: shift, command: command)
        }
        typealias C = ReadlineBinding.Command
        precondition(ReadlineBinding.command(for: chord("u", control: true)) == .killToStart)
        precondition(ReadlineBinding.command(for: chord("w", control: true)) == .killWordBackward)
        precondition(ReadlineBinding.command(for: chord("-", control: true, shift: true)) == .undo)
        precondition(ReadlineBinding.command(for: chord("/", control: true)) == .undo)
        let options: [String: C] = [
            "b": .wordBackward, "f": .wordForward, "d": .killWordForward, "c": .capitalizeWord,
            "u": .uppercaseWord, "l": .lowercaseWord, "t": .transposeWords,
        ]
        for (key, command) in options {
            precondition(ReadlineBinding.command(for: chord(key, option: true)) == command)
            precondition(ReadlineBinding.command(for: chord(key, option: true, command: true)) == nil)
            precondition(ReadlineBinding.command(for: chord(key, option: true, shift: true)) == nil)
        }
        // App chords stay with the app.
        for key in ["n", "p", "f", "b", "x", "g", "c", "a", "e", "k", "y", "t", "d", "h"] {
            precondition(ReadlineBinding.command(for: chord(key, control: true)) == nil, key)
        }

        func field(_ text: String, at location: Int) -> NSTextView {
            let view = NSTextView()
            view.isFieldEditor = true
            view.allowsUndo = true
            view.string = text
            view.setSelectedRange(NSRange(location: location, length: 0))
            return view
        }
        let yank = #selector(NSResponder.yank(_:))

        var view = field("alpha beta gamma", at: 16)
        ReadlineFieldKeys.perform(.killToStart, in: view)
        precondition(view.string.isEmpty)
        view.doCommand(by: yank)
        precondition(view.string == "alpha beta gamma")

        view = field("alpha beta gamma", at: 16)
        ReadlineFieldKeys.perform(.killWordBackward, in: view)
        precondition(view.string == "alpha beta ")
        view.doCommand(by: yank)
        precondition(view.string == "alpha beta gamma")

        view = field("alpha beta gamma", at: 0)
        ReadlineFieldKeys.perform(.killWordForward, in: view)
        precondition(view.string == " beta gamma")

        view = field("alpha beta gamma", at: 16)
        ReadlineFieldKeys.perform(.wordBackward, in: view)
        precondition(view.selectedRange().location == 11)
        ReadlineFieldKeys.perform(.wordBackward, in: view)
        precondition(view.selectedRange().location == 6)
        ReadlineFieldKeys.perform(.wordForward, in: view)
        precondition(view.selectedRange().location == 10)

        view = field("alpha beta gamma", at: 6)
        ReadlineFieldKeys.perform(.uppercaseWord, in: view)
        precondition(view.string == "alpha BETA gamma")

        view = field("~/github/agentkit/", at: 18)
        ReadlineFieldKeys.perform(.killWordBackward, in: view)
        precondition(view.string.hasPrefix("~/github/"))
        print("Readline keys passed")
    }
}
```

Adjust any assertion that disagrees with what Sasha confirmed in Dev; the confirmed Dev behaviour
is the oracle. Undo is checked in Dev only, because a window-less `NSTextView` has no undo manager
in the responder chain.

- [ ] **Step 2: Register** in `Scripts/run-tests.sh`:

```sh
run readline-keys-test     Tinycast/Fork/TextKeys/*.swift \
                           Tinycast/Platform/ASCIIKeyboardLayout.swift
```

- [ ] **Step 3: Run** `./Scripts/run-tests.sh readline-keys-test` → `PASSED`.
- [ ] **Step 4: Commit**

```bash
git add Tests/readline-keys-test.swift Scripts/run-tests.sh
git commit -m "Tests: readline keys harness"
```
