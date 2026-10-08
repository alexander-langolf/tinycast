# Terminal instances and Tab chips

## Invariants

- **An instance owns a login-interactive zsh on its own pty.** `TerminalProcess` uses `forkpty`
  and `/bin/zsh -il`, giving the shell a controlling terminal and job control. ⌃C reaches the
  foreground job. The upstream [PseudoTerminal](../../Tinycast/Platform/PseudoTerminal.swift)
  continues to serve custom commands; terminal instances do not change it.
- **The fork child uses only async-signal-safe calls.** Arguments, environment, paths and the
  descriptor limit are prepared before the fork. The child clears the signal mask, resets signal
  dispositions, closes descriptors ≥ 3, changes directory and calls `execve`, or `_exit(127)`.
- **Shell marks drive state and output.** The ZDOTDIR shim adds OSC 133 A/C/D and OSC 7 after loading
  the user's startup files. The parser captures output between C and D, accepts BEL and ST
  terminators across reads, retains CSI for log rendering and holds incomplete UTF-8 scalars.
  Unknown OSC and charset designations are dropped; incomplete escape sequences have a 4 KiB bound.
- **`$` must stand alone.** `$ cmd` and a bare `$` select the terminal screen; `$100 in eur`
  remains a calculator query. A bare `$` shows an instruction rather than a runnable row.
- **Each submitted command replaces the displayed run.** `TerminalSession` creates a new
  `CommandRun` and reuses the upstream `TerminalLogView`. When the log exceeds 256 KiB of UTF-8,
  it retains the last 131,072 characters and increments the generation to force a full redraw.
- **Full-screen programs are not rendered.** Entering alternate-screen mode 1049, 1047 or 47
  suppresses further output until a command-finished mark and shows “Full-screen program · ⌘O opens
  kitty”. Ordinary typing is not forwarded to running programs; `PAGER` and `GIT_PAGER` are `cat`.
- **Instances outlive the palette.** Each is a top-level, key-capable, non-activating panel that
  stays visible on deactivation. It starts pinned at `.floating`, below the palette's `.palette`
  level; unpinning changes it to `.normal`. Sessions and panel positions are not persisted.
- **Models have no AppKit or SwiftUI dependency.** They use Foundation and, for geometry,
  CoreGraphics, with environment facts passed as parameters. Harnesses compile the shipped models.
- **`AppCore` owns both coordinators and both presenters as lazy properties.** There are no
  feature singletons, preferences or caches; termination asks every terminal session to hang up.

## Shell and lifecycle

In launcher mode, `RootPaletteView.screen` routes a terminal query to `TerminalCommandScreen`.
Return or a click on its command row calls `TerminalInstancesCoordinator.open`. The coordinator
captures the palette's top-left corner, hides it without restoring external focus, pops to root,
and presents the new instance there. Each new shell starts in the user's home directory.
Spawning runs in a detached task; the initial command waits for the first OSC 133 A prompt mark.

`TerminalShellShim` rewrites four files in the temporary directory's `<bundle id>-zdotdir` folder
on every spawn. Its `.zshenv` sources the user's `$HOME/.zshenv`, then remembers that file's
`ZDOTDIR` choice for `.zprofile`, `.zshrc` and `.zlogin`. After login, `ZDOTDIR` points at the user's
directory again. The shim does not write startup files in the home directory; the user's own
shell configuration still runs normally. It removes inherited `KITTY_` and `TERM_PROGRAM`
variables, sets `TERM=xterm-256color`, and exports `TINYCAST=1` and `TINYCAST_TERMINAL=1`.

The phase is `starting → idle → running → idle …`, ending at `ended` when the shell exits or
cannot spawn. Sending a command sets `running` immediately. OSC 133 C marks execution, D records
the exit status (defaulting to zero if absent or invalid), and A marks a ready prompt. A prompt
while running without D returns to idle with no status, as after interrupting a continuation
prompt. The shim emits D only after a command ran; its `precmd` hook runs first to preserve `$?`.
OSC 7 updates the instance's directory, including percent-decoded spaces. Output-only reads
coalesce for 30 ms; marks flush the pending batch immediately.

Closing sends SIGHUP to the shell's process group and to a distinct foreground group, then
cancels pty reads and closes the descriptor. After two seconds, SIGKILL targets both groups only
if the shell has not yet been reaped. A process dispatch source and `waitpid` reap the shell
independently of pty EOF, including when a background job retains the terminal descriptor.

## Presentation and keys

The “Grow” card uses `GlassEffectView`, the palette scrim and a 1-point rounded border. Starting
and running use the accent border; a non-zero status uses the destructive border and displays
the code; idle and ended otherwise use the normal border. The bar matches the compact palette's
height and full panel width. Output grows beneath a 1-point divider up to `scaled(340)` points,
then scrolls. The log follows its tail while the reader is at the bottom; scrolling up pauses it.

`TerminalLineCounter` estimates rows at the session's fixed pty columns, ignores CSI, handles
carriage-return redraws and stops at the row cap. It counts printable scalars as one column and
ignores control characters, so wide glyphs and tabs are not terminal-accurate.
`TerminalInstanceMetrics` restates `TerminalLogView`'s private 12-point monospaced font and inset;
keep these in step if the upstream view changes.

| Key | In an instance |
| --- | --- |
| ↵ | Submit the next command while idle, in the same shell; a leading `$ ` is accepted |
| ⌃C | Interrupt the running command |
| ⎋ | Toggle output expansion |
| ⌘P | Toggle pinning between floating and normal window order |
| ⌘O | Open a separate kitty shell in the instance's current directory |
| ⌘W | Close the card and hang up its shell |

⌘O tries a new tab through a running kitty socket under `/tmp/kitty.sock*`; if remote control
fails or no socket is found, it opens a new `/Applications/kitty.app` instance with `--directory`.
It does not attach to the existing pty or rerun the command. Opening failures use the message HUD.

Instances stack newest first at the most recently captured palette corner, separated by
`spacing.md`. Growth and closing animate restacking over 0.18 seconds. Attached panels clamp
their bottom to the screen's visible-frame floor, so a tall stack can overlap there. Dragging a
panel removes it from the stack; it grows down from its own top-left corner without that floor
clamp, and the remaining cards close the gap.

## Tab chips

Tab in the collapsed compact launcher toggles chip mode, unless a menu or control list owns the
key. The palette is collapsed only with compact mode on, launcher mode, an empty trimmed query
and no forced expansion. Chips remain active when typing expands the palette. Applications,
Files, Shortcuts and Clipboard appear in that order in a separate non-key child panel; clicking
them leaves search focus in the palette. Clipboard is dimmed and disabled when clipboard history
is disabled, and its shortcut is consumed without opening it.

The collapsed bar narrows to a pill with a half-bar-height corner radius. Pill, gap and four
round glass chips span the original bar width. The field shows `⌘1–4`; compact favourites hide.
When expanded, the chips sit top-aligned on the right, or on the left if the right will not fit,
with placement clamped to the visible frame. Width changes use immediate frame updates. Pill
and chips cannot share a single Liquid Glass morph because they live in separate windows.

| State | ⌘1–⌘4 | ⎋ |
| --- | --- | --- |
| Chips off | Existing favourite-slot behaviour | Existing palette behaviour |
| Chips on, none selected, empty query | Select a chip | Turn chips off |
| Chip selected, nonempty query | Switch chip; selecting the same chip deselects it | Existing palette query-clearing behaviour |
| Chip selected, empty query | Switch chip; selecting the same chip deselects it | Deselect the chip, retaining chip mode |

While chip mode is active, the remaining number-row favourite slots (⌘5–⌘9 and ⌘0) are consumed.
Escape reaches the chip handler only with no menu open, no argument field focused and no control
list owning it; a nonempty query falls through to the palette's existing Escape policy.

Applications and Shortcuts force the launcher open and scope ordinary results to `.application`
or `.appleShortcut`. Empty queries use the launcher's category-name lookup; typed queries filter
its existing ordered results by kind. A pinned custom-command argument result still takes
precedence, and `$` queries still select the terminal screen before launcher scoping.
Files and Clipboard push their existing screens carrying the query. Their normal back step
clears the selection while retaining chip mode. Hiding the palette or entering a screen not
owned by the selected chip resets chip state.

## Verification

The registered [terminal model harness](../../Tests/terminal-instances-test.swift) covers command
marks, byte-by-byte splits, BEL/ST and split ST, retained SGR, alternate screen, split UTF-8,
missing status, runaway OSC, dropped titles and charsets, phase transitions, `$` parsing,
stack placement, card height and row counting.
The [process harness](../../Tests/terminal-process-test.swift) spawns a real `zsh -il` with a
scratch HOME and checks `.zshenv`, `.zprofile` and `.zshrc` loading, restored `ZDOTDIR`, exit
statuses, OSC 7 with spaces, foreground-job interruption, alternate-screen marks and hang-up.
It does not create or assert a user `.zlogin` file.
The [chips harness](../../Tests/palette-chips-test.swift) covers reducer transitions, unavailable
chips, consumed slots, Escape/back/reset behaviour and pill/side placement geometry.

These harnesses do not verify native focus, glass rendering, drag behaviour, kitty integration
or the composed palette hooks. Manual checks should cover those surfaces, hide/reopen, stacked
growth near screen edges, pinning, output collapse, keyboard routing and category selection.

## Fork ownership

[Features/TerminalInstances/](../../Tinycast/Features/TerminalInstances/),
[Windows/TerminalInstances/](../../Tinycast/Windows/TerminalInstances/),
[Features/PaletteChips/](../../Tinycast/Features/PaletteChips/),
[Windows/PaletteChips/](../../Tinycast/Windows/PaletteChips/), this document and the three harnesses
are fork-owned. The integration hooks are listed in [the fork guide](../fork.md#upstream-hooks).
