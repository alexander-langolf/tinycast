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
  SHA-256 digest in memory. Create, rotate and revoke are in Settings → General → Automation.
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
- **Bounds:** 16 KiB of headers, 256 KiB of body, no `Transfer-Encoding`, 16 connections, 10 s to
  read a request, 180 s for a handler, 4 listen streams per client.
- **Era:** a body with `_meta["io.modelcontextprotocol/protocolVersion"]` must carry matching
  `MCP-Protocol-Version`, `Mcp-Method` and (for `tools/call`, `resources/read`) `Mcp-Name` headers or
  it is `-32020`; an unsupported version is `-32022` listing what is supported. Anything else is a
  handshake-era request: `initialize` is answered with no session id, later requests need a legacy
  `MCP-Protocol-Version` (absent means 2025-03-26).
- **Errors.** Envelope and header faults are JSON-RPC errors with HTTP 400. Unknown tools and
  resources are `-32602`. A tool that ran and failed, or was declined, is a result with
  `isError: true`. The caller's JSON-RPC id is echoed untouched and recorded in the audit log.
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

| Link | Effect |
| --- | --- |
| `tinycast://palette?query=…` | Opens the launcher with the query typed in; nothing is activated. |
| `tinycast://hud?text=…` | Shows a message pill prefixed `tinycast:// link:`, so it cannot pass for an agent. |

Links share one rate limit (burst of 3, then one every two seconds), return nothing to the caller,
and hold no scopes. Text is stripped of control and bidirectional-override characters and cut to
120 characters (message) or 200 (query).
