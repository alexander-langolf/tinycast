## Why

The persistent notch currently repeats the launcher search field while idle. Turn that space into a
useful status bar, starting with an at-a-glance view of the user's open Ghostty tabs and the agents
running in them.

## What Changes

- Replace the resting notch's search icon, placeholder and input presentation with compact cards.
  Each card contains an icon and a short description.
- Show current tabs in the external Ghostty application, including ordinary shell tabs. This is a
  tab inventory, not only a list of agent runs known to Tinycast.
- Use a Codex or Claude icon when that agent is identified in a tab; use a terminal/Ghostty icon
  otherwise. Keep descriptions tied to the tab or its associated work, and avoid guessing agent
  identity from ambiguous text.
- Reuse the existing agent-card visual language and appearance controls in a compact presentation.
  The existing full agent cards use labels and status dots; the compact icon treatment is part of
  this change rather than an assumed existing component.
- Refresh cards as tabs open, close or change their current activity. Account for Ghostty being
  closed, unavailable, or inaccessible without presenting stale cards as current.
- Preserve the top-safe-edge resting location and the normal launcher invoked by its hotkey,
  including immediate input focus and dismissal back to the status bar. Search remains in the
  active launcher; it is removed from the resting notch only.
- Define card interaction, overflow, empty-state presentation and the transition between the status
  bar and active launcher in the design/spec artifacts. The prior whole-field click-to-open behavior
  must be reconciled with cards rather than inherited accidentally.

## Capabilities

### New Capabilities

- `ghostty-tab-status`: Current Ghostty tab inventory, short descriptions, Codex/Claude identification,
  refresh lifecycle, and unavailable/empty states for compact status cards.

### Modified Capabilities

- `ui`: Replace the passive launcher-field appearance with an agent-card-based notch status bar;
  define compact layout, appearance, accessibility and launcher transition behavior.

## Impact

- Fork-owned persistent presentation in `Tinycast/Fork/Palette/`, its AppCore-owned lifecycle and
  palette summon/dismiss integration.
- `AgentRunCard`, `AgentRunsMetrics` and existing agent identity/icon resources are reuse points;
  tab identity must remain distinct from agent-run identity.
- External Ghostty integration needs a verified source of tab identity and current activity.
  `TerminalGhosttyLauncher` currently opens tabs; it does not provide an inventory. Design must
  verify available integration capabilities and permission requirements before choosing a mechanism,
  including how split panes relate to one tab card.
- The completed `persistent-launcher-field` change is the implementation baseline. Its UI delta has
  not yet been archived/synced into the main UI spec, so subsequent specs must reconcile that baseline
  explicitly instead of losing its focus, display and lifecycle guarantees.
- Tests and native acceptance must cover tab lifecycle, agent identification, compact card layout,
  and physical-hotkey focus after invocation. No new external dependency is selected by this proposal.
