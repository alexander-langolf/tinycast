# Inbound automation

Other programs can ask Tinycast to do things: open the palette with a query, show a message, ask
you a question, read agent status, focus a terminal, start a named agent. This is the **server**
side and is unrelated to the MCP **client** in [mcp.md](mcp.md); the two share no code.

## Invariants

- **One door.** Every transport authenticates its own caller, builds an `AutomationCall` and hands
  it to `AutomationRouter.route`. The registry in `AutomationOperationCatalog` is the only list of
  operations: the MCP listing, the policy and the link allowlist all read it.
- **Identity is not authority.** `AutomationCaller` says who is asking; `AutomationScope` says what
  they may ask for: `agents:read`, `context:read`, `clipboard:read`, `ui`, `exec`, `dispatch`.
  A `tinycast://` link has an identity and **no scopes**: it may only open the palette with a
  query (never executed) and show a message labelled as coming from a link, rate limited.
- **Unavailable looks like unknown.** A tool or resource the caller's scopes do not cover is absent
  from listings and answers `-32602` as if it did not exist.
- **Off means off.** The server is disabled until Settings turns it on.
- **Fork-owned.** `Features/Automation/` is owned by `AppCore.automation`; upstream hooks are in
  [fork.md](../fork.md#upstream-hooks).

## Protocol revision

The endpoint serves MCP revision **2026-07-28** (stateless: per-request `_meta`, no `initialize`,
no `Mcp-Session-Id`, `server/discover`, `subscriptions/listen`) and also accepts the earlier
handshake revisions 2025-11-25, 2025-06-18 and 2025-03-26 without minting sessions, because Claude
Code and Codex both carry both eras and fall back on a 4xx. Spec pages read on 2026-10-10:
[transports](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports),
[streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http),
[versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning),
[tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools),
[resources](https://modelcontextprotocol.io/specification/2026-07-28/server/resources).

## Approval, credentials and audit

- **Approvals are per request.** `AutomationApprovalQueue` keys each request by its own id and shows
  one at a time through Tinycast's own dialog (default button: Deny), with the exact command and
  folder. Requests expire after 60 seconds, a revoked client's requests are cancelled, and the
  router rechecks the caller's authority after the wait. At most 8 are pending (3 per client) and a
  client gets 6 prompts a minute. A command over 1,000 characters is refused rather than shown cut.
  The dialog waits while another Tinycast dialog is open instead of being swallowed by it.
- **Per-client tokens live only in the login Keychain.** Service
  `<bundle id>.automation-clients`, account = the client's UUID, so Dev and stable never share a
  token. `~/Library/Application Support/<bundle id>/Automation/clients.json` holds labels, scopes and
  expiry (0600), never a token. Tokens look like `tcn_<client id>.<secret>`; the server keeps only a
  SHA-256 digest in memory, read once off the main thread when the endpoint starts; the endpoint
  listens only after that read. An ad-hoc-signed Dev rebuild changes the code signature, so macOS
  may ask for Keychain access again, and Settings says "Starting…" until it is answered.
  Create, rotate and revoke are in Settings → General → Automation.
  Bearer tokens are a deliberate departure from MCP's OAuth profile: this is a local, per-user
  endpoint with manually provisioned clients.
- **Audit.** `Automation/audit.jsonl` (0600, folder 0700) is append-only, serialized under a lock and
  rotated at 5 MiB keeping three files. Each call writes `received`, then `denied`, `approved`,
  `completed`, `failed` or `cancelled` with the request id, caller, transport and redacted
  arguments. A privileged call is refused when its `received` event cannot be written. The log is not
  tamper-evident against the same user.

## HTTP endpoint

`AutomationHTTPServer` listens on `127.0.0.1` only (`NetworkListener`, no dependency): stable
**43311**, Dev **43312**, Beta **43313**, path `/mcp`, POST only. Settings → General → Automation →
Allow automation starts and stops it; it is off by default and the flag is not in backups.

- **Before any body is read:** `Host` must be `127.0.0.1:<port>` or `localhost:<port>`; any `Origin`
  header at all (including `null`) is a 403, so a browser can never talk to it; wrong path 404; any
  method but POST 405 with `Allow: POST`; no CORS headers and no preflight answer.
- **Then:** `Authorization: Bearer …` on every request (never a cookie or a URL parameter; 401, and
  429 after ten failures in a burst), `Content-Type: application/json`, one JSON-RPC message per POST.
- **Bounds:** 16 KiB of headers, 256 KiB of body, no `Transfer-Encoding`, 16 connections open at
  once (one more is answered 503 with `Retry-After: 1` and closed), 10 s to read the headers and
  another 10 s for the body, 180 s for a handler, 4 listen streams per client. Settings shows a
  listener that has failed or stopped instead of "Listening".
- **Era:** a body with `_meta["io.modelcontextprotocol/protocolVersion"]` must carry matching
  `MCP-Protocol-Version`, `Mcp-Method` and (for `tools/call`, `resources/read`) `Mcp-Name` headers or
  it is `-32020`; an unsupported version is `-32022` listing what is supported. Anything else is a
  handshake-era request: `initialize` is answered with no session id, later requests need a legacy
  `MCP-Protocol-Version` (absent means 2025-03-26).
- **Errors.** Envelope and header faults are JSON-RPC errors with HTTP 400. Unknown tools and
  resources are `-32602`, and the attempt is audited (`received`, then `denied`). Arguments that fail
  the tool's input schema, a tool that ran and failed, or one that was declined, are a result with
  `isError: true` (MCP counts input validation as a tool execution error). A resource read that
  is refused or fails after the resource was found (rate limit, audit log down) is `-32603` with
  HTTP 200. The caller's JSON-RPC id is echoed untouched and recorded in the audit log.
- **Cancellation.** Each POST has its own connection; when the client closes it the handler task is
  cancelled, which withdraws a pending approval. The legacy `notifications/cancelled` is accepted
  and ignored: closing the connection is the signal on this transport.
- **Push.** `subscriptions/listen` (2026-07-28 only) is an SSE stream: acknowledgement first, then
  `notifications/resources/updated` for the subscribed resource URIs the client's scopes allow, a
  keep-alive comment every 15 s, and a graceful completion if the client is revoked. There is no GET
  stream and no `Mcp-Session-Id`.

## Links

`AppCore.handleOpenURL` offers each URL to `AutomationCoordinator.handleLink` before the extension
deep-link handler. A URL is claimed only when automation is on and its host names a link operation
or any other tool (so an attempt such as `tinycast://terminal_run?command=…` is refused and audited
instead of falling through). `tinycast://extensions/…` is untouched.

Every installed channel (stable, Beta, each Dev build) registers `tinycast://`, and macOS hands it
to whichever Launch Services picks, often not the build you are testing. Each channel therefore
also claims its bundle id as a scheme, served by the same hosts: `com.tinycast.app.dev://hud?text=…`
reaches only Dev (`com.tinycast.app.beta://`, `com.tinycast.app://` likewise).
`open -b <bundle id> 'tinycast://…'` works too.

| Link | Effect |
| --- | --- |
| `tinycast://palette?query=…` | Opens the launcher with the query typed in; nothing is activated. |
| `tinycast://hud?text=…` | Shows a message pill prefixed `tinycast:// link:`, so it cannot pass for an agent. |

Links share one rate limit (burst of 3, then one every two seconds), return nothing to the caller,
and hold no scopes. Text is checked against the tool's schema like any other call, so a message over
120 characters or a query over 200 is refused (and audited as denied), not cut; what is shown has
control and bidirectional-override characters stripped.

## The `tinycast` bridge

`TinycastCLI/` builds a small tool, embedded at `Tinycast.app/Contents/Helpers/tinycast` (target
added in `project.fork.yml`; it is not part of the app's own sources). `tinycast mcp --stdio` is a
stdio MCP server that POSTs each line to the running app's endpoint:

- **Credentials** are read from the login Keychain (service `<bundle id>.automation-clients`,
  account = client id) and sent as the bearer. `--client <id>` (or `TINYCAST_CLIENT`) picks the
  client; with exactly one client it is optional. The first read by this binary makes the Keychain
  ask for permission once. Nothing is read from a file or an environment token.
- **Channel** (`--channel dev|stable|beta`, `TINYCAST_CHANNEL`; Debug builds default to dev) picks the
  bundle id, Keychain service and port, so a Dev token never reaches the stable app. There is no
  port override: a token only ever goes to its own channel's fixed port.
- **Bridging.** Modern requests get `MCP-Protocol-Version`, `Mcp-Method` and `Mcp-Name` (Base64
  sentinel when not plain ASCII) mirrored from the body. Handshake-era requests get the version the
  server returned from `initialize`. A JSON reply becomes one stdout line; an SSE reply becomes one
  line per event, so `subscriptions/listen` notifications flow. A JSON-RPC error that arrives with a
  null id gets the request's id.
- **Cancellation.** `notifications/cancelled` cancels that request's HTTP exchange, which closes its
  connection; the app treats that as cancellation. Closing stdin stops reading: requests already
  sent are still answered (a piped client closes stdin right after writing), `subscriptions/listen`
  streams are closed, and the bridge exits once the last answer is written.
- **Logs** go to stderr only; stdout carries nothing but MCP messages. If the app is not listening
  the request fails with a JSON-RPC error saying where to turn automation on.

## The cockpit round trip

| Operation | Scope | What it does |
| --- | --- | --- |
| resource `tinycast://agents` | `agents:read` | Runs from the existing status helper (`attach` is reduced to `attachable`). |
| resource `tinycast://terminals` | `agents:read` | Open terminal instances: id, directory, phase, pinned. No command text. |
| resource `tinycast://questions` | `ui` | The caller's own questions with `state` (`pending`, `answered`, `expired`, `acknowledged`), `answer`, `expiresAt`. |
| tool `question_ask` | `ui` | Puts a card on screen with up to six buttons; returns the question id. |
| tool `question_ack` | `ui` | Marks an answered or expired question handled so it leaves the resource. |
| tool `terminal_focus` | `ui` | Raises an existing terminal instance by id. |
| tool `terminal_run` | `exec` | Opens a terminal instance running a command, **after the user approves it**. |
| tool `agent_dispatch` | `dispatch` | Starts a named profile with a prompt, **after the user approves it**; returns the terminal id. |
| resource `tinycast://agent-profiles` | `dispatch` | Profile names the caller may ask for. |
| resource `tinycast://context` | `context:read` | The frontmost app. |

`clipboard:read` is a defined scope with no operation yet.

- **Questions belong to the client that asked** (its token label heads the card, so the text cannot
  impersonate a run). They live in memory in `AutomationQuestionStore`: a client that reconnects reads
  them again; a quit loses them. At most 10 open per client, 50 in total, lifetime 10 s to 24 h
  (default 15 min). The cards float top-right without taking key focus.
- **Push.** Changes to agents, terminals and a client's questions publish
  `notifications/resources/updated` to subscribed streams; the client re-reads. A subscriber also
  holds the agent poll open while the palette is hidden.
- **Launch grants.** `agent_dispatch` only starts what the user wrote into
  `~/Library/Application Support/<bundle id>/Automation/agent-profiles.json`, re-read on every call:

  ```json
  [{"name": "claude", "title": "Claude Code", "command": "claude", "arguments": ["{prompt}"]}]
  ```

  The client sends a profile name and a prompt (control characters become spaces, at most 1,000
  characters); the shell line is built with every word single-quoted, and that exact line is what the
  approval dialog shows. A dispatched agent is an ordinary terminal instance: it appears in
  `tinycast://agents` only if the status helper reports it, and nothing links the two ids.

## Registering a client

In Settings → General → Automation, turn automation on and create a client; the row shows its id.
The tool is `Tinycast Dev.app/Contents/Helpers/tinycast` (Debug builds live under DerivedData:
`…/Build/Products/Debug/Tinycast Dev.app`).

```sh
TC="$HOME/Library/Developer/Xcode/DerivedData/<Tinycast-…>/Build/Products/Debug/Tinycast Dev.app/Contents/Helpers/tinycast"
claude mcp add tinycast -- "$TC" mcp --stdio --client <client id>
codex mcp add tinycast -- "$TC" mcp --stdio --client <client id>
```

## Not done

- **Script sessions (R7).** No duplex JSONL channel for scripts, no script-launch grants and no
  process-group supervision; custom commands still read EOF on stdin.
- **`clipboard:read`** has a scope and no operation.
- **Cancel-run** and status ingestion that does not depend on the status helper.
- **Questions** do not survive a quit; `notifications/cancelled` on HTTP is ignored in favour of
  connection close.
- **Tests.** None were written; the harnesses compile no automation source yet.
