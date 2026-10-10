# Quick AI root session (Codex): specification

**Status:** spec, not built. It's an experiment, Codex only, off by default. Research and timings are in
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
          terminal instance: codex fork <root> "<handoff>"
          (full tools, Codex's own approvals, visible)
                     │
          Quick AI ◀─┘ new chat = next prewarmed root
```

## Invariants

- **Off means upstream.** With the setting off, every code path is today's: ephemeral threads, the
  10-minute idle shutdown, and no log.
- **The root stays as restricted as today's Quick AI thread.** That means a read-only sandbox, the
  `configurationFlags` feature switches (no shell, no hooks, no multi-agent), Tinycast's safety
  instructions, and `approvalPolicy` `never`/`untrusted`. Only two things change: the thread persists
  (`ephemeral: false`), and it exists before the first question.
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

- **Where:** the Quick AI action panel (⌘K) gets "Start Work in Codex", with a shortcut (proposed
  ⌘⇧↩; check it's free first). It's enabled only when the chat has a root thread with at least one
  completed turn and no reply is streaming.
- **What it does:**
  1. Writes the handoff to the log.
  2. Opens a terminal instance (`TerminalInstancesCoordinator.open`) in the working folder (home if
     none is set) that runs:

     ```sh
     codex fork <root-thread-id> '<handoff prompt>'
     ```

     The CLI forks the stored conversation under Sasha's own Codex config: normal tools, sandbox,
     approvals, AGENTS.md. The app-server's restrictions don't carry over, because they were launch
     flags of a different process.
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
    `thread/delete`, when the root is retired and once an hour while the server runs.
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

The request has to say which surface it came from. That's either a field on `AIRequest`, or the
hook checks `chats.quickAI` identity. The spike decides which is less invasive.

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

## Spike first: four checks before building

1. Does `codex fork <id>` accept a thread the app-server created (`ephemeral: false`, same
   `CODEX_HOME`)? And is the rollout on disk as soon as `turn/completed` arrives?
2. Do the root's developer instructions, Tinycast's text-only safety prompt, carry into a CLI fork?
   If they do, the handoff prompt has to override them clearly, or the fork switches to the
   app-server's `thread/fork` with its own `developerInstructions` followed by `codex resume <fork>`.
3. What does `thread/delete` remove on disk?
4. Does an app-server kept alive with Tinycast's MCP tool servers hold those processes open, and what
   does it cost while idle?

## Not in scope

- A Claude root (planned under the hub, where `/clear` is the reset).
- Model-driven escalation or an MCP `escalate` tool.
- Run registry and agent-card tracking of the fork. The terminal instance is the record for now.
- Approvals answered from Tinycast cards.
- Cursor, OpenCode and Grok routes.
