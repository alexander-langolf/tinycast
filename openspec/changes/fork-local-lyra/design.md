## Context

Local Lyra's source, in `~/github/local-lyra/app/Sources/LocalLyra/`:

| File | Role |
| --- | --- |
| `App/Coordinator.swift` | Fix scheduling, the panel, key handling, apply and dismiss |
| `Accessibility/FocusedText.swift` | `AXObserver` on the focused field, text snapshots, caret bounds |
| `Accessibility/TextInserter.swift` | Verified insertion, with a System Events paste fallback |
| `Server/ModelServer.swift` | Reuses or starts `llama-server` on port 8765, adopts a PID, stops its own server |
| `Client/RewriteClient.swift` | Streams from `llama-server` or Vercel AI Gateway |
| `Input/HotKeys.swift`, `Input/KeyboardMonitor.swift` | System hotkeys while a marker shows, double-⌘ |
| `UI/SuggestionUI.swift` | The Fix marker and the panel |
| `App/Log.swift` | `~/Library/Logs/LocalLyra.log` and the `local.lyra` unified log |

The prompts live in `~/github/local-lyra/bench/prompts/` (`fix.txt`, `coach.txt`,
`professional.txt`, `friendly.txt`). `app/README.md` documents the behaviour and the manual checks.

Tinycast provides the following:

- `AIConnection` with an `openAICompatible` kind, and `AIProviderFactory`.
- `ForkClaudeAccount`, which registers its own connection; its pattern applies here.
- `ForkAppSupervisor`, `ForkTrace`, the selection reader and `ForkTextSink`.
- `HotKeyCenter`.

## Goals / Non-Goals

**Goals:**

- Parity with Local Lyra's README behaviour: Fix, the panel, the hotkeys and the server
  lifecycle.
- One app owns the model server, the logs and the health of every part.
- A front end other than Tinycast's UI runs a Lyra mode.

**Non-Goals:**

- New Lyra features, or changes to the prompts.
- The benchmark harness. It stays in the Local Lyra repository.
- Deleting the Local Lyra repository or its app. Sasha retires the app after the parity check.

## Decisions

### 1. Lyra is a fork feature with the usual layers

`Tinycast/Fork/Lyra/` holds `Model/`, `Service/` and `UI/`. Model is pure:
- the trigger rule: at least 3 words, at most 1,000 characters, and a 0.5 s pause or ending
  punctuation;
- output cleaning: removing `<think>` blocks, echoed `<input>` tags and trailing whitespace;
- the mode list and the prompt loading.

Service owns the focus observer, the engine and the server. UI owns the marker and the panel.

### 2. The model is a Tinycast connection

The feature registers an `openAICompatible` connection named "Local Lyra" for
`http://127.0.0.1:8765/v1`, as the Claude account registers its own. Fix always uses it. Panel
rewrites use a setting that names any Tinycast connection. The default is the local one. The
Vercel AI Gateway client is dropped, because the Claude account and the other connections cover
the cloud case.

### 3. The server is a supervised process

`ForkLlamaServer` ports `ModelServer`: it reuses a healthy server on port 8765, adopts a recorded
PID, and starts `/opt/homebrew/bin/llama-server` with the configured model path. It stops only a
server that it started. It joins `ForkSupervision` as a process companion, and it starts only
while Lyra is enabled. `tinycast://health` lists it with its state.

### 4. Focus and insertion use the ports

The focus observer is a Lyra service that reads through the Accessibility adapter. Insertion
goes through `ForkTextSink`. Lyra's checks run before every write: original value, selection,
element and frontmost app. Its System Events paste fallback comes along. Either the checks live in
a Lyra sink adapter, or `TextInjector` already covers them; the worker reports which.

### 5. Hotkeys follow Lyra's Secure Input finding

Tab is registered as a system hotkey only while a marker shows, because an event tap misses
keystrokes under Secure Keyboard Entry. The panel opens through the Lyra rewrite command (default Hyper+R).
The command uses Tinycast's normal hotkey storage, conflict checks, Settings recorder, and settings-file mirror.

### 6. The rewrite is headless too

`ForkLyraService.rewrite(mode:target:apply:)` reads the selection or the whole focused field,
runs the mode's prompt and optionally applies the result. The Automation tool `lyra_rewrite`
calls it under the `selection` scope.

### 7. Observability replaces the log file

The trigger, the request, the first token, the insertion path and the dismissal each produce
`ForkTrace` events. These events record lengths, durations and outcomes, never text.

## Risks / Trade-offs

- **Hotkey clash.** The Lyra rewrite command (default Hyper+R) uses Tinycast's conflict checks.
  Disabled Lyra ignores the command and unregisters temporary card keys, including Tab.
- **Behaviour drift.** Moving to Tinycast's provider changes the streaming code. The parity check
  in tasks group 5 covers it.
