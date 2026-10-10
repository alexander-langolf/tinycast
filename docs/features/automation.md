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
