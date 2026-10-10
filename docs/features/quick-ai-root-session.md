# Quick AI root session and Start Work: specification

**Status:** spec, spike done, not built. It's an experiment and off by default. Research and timings
are in the vault note *Quick AI Root Session — Research*, and the wider plan in *Tinycast Agent Hub —
Design & Plan*.

## Goal

Two separate parts:

- **Warm root (Codex):** Quick AI answers from a Codex thread that's already prepared, so a question
  never waits for a cold start. Each new chat gets a fresh one.
- **Start Work:** when a request needs real work, Sasha moves the conversation into a full
  interactive session (Claude Code or Codex) in a visible terminal instance. That session has its
  normal tools, hooks and approvals. Quick AI then starts a new chat.

Start Work moves the conversation **as text**. It isn't an engine fork: the new session's first
prompt is Sasha's original request, word for word, followed by the Quick AI exchange. So a Quick AI
request like `context> multiverse emails +stardust research create new tokens` reaches the work
session's own prompt hook unchanged, and the sigils resolve there just as in a session Sasha opens
himself. Start Work can be used on the very first message, before Quick AI answers, which makes
Quick AI a fast launcher for real work.

```
 Quick AI ──ask──▶ warm root thread (Codex, ephemeral, read-only, text only)
     │ Start Work (explicit, ⌘↵ / ⌃⌘↵)
     ▼
 terminal instance in the working folder:
   claude '<handoff prompt>'   or   codex '<handoff prompt>'
   (interactive, full tools, its own approvals)
     │
 Quick AI ◀─ new chat (next warm root)
```

## Invariants

- **Off means upstream.** With both settings off, every code path is today's: ephemeral threads made
  on demand, the 10-minute idle shutdown, no log, and no Start Work action.
- **The root is exactly as restricted as today's Quick AI thread.** It has the same parameters,
  including `ephemeral: true`, the same `configurationFlags` (no shell, no hooks, no multi-agent),
  the same safety instructions word for word, a read-only sandbox, and `approvalPolicy`
  `never`/`untrusted`. The only change is that it exists before the first question.
- **Work never runs in Quick AI.** Tools, edits and commands happen only in the work session, a
  separate CLI process in a terminal instance Sasha can see.
- **The handoff is explicit.** Nothing moves without Sasha choosing Start Work. There's no
  classifier, and no tool the model can call to escalate itself.
- **Only Quick AI.** The AI Chat window, and chats reopened from history, keep today's path.
- **Interactive sessions only.** Start Work never uses `claude -p` or `codex exec`.

## Behaviour

### Warm root (Codex)

```
            enable / Quick AI shown
 [off] ───────────────────────────▶ [warming] ── thread/start ok ──▶ [ready]
   ▲                                    │ fail                         │ first send
   │ disable                            ▼                              ▼
   │                               [unavailable] ◀── app-server exit ─ [in use]
   │                                    │ retry on next show            │ new chat / Start Work
   └────────────────────────────────────┴──────────────── retire ◀──────┘
                                                            │ log + prewarm next
```

- **Warming:** when Quick AI is shown and there's no ready root, Tinycast starts the app-server if
  it isn't running (today's `CodexAppServerClient.start`), then sends `thread/start` with today's
  parameters unchanged. The model, web search setting and developer instructions are the current
  ones, and `cwd` is the working folder.
- **Ready → in use:** the first send in a new Quick AI chat claims the ready root. It skips
  `thread/start` and starts its turn on that thread. Later turns in the chat reuse the same thread
  (today's `Conversation` reuse).
- **Mismatch:** if the send's model, web search setting or developer instructions differ from what
  the root was started with, the root is retired unused, and the send takes today's path, which costs
  about 30 ms on a running server.
- **Retire:** happens on a new chat, after Start Work, when the setting is turned off, or when the
  server relaunches. The root's id goes in the log, and a new root is prewarmed for the next chat.
  An ephemeral thread leaves nothing on disk, so there's nothing to delete.
- **Keep-alive:** while the setting is on, the app-server has no idle shutdown. It stops when the
  setting is turned off, when Tinycast quits, or under today's relaunch rules (a changed tool-server
  list).
- **Unavailable:** if warming or the app-server fails, Quick AI falls back to today's path for that
  chat and shows nothing extra. The next time Quick AI is shown, Tinycast tries again.
- The warm root needs Quick AI's provider to be Codex. Start Work doesn't: it works with any provider.

### Start Work

- **Where:** in Quick AI's action panel (⌘K):
  - **"Start Work in <default engine>"**, ⌘↵;
  - **"Start Work in <other engine>"**, ⌃⌘↵, shown only when that engine is installed.

  Both are enabled once the chat has at least one user message (or the composer has text) and no
  reply is streaming. Text in the composer counts as the newest request: it goes into the handoff
  and is never sent to Quick AI.
- **What it does:**
  1. Builds the handoff prompt (below).
  2. Opens a terminal instance (`TerminalInstancesCoordinator.open`) in the working folder (home if
     none is set) running the engine's interactive CLI with the prompt as its first message:

     ```sh
     '<claude path>' -- '<handoff prompt>'
     '<codex path>' -- '<handoff prompt>'
     ```

     The path is the executable Tinycast already resolves for that engine
     (`ExecutableLocator.locate` with the kind's extra paths), so the terminal's `PATH` can't pick a
     different install. Each argument is single-quoted for zsh.
  3. Writes `handedOff` to the log, retires the root if there is one, and Quick AI starts a new
     chat.
- **Approvals, folder trust and hook review** happen inside the CLI in the terminal instance, as in
  any session Sasha starts. Tinycast doesn't answer them.

### Handoff prompt

Plain text, in this order:

1. Sasha's **first Quick AI message, verbatim** and first, so prompt hooks see its sigils exactly as
   typed.
2. When the chat has more than that first message, a separator, then the exchange as
   `Sasha:` / `Quick AI:` turns. An attachment becomes a one-line placeholder
   (`[image attached in Quick AI]`, `[document: name.pdf]`).
3. A closing line:
   > This conversation started in Tinycast Quick AI, which could only answer in text. Continue it
   > here as a work session, with your normal tools and approval rules, starting from the latest
   > request.

**Long chats:** if the prompt would be longer than 32 KB, step 2 goes into
`<Application Support>/QuickAIRoot/handoffs/<chat id>.md` instead, and the prompt keeps the first
message verbatim plus "The rest of the Quick AI conversation is in <path>; read it first." That file
is the only place this feature writes message text, and retention removes it.

### Log and retention

- **Fork-owned log:** `<Application Support>/QuickAIRoot/log.jsonl`, one line per event:

  ```json
  {"at":"…","event":"warmed|claimed|retired|handedOff|fellBack","root":"<thread id>","chat":"<chat uuid>","engine":"claude|codex","terminal":"<instance id>","reason":"…"}
  ```

  It holds no prompt or reply text. Quick AI's chat history already stores that, under its own
  retention setting.
- **Retention**, a setting with default 24 h: log lines and handoff files older than it are removed
  once an hour while Tinycast runs. The work sessions belong to their engines, and Tinycast never
  touches them.

### Settings

Under Settings → AI → Quick AI:
- **"Keep a warm root session (Codex)"**: off by default. It's disabled, with a note, when Quick
  AI's provider isn't Codex.
- **"Start Work in"**: Off, Claude Code (default) or Codex. Engines that aren't installed are shown
  disabled.
- **"Forget the Quick AI log after"**: 1 h, 24 h or 7 days.

All three appear in `settings.json`, in backups and in settings search, following the fork's
existing pattern (`AppSettingsKey`, `SettingsFileKey`, `SettingsBackup`).

## Code layout

**Fork-owned**, in `Tinycast/Fork/QuickAIRoot/`:
- `ForkQuickAIRoot`: the root's state machine, which owns the ready or in-use root id and its start
  parameters.
- `ForkQuickAIHandoff`: builds the handoff prompt and command, and opens the terminal instance.
- `ForkQuickAIRootLog`: the JSONL log, handoff files and pruning.
- `ForkQuickAIRootSettings` and its settings rows.

**Upstream hooks**, each with a `// FORK: quick-ai-root` marker and a `docs/fork.md` row:

| File | Hook |
|---|---|
| `CodexTurnRunner.prepareThread` | Claim the ready root instead of `thread/start` when the request is from Quick AI. |
| `ChatGPTSubscriptionManager.scheduleIdleShutdown` | Skip the shutdown while the root is enabled. |
| `QuickAICoordinator.show` / `startNewChat` | Prewarm, and retire on a new chat. |
| `AIScreen.actions(at:)`, `secondary(at:)`, `tertiary(at:)` | The two Start Work actions and their shortcuts. Both methods return `false` in the AI screen today. |
| `AISettingsView` + settings keys | The three settings. |

The hook spots a Quick AI request by identity: `AIChatState` already sends
`conversationID: session.id`, and the fork asks whether `chats.quickAI.holds(id)`. `AIRequest` is
unchanged.

## Acceptance criteria

1. **Warm first send:** with the root on and Quick AI shown, the first send makes no `thread/start`
   call. That shows in a debug log line, and the warm time to first token is lower than with the
   setting off (measured with a real account, 5 runs each).
2. **New chat:** a new chat gets a new root id, and the previous chat's context never shows up in
   the next answer.
3. **Mismatch:** changing the model or web search between chats retires the prewarmed root, and the
   answer still comes back correctly.
4. **Start Work, first message:** typing `context> multiverse emails +stardust research create new
   tokens` and pressing ⌘↵ without sending opens a Claude Code session in the working folder. Its
   prompt hook resolves the sigils (the `Sigils parsed:` block shows up), it works with its normal
   tools after its normal approvals, and Quick AI is empty afterwards.
5. **Start Work, mid-chat:** after two Quick AI exchanges, ⌃⌘↵ opens Codex. The session knows
   what was said, and a long chat goes through the handoff file.
6. **Root stays restricted:** inside Quick AI, asking for a command or a file edit is refused, just
   as today.
7. **Retention:** with a 1 h retention, old log lines and handoff files are gone after the next
   prune.
8. **Off is upstream:** with everything off, the app-server idles out after 10 minutes, nothing is
   written to `QuickAIRoot/`, and the action panel has no Start Work.
9. **Server crash:** killing the app-server mid-chat falls back to today's path, and the next time
   Quick AI is shown it warms again.

## Spike results (2026-10-10, codex-cli 0.161.0)

The spike tested an engine fork (`codex fork`), which this spec no longer uses. What carries over:

- **Why the handoff moves text, not a fork:** the root's text-only developer message is stored
  history, so every fork inherits it. A plain fork refused to work 3 of 3 times, and
  `thread/fork` with new `developerInstructions` didn't replace it. Rewording the root's
  instructions made forks work, but that loosened the root, made handed-off roots impossible to
  delete (`forked history still references it`, since a fork reads the root's file), and still
  needed `-C` because a fork keeps the root's `cwd`. A fresh session with the chat as its prompt
  has none of these problems.
- **Idle cost of a kept-alive root: negligible.** Over 15 minutes, the native `codex` process
  used 0.08 s of CPU after start-up, and its RSS settled from about 115 MB to 97 MB. The npm `node`
  shim, when that's the launched binary, adds 37–48 MB. There were no child processes, since
  Tinycast disables the user's own MCP servers, and one HTTPS connection stayed open. Each Tinycast
  MCP server would add its own idle process.
- **Shortcuts:** in the AI screen, ⌘↵ reaches `secondary(at:)` (⇧⌘↵ too, after `copyCalculation`
  declines) and ⌃⌘↵ reaches `tertiary(at:)`. Both return `false` today. ⌥⌘↵ can't be used,
  because it also lands on `secondary`.
- **First-run dialogs:** a CLI started in a folder shows its own folder trust and "hooks need
  review" dialogs when they apply. Sasha answers them in the visible terminal.

## Not in scope

- A Claude warm root (planned under the hub, where `/clear` is the reset).
- Model-driven escalation or an MCP `escalate` tool.
- A run registry, and agent-card tracking of the work session. The terminal instance is the record
  for now.
- Approvals answered from Tinycast cards.
- Cursor, OpenCode and Grok routes.
