# Terminal-style text keys

Basic bash/readline editing chords in Tinycast's single-line inputs, so the palette and a terminal
card's command field edit like a shell prompt. Source list:
[bash shortcuts gist](https://gist.github.com/tuxfight3r/60051ac67c5f0445efee), narrowed to what makes
sense in a one-line field that is not a shell.

## Invariants

- **Only single-line field editors.** A chord applies when the key window's first responder is an
  `NSTextView` with `isFieldEditor == true`. Multi-line editors (Notes, the AI composer, Settings
  text areas) and the libghostty grid (not an `NSTextView`) are untouched. The grid already gets
  every chord from the real zsh.
- **AppKit does the editing.** Each chord becomes one or more standard `NSResponder` selectors sent
  through `NSTextView.doCommand(by:)`. Nothing rewrites the field's string by hand, so undo grouping,
  the field delegate, SwiftUI bindings and the kill buffer behave as they do for built-in keys.
- **Physical keys, not typed characters.** Chords are recognised from the key's base character in
  the ASCII-capable layout (`ASCIIKeyboardLayout.character(for:)` with no modifiers). ⌥B is ⌥B on
  Russian or German layouts and is never mistaken for the `∫` it would type.
- **Marked text wins.** While an input method has marked text (`hasMarkedText()`), no chord is
  intercepted.
- **Existing app chords keep priority.** The router runs after each window's own key handlers:
  palette ⌃N/⌃P (list), ⌃F/⌃B (respelled arrows), ⌃X/⌃⇧X (delete row), ⌃G (File Navigator `cd`),
  ⌃C on a running terminal card (interrupt). The table below lists no chord that collides with them.
- **The binding table is pure.** `ReadlineBinding` is Foundation-only and maps a chord to a command
  and a command to selector names, so a harness can check the table without AppKit.

## Chords

Already native in every `NSTextField` (AppKit's `StandardKeyBinding.dict`); this feature does not
touch them. They are listed because the Dev check confirms them:

| Chord | Effect |
|---|---|
| ⌃A / ⌃E | start / end of line |
| ⌃B / ⌃F | back / forward one character (in the palette these arrive as ← / →) |
| ⌃D / ⌃H | delete forward / backward one character |
| ⌃K | cut to end of line (kill buffer) |
| ⌃Y | paste the kill buffer (yank) |
| ⌃T | swap the two characters around the cursor |
| ⌥⌫ | delete the previous word |

Added by this feature:

| Chord | Command | Selectors |
|---|---|---|
| ⌃U | cut to start of line | `deleteToBeginningOfLine:` |
| ⌃W | cut the previous word | `setMark:`, `moveWordBackward:`, `deleteToMark:` |
| ⌥D | cut the next word | `setMark:`, `moveWordForward:`, `deleteToMark:` |
| ⌥B / ⌥F | back / forward one word | `moveWordBackward:` / `moveWordForward:` |
| ⌥C | capitalize the word | `capitalizeWord:` |
| ⌥U / ⌥L | upper / lower case the word | `uppercaseWord:` / `lowercaseWord:` |
| ⌥T | swap the word with the previous one | `transposeWords:` |
| ⌃_ (⌃⇧-) and ⌃/ | undo | `undo:` |

⌃W and ⌥D go through `setMark:` / `deleteToMark:` so the cut text lands in AppKit's kill buffer and
⌃Y pastes it back, as in readline. `deleteWordBackward:` would delete without cutting.

Word boundaries are AppKit's (punctuation splits words), not readline's `unix-word-rubout`
(whitespace only). `~/github/agentkit` loses `agentkit` on ⌃W, not the whole path.

## Surfaces

| Surface | Window | Hook |
|---|---|---|
| Palette search field, every mode (launcher, File Navigator path input, Search Files, …) | `PalettePanel` | `sendEvent(_:)`, after the File Navigator key, before the emacs-arrow respelling |
| Palette inline argument fields | `PalettePanel` | same hook (they are field editors too) |
| Terminal card command input (log renderer) | `TerminalInstancePanel` | `sendEvent(_:)`, after `onKey` |

Out of scope: Settings and other `AppWindowController` windows, Notes, the AI chat window, the
libghostty grid.

## Not in v1

| Chord | Why not |
|---|---|
| ⌃X ⌃X, ⌃X ⌃U | ⌃X is the palette's delete-row chord; a prefix state would change it |
| ⌃] x, ⌥⌃] x | character search needs a pending-key state; rare in a one-line field |
| ⌃L | no screen to clear; a terminal card's output clearing is a separate decision |
| ⌃C (clear line) | Escape already clears the palette query; ⌃C stays interrupt on terminal cards |
| ⌃R / ⌃S / ⌃O / ⌃P / ⌃N history, `!!`, `^a^b`, Tab completion, ⌥. / ⌥* / ⌥? | need a command history or completion model the fields don't have; ⌃N/⌃P already move the list |
| ⌥R (revert line), ⌥⌃E (expand) | no shell semantics behind them |
| ⌃D exit on empty, ⌃Z | process control, meaningless in a field |

## Behaviour rules

- A recognised chord is consumed (`sendEvent` returns without calling `super`) even when the
  selector is a no-op at a boundary, so ⌥B at position 0 never types `∫`.
- An unrecognised ⌥ letter is passed through unchanged and types its character as today.
- With ⌘ held, nothing matches; ⌘ chords stay with the app.
- No setting in v1. If a layout user needs ⌥U/⌥C/⌥L/⌥T/⌥D/⌥B/⌥F for characters, add
  "Option as Meta in text fields" then (open question below).

## Acceptance criteria

Run in Tinycast Dev, palette launcher field with the text `alpha beta gamma`, cursor at the end,
unless stated otherwise:

1. ⌃U empties the line; ⌃Y brings `alpha beta gamma` back.
2. ⌃W leaves `alpha beta `; ⌃Y restores `gamma`.
3. ⌥B moves before `gamma`, ⌥B again before `beta`; ⌥F moves after `beta`.
4. Cursor at the start, ⌥D leaves ` beta gamma`; ⌃Y restores `alpha`.
5. Cursor before `beta`: ⌥C → `Beta`; ⌥U → `BETA`; ⌥L → `beta`.
6. Cursor after `beta`, ⌥T → `beta alpha gamma`.
7. After ⌃W, ⌃_ (⌃⇧-) restores the word; ⌃/ does the same.
8. Native chords still work: ⌃A, ⌃E, ⌃K + ⌃Y, ⌃T, ⌃D, ⌃H, ⌥⌫.
9. App chords unchanged: ⌃N/⌃P move the list; ⌃X deletes a clipboard row; ⌃G in the File Navigator
   with a terminal origin still `cd`s it.
10. File Navigator: input `~/github/agentkit/`, ⌃W leaves `~/github/` and the listing follows.
11. Russian layout active: ⌥B / ⌃W behave as in 2–3.
12. Japanese/Chinese IME with marked text: ⌃W does not delete anything.
13. Terminal card (log renderer, `forkTerminalGhostty = NO` or renderer off): the command field
    obeys 1–7; ⌃C on a running command still interrupts.
14. libghostty grid card: ⌥B / ⌃W go to zsh as before (zsh's own line editing).

## Open questions

- ? Add an "Option as Meta in text fields" toggle, default on, for layouts that type characters
  with ⌥U/⌥C/⌥L/⌥T/⌥D/⌥B/⌥F?
- ? Extend to Settings text fields and the AI chat window field (same router, different windows)?
- ? ⌃L on a terminal card: clear its output log?
