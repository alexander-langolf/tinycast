# Quick AI root session (Codex): specification

**Status:** spec, spike done (path C), not built. It's an experiment, Codex only, off by default. Research and timings are in
the vault note *Quick AI Root Session — Research*, and the wider plan in *Tinycast Agent Hub — Design &
Plan*.

## Goal

Quick AI answers from a session that's already running, so a question never waits for a cold start.
Nothing serious runs in Quick AI itself. When a request needs real work, Sasha hands the conversation
off to a full Codex session that has its normal tools and approvals, and Quick AI goes back to a
clean root.

```
 Quick AI ──ask──▶ root thread (warm, read-only, text only)
                     │ answer
                     │ Start Work (explicit)
                     ▼
         terminal instance: codex fork -C <dir> <root> "<handoff>"
          (full tools, Codex's own approvals, visible)
                     │
          Quick AI ◀─┘ new chat = next prewarmed root
```

## Invariants

- **Off means upstream.** With the setting off, every code path is today's: ephemeral threads, the
  10-minute idle shutdown, and no log.
- **The root stays as restricted as today's Quick AI thread.** That means a read-only sandbox, the
  `configurationFlags` feature switches (no shell, no hooks, no multi-agent), Tinycast's safety
  instructions, and `approvalPolicy` `never`/`untrusted`. Three things change: the thread persists
  (`ephemeral: false`), it exists before the first question, and its safety instructions are worded
  as limits of Quick AI that end when the conversation moves into a work session (see *Spike
  results*). The hard limits are the flags and the sandbox, and they don't change.
- **Work never runs in the root.** Tools, edits and commands happen only in the handed-off session,
  which is a separate Codex CLI process started from a terminal instance Sasha can see.
- **The handoff is explicit.** Nothing forks without Sasha choosing Start Work. There's no classifier
  and no tool the model can call to escalate itself.
- **Only Quick AI.** The AI Chat window, and chats reopened from history, keep today's path.
- **Never `claude -p`.** This feature doesn't touch the Claude route.

## Behaviour

### Root lifecycle

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

- **Warming:** when Quick AI is shown and no ready root exists, Tinycast starts the app-server if it
  isn't running (today's `CodexAppServerClient.start`), then sends `thread/start` with today's
  parameters except `ephemeral: false`. The model, web search setting and developer instructions are
  the current ones, and `cwd` is the working folder.
- **Ready → in use:** the first send in a new Quick AI chat claims the ready root. It skips
  `thread/start` and starts its turn on that thread. Later turns in the chat use the same thread
  (today's `Conversation` reuse).
- **Mismatch:** if the send's model, web search setting or developer instructions differ from what
  the root was started with, the root is retired unused. The send then starts a fresh root, about
  30 ms on a running server.
- **Retire:** happens on a new chat, after Start Work, when the setting is turned off, or when the
  server is relaunched. The root's id is written to the log, and a new root is prewarmed for the
  next chat.
- **Keep-alive:** while the setting is on, the app-server has no idle shutdown. It stops when the
  setting is turned off, when Tinycast quits, or on today's relaunch rules (a changed tool-server
  list).
- **Unavailable:** if warming or the app-server fails, Quick AI falls back to today's ephemeral path
  for that chat and shows nothing extra. The next time Quick AI is shown, Tinycast retries.

### Start Work (the handoff)

- **Where:** the Quick AI action panel (⌘K) gets "Start Work in Codex", shortcut ⌘↵ (the AI
  screen's unused secondary action). It's enabled only when the chat has a root thread with at least one
  completed turn and no reply is streaming.
- **What it does:**
  1. Writes the handoff to the log.
  2. Opens a terminal instance (`TerminalInstancesCoordinator.open`) in the working folder (home if
     none is set) that runs:

     ```sh
     codex fork -C '<working folder>' '<root-thread-id>' '<handoff prompt>'
     ```

     The CLI forks the stored conversation under Sasha's own Codex config: normal tools, sandbox,
     approvals, AGENTS.md. The app-server's flags don't carry over, because they belong to a
     different process. The root's instructions do, as part of the history, which is why they're
     worded as Quick AI's limits and the handoff prompt says the move has happened.
  3. Retires the root, and Quick AI starts a new chat.
- **Handoff prompt** (fixed text, quoted for the shell):
  > This conversation moved from Tinycast Quick AI into a work session. Earlier instructions limiting
  > you to text no longer apply: use your normal tools and approval rules. Continue with the last
  > request.
- **Approvals** happen inside the Codex TUI in the terminal instance. Tinycast doesn't answer them.

### Log and retention

- **Fork-owned log:** `<Application Support>/QuickAIRoot/log.jsonl`, one line per event:

  ```json
  {"at":"…","event":"warmed|claimed|retired|handedOff|deleted","root":"<thread id>","chat":"<chat uuid>","terminal":"<instance id>"}
  ```

  It holds no prompt or reply text: Quick AI's chat history already stores that, under its own
  retention setting.
- **Retention** has a setting with default 24 h:
  - **Root threads:** retired roots older than the retention are removed with the app-server's
    `thread/delete`, when the root is retired and once an hour while the server runs. A root that
    was handed off can't be deleted: its fork reads the root's history from the root's own file,
    and Codex refuses (`forked history still references it`). Tinycast logs it as kept and stops
    trying; it stays as long as its fork does.
  - **Log:** lines older than the retention are dropped at the same time.
  - **Handed-off forks:** they're separate threads with their own ids, and Codex's retention applies
    to them. Tinycast never deletes them.
- **Engine copies:** clearing isn't deletion. Codex's own session files for a deleted root are
  whatever `thread/delete` removes, and the spike checks exactly what that covers.

### Settings

- Settings → AI → Quick AI:
  - **"Keep a warm root session (Codex, experimental)"**, off by default;
  - **"Forget root sessions after"**: 1 h, 24 h or 7 days.
- Both appear in `settings.json`, in backups and in settings search, following the fork's existing
  pattern (`AppSettingsKey`, `SettingsFileKey`, `SettingsBackup`).
- If Quick AI's provider isn't Codex, the toggle is shown disabled with a note saying why.

## Code layout

**Fork-owned**, in `Tinycast/Fork/QuickAIRoot/`:
- `ForkQuickAIRoot`: the state machine above, which owns the ready or in-use root id and its start
  parameters.
- `ForkQuickAIRootLog`: the JSONL log and pruning.
- `ForkQuickAIHandoff`: builds the fork command and the handoff, and calls the terminal coordinator.

**Upstream hooks**, each with a `// FORK: quick-ai-root` marker and a `docs/fork.md` row:

| File | Hook |
|---|---|
| `CodexTurnRunner.prepareThread` | Claim the ready root instead of `thread/start` when the request is from Quick AI. |
| `ChatGPTSubscriptionManager.scheduleIdleShutdown` | Skip the shutdown while the root is enabled. |
| `QuickAICoordinator.show` / `startNewChat` | Prewarm, and retire on a new chat. |
| Quick AI action list | The Start Work action and its shortcut. |
| `AISettingsView` + settings keys | The two settings. |

The hook tells a Quick AI request apart by identity: `AIChatState` already sends
`conversationID: session.id`, and the fork asks whether `chats.quickAI.holds(id)`. `AIRequest` is
unchanged.

## Acceptance criteria

1. **Warm first send:** with the setting on and Quick AI shown, the first send makes no `thread/start`
   call. That shows in a debug log line, and the warm time-to-first-token is lower than with the
   setting off (measured with a real account, 5 runs each).
2. **New chat:** starting a new chat gives a new root id, and the previous chat's context never shows
   up in the next answer.
3. **Mismatch:** changing the model or web search between chats retires the prewarmed root and still
   answers correctly.
4. **Start Work:** opens a terminal instance whose Codex session holds the Quick AI conversation, can
   run a shell command after Codex asks for approval, and Quick AI is empty afterwards.
5. **Root stays restricted:** while in Quick AI, asking the root to run a command or edit a file is
   refused, just as today.
6. **Retention:** with a 1 h retention, a retired root is gone after the next prune (a `thread/read`
   fails), and its log lines are dropped.
7. **Off is upstream:** with the setting off, the app-server idles out after 10 minutes and nothing
   is written to `QuickAIRoot/`.
8. **Server crash:** killing the app-server mid-chat falls back to the ephemeral path, and the next
   time Quick AI is shown it warms again.

## Spike results (2026-10-10, codex-cli 0.161.0)

Run against a real app-server with Quick AI's exact flags, the user's own MCP servers disabled as
Tinycast does, and Quick AI's thread parameters except `ephemeral: false`. Scripts were throwaway.

1. **CLI fork of an app-server thread: works.** The rollout is on disk at `turn/completed`
   (`thread/start` returns its `path`). `codex fork <id>` (TUI) and `codex exec fork <id>` both
   accept it while the app-server still runs, and the fork carries the history (it recalled a word
   from the root's turn). A fork doesn't copy the history: its `session_meta` has
   `history_mode: paginated` and a `history_base` pointing at the root's rollout and byte offset.
2. **Instructions carry over, as history.** The root's developer message is a stored history item,
   so every fork inherits it:
   - **Path A** (today's wording plus the handoff prompt): the fork refused to run commands, 3 of 3.
   - **Path B** (`thread/fork` with new `developerInstructions`, then `codex resume`): also refused.
     The new instructions never reached the fork's history.
   - **Path C** (chosen): the root's safety text says the limits belong to Quick AI and end when the
     conversation moves into a Codex work session, and the handoff prompt says that move happened.
     With `codex fork <root> '<handoff>'` the fork ran the pending `ls ~` 3 of 3 (`exec`), and once
     in the TUI. Inside the root the same wording still refuses, including when the user claims the
     move has happened. In any case the root has no shell tool, so the flags hold whatever the
     model says.

   Root wording:
   > You are answering inside Tinycast Quick AI, a text-only surface. While this conversation is in
   > Quick AI, never execute commands, read local files, inspect the environment, or modify files.
   > These limits belong to Quick AI only: if the conversation is later moved into a Codex work
   > session, they end and your normal tools and approval rules apply.
3. **`thread/delete`.** For an unforked root it removes the rollout file, its `threads` row in
   `state_5.sqlite` and its rows in `thread_history_1.sqlite`, and a later `thread/read` fails. For
   a root with forks it refuses: `cannot delete thread …: forked history still references it`. So
   handed-off roots stay as long as their forks do, and retention only deletes unforked roots.
4. **Idle cost: negligible.** A ready root on an idle server for 15 minutes: the native `codex`
   process used 0.08 s of CPU after start-up (0.40 → 0.48 s in total), and its RSS settled from
   about 115 MB to 97 MB. The npm `node` shim in front of it, when that's the launched binary,
   added 37–48 MB and no CPU. There were no child processes, because Tinycast disables the
   user's own MCP servers and Dev has none of its own, and one HTTPS connection stayed open
   (172.64.155.209, Cloudflare). Each Tinycast MCP server would add its own idle process.
5. **Working folder.** A fork keeps the root's `cwd` unless told otherwise: launched in
   `~/github/tinycast`, a fork of a root warmed in `~` ran its turn in `~`, although the TUI's header
   showed the terminal's folder. `codex fork -C <dir>` sets it (`pwd` in the fork printed the
   `-C` folder), so Start Work always passes `-C` with the folder it opens the terminal in.
6. **Handoff terminal.** The TUI shows Codex's usual first-run dialogs for the working folder:
   folder trust in an untrusted folder, and "Hooks need review" when a repo's hooks are new or
   changed. Sasha answers them in the visible terminal, as in any Codex session. `codex exec` also
   needs a trusted folder (or `--skip-git-repo-check`); Start Work uses the TUI, so this doesn't
   apply to it.
7. **Shortcut:** ⌘↵. In the AI screen `secondary(at:)` returns `false` today, and the palette's
   Return handler sends ⌘↵ (and ⇧⌘↵, after `copyCalculation` declines) to it.

## Not in scope

- A Claude root (planned under the hub, where `/clear` is the reset).
- Model-driven escalation or an MCP `escalate` tool.
- Run registry and agent-card tracking of the fork. The terminal instance is the record for now.
- Approvals answered from Tinycast cards.
- Cursor, OpenCode and Grok routes.
