## ADDED Requirements

### Requirement: The user signs in with a Claude account

AI Settings SHALL offer Sign In for a Claude account. Sign In SHALL open the Claude authorize page
in the default browser and SHALL complete through a loopback callback. A copy-code field SHALL
accept `code#state` when the callback cannot complete. A state that does not match the request
SHALL fail the sign-in. A successful sign-in SHALL store the tokens in the Keychain.

#### Scenario: Browser sign-in
- **WHEN** the user chooses Sign In and approves access in the browser
- **THEN** the account shows as signed in and the "Claude account" connection appears in the model picker

#### Scenario: Copy-code sign-in
- **WHEN** the user pastes the code shown by Claude into the copy-code field
- **THEN** the sign-in completes as it does through the browser callback

#### Scenario: State mismatch
- **WHEN** the pasted code carries a state that differs from the request's state
- **THEN** the sign-in fails with a message and stores nothing

#### Scenario: Claude Code's credentials
- **WHEN** Tinycast signs in, refreshes or signs out
- **THEN** Claude Code's own Keychain item is neither read nor changed

### Requirement: The connection lists ThinkRail's catalog

Signing in SHALL add one Anthropic API connection titled "Claude account". Its models SHALL be the
17 entries of pi 1.2.0's Anthropic catalog, in catalog order, shown by catalog name. Each model's
effort levels SHALL follow pi's ladder rule: off, minimal, low, medium, high, then xhigh and max
only when the model's map names them, with every level mapped to `null` left out. The default
level SHALL be medium. Signing out SHALL remove the connection, and removing the connection SHALL
sign out. Signing in again SHALL reuse the same connection ID.

#### Scenario: Opus 5.5 ladder
- **WHEN** the user opens the effort menu for Claude Opus 5.5
- **THEN** it offers Low, Medium, High, Extra high and Max

#### Scenario: Sonnet 4.5 ladder
- **WHEN** the user opens the effort menu for Claude Sonnet 4.5
- **THEN** it offers None, Minimal, Low, Medium and High

#### Scenario: Names
- **WHEN** the user opens the model picker on the account's connection
- **THEN** the models show as "Claude Opus 5.5", "Claude Sonnet 4.5 (latest)" and so on, never as IDs

#### Scenario: Saved selection survives sign-in again
- **WHEN** a chat selected Sonnet 5.5 on the account's connection and the user signs out and in again
- **THEN** the chat still selects Sonnet 5.5 on the account's connection

### Requirement: Refused models and levels are hidden

A 404 that names the requested model SHALL hide that model from the connection. A 400 with the
message "Invalid effort level" SHALL hide that level for that model. The turn SHALL fail with the
API's message and a note that the item is now hidden. Signing in again or choosing Refresh on the
connection SHALL clear every refusal.

#### Scenario: Model the account cannot use
- **WHEN** the user sends a message with Claude Opus 4.8 and the API answers 404
- **THEN** the turn fails with the message and Claude Opus 4.8 no longer appears in the picker

#### Scenario: Effort the model rejects
- **WHEN** the user sends a message with Sonnet 5.5 at Max and the API answers "Invalid effort level"
- **THEN** the turn fails with the message and Max no longer appears for Sonnet 5.5

#### Scenario: Refresh
- **WHEN** the user chooses Refresh on the account's connection
- **THEN** all 17 models and their full ladders appear again

### Requirement: Requests carry the token and the Claude Code identity

Every request on the account's connection SHALL send `Authorization: Bearer <access token>`,
`anthropic-version: 2023-06-01`, `user-agent: claude-cli/<version>`, `x-app: cli`, and an
`anthropic-beta` header that contains `claude-code-20250219` and `oauth-2025-04-20`. It SHALL NOT
send `x-api-key`. Its `system` field SHALL be an array whose first block is exactly "You are
Claude Code, Anthropic's official CLI for Claude." Instructions and system messages SHALL follow
in a second block.

#### Scenario: Sonnet reply
- **WHEN** the user sends a message on the account's connection with Sonnet 5.5 selected
- **THEN** the reply streams into the chat

#### Scenario: Other connections
- **WHEN** a request goes to any other Anthropic API connection
- **THEN** its headers and body are identical to the shape before this change

### Requirement: Effort follows pi's three request shapes

A model with `supportsMidConvoEffort` SHALL always send adaptive thinking with summarized display
and `block_binding`, plus `output_config.effort` "high". It SHALL also send system-role
`output_config` messages that carry the chosen effort, and the two mid-conversation betas. A model
with only `forceAdaptiveThinking` SHALL send adaptive thinking and `output_config.effort` for every
level except off. Any other model SHALL send budget thinking with pi's budget for the level, the
interleaved-thinking beta, and `thinking: {type: "disabled"}` for off.

#### Scenario: Opus 5.5 at High
- **WHEN** the user sends a message with Opus 5.5 at High
- **THEN** the request ends its messages with a system-role message whose `output_config.effort` is "high"

#### Scenario: Sonnet 4.5 at Medium
- **WHEN** the user sends a message with Sonnet 4.5 at Medium
- **THEN** the request sends `thinking.type` "enabled" with `budget_tokens` 8192

#### Scenario: Sonnet 4.5 at None
- **WHEN** the user sends a message with Sonnet 4.5 at None
- **THEN** the request sends `thinking.type` "disabled"

### Requirement: Thinking works inside a tool loop

Thinking blocks and their signatures from one round of a turn SHALL return in front of their
`tool_use` blocks in the next round of that turn. Thinking blocks from earlier turns SHALL NOT be
sent.

#### Scenario: Tool call with thinking
- **WHEN** Opus 5.5 thinks, calls an attached MCP tool, and the tool returns a result
- **THEN** the next round succeeds and the reply streams into the chat

### Requirement: Later turns reuse the prompt cache

Requests on the account's connection SHALL mark both system blocks, the last tool and the last
content block of the latest user message with `cache_control: {type: "ephemeral"}`.

#### Scenario: Second turn
- **WHEN** the user sends a second message in the same chat within five minutes
- **THEN** the turn's usage reports cached input tokens

### Requirement: Tool names follow Claude Code's built-in spelling

A request tool whose name matches a Claude Code built-in tool, ignoring case, SHALL be sent with
the built-in spelling. A tool call in the reply SHALL map back to the request tool's own name.
Other names SHALL pass through unchanged.

#### Scenario: Colliding name
- **WHEN** an attached MCP tool is named `read`
- **THEN** the request names it `Read` and the tool loop invokes the tool named `read`

#### Scenario: Ordinary name
- **WHEN** an attached tool is named `tinycast_clipboard_search`
- **THEN** the request and the reply both use `tinycast_clipboard_search`

### Requirement: Tokens refresh without user action

The access token SHALL count as expired five minutes before the server's expiry. A request that
finds it expired SHALL wait for a single shared refresh. A 401 before the first event SHALL cause
one refresh and one retry. A refused refresh or a second 401 SHALL sign the account out and fail
the turn with a message that asks the user to sign in again.

#### Scenario: Concurrent requests near expiry
- **WHEN** a Quick AI turn and a title request start after the token expired
- **THEN** one refresh request is sent and both requests use its token

#### Scenario: Revoked access
- **WHEN** the refresh endpoint refuses the refresh token
- **THEN** the account shows as signed out and the turn fails with the sign-in message

### Requirement: Titles use a Haiku model

Title requests on the account's connection SHALL use the first catalog model whose ID starts with
`claude-haiku` and that is not hidden. They SHALL send no thinking.

#### Scenario: Opus chat title
- **WHEN** a chat on the account's connection with Opus 5.5 selected gets its automatic title
- **THEN** the title request names a Haiku model

### Requirement: A throttled request explains the alternative

A 429 on the account's connection SHALL fail the turn with a message that names the Claude CLI
route as an alternative. No failure message SHALL contain the access token.

#### Scenario: Identity check tightened
- **WHEN** the server answers 429 to a Sonnet request
- **THEN** the chat shows the failure with the Claude CLI route named as the alternative
