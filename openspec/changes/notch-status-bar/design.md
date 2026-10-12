## Context

The completed `persistent-launcher-field` implementation owns a non-key passive panel and animates
between resting, opening, active and closing states. Its resting surface is currently one button
containing a half-scale launcher header. Native search focus is established synchronously; the active
window remains at alpha 1 while its rendering is masked during the animation. These guarantees must
survive replacing the passive content.

`AgentRunCard` and `AgentRunsMetrics` provide the existing glass, border, typography and appearance
tokens. `AgentRun` describes a run, not a terminal tab, and has no Ghostty terminal identity. Its attach
action currently opens kitty; that action is inappropriate for a Ghostty tab card.

Source inspection on 2026-10-12 found Ghostty 1.3.1 installed at `/Applications/Ghostty.app`.
Its `Contents/Resources/Ghostty.sdef` declares window/tab/terminal enumeration, stable IDs, titles,
working directories, selected tabs, focused terminals, and commands to select tabs and activate
windows. It does not declare foreground-process PID, TTY or agent identity. This verifies the local
interface declaration, not successful runtime enumeration or permission availability.

## Goals / Non-Goals

**Goals:**

- Show one compact icon-and-description card per current Ghostty tab, including ordinary shells.
- Reuse the agent cards' appearance and distinguish verified Codex/Claude activity visually.
- Keep a single persistent surface at the safe top edge, with bounded layout and accessible actions.
- Preserve reliable hotkey invocation, immediate typing, normal active launcher behavior and dismissal.

**Non-Goals:**

- Render terminal output, control agent runs, launch replacement terminal sessions or manage tabs.
- Add other terminal applications or arbitrary information providers in this first change.
- Treat Tinycast's embedded libghostty terminals as external Ghostty tabs.
- Redesign the full agent-run cards or migrate their existing attach behavior.

## Decisions

### 1. Own tab state separately from agent runs

Add a fork-owned Ghostty status feature with pure snapshot/identity/layout models, a platform service,
an observable coordinator and compact views. `AppCore` owns and starts the coordinator; views consume
the coordinator through their environment. The persistent presentation coordinator retains ownership
of window geometry, transitions and display selection.

Use `(application instance, window ID, tab ID)` as card identity, with terminal IDs nested inside each
tab. Include the application's launch identity so a restarted process cannot reuse a previous snapshot.
An agent association is optional metadata, never the card's primary key. Inject time into freshness
and reconciliation policy. Do not fabricate `AgentRun` records for shell tabs.

Alternative: display the current agent-run list directly. Rejected because it omits ordinary tabs,
can include runs outside Ghostty and cannot reliably identify the tab to select.

### 2. Enumerate through Ghostty's declared scripting interface

Use the running application's own bundle and dictionary, following the existing Ghostty launcher's
selection policy. Send typed Apple Events to its captured process ID, not a path-targeted script,
so a queued request cannot relaunch an exited application. Do not launch Ghostty merely to poll it. Serialize Ghostty Apple Events with
existing Ghostty operations on their shared queue rather than introducing competing execution queues.
Execute blocking work off-main and publish immutable snapshots on the main actor.

Read all windows, tabs and terminal identities in one bounded request. Preserve window/tab order
instead of moving cards whenever activity changes. Initially refresh every two seconds while the
status bar is visible, plus on Ghostty launch/termination and display-session resume. Only one request
may be in flight; coalesce requests, bound execution time, and reject responses for an obsolete app
instance or lifecycle generation. Suspend recurring work during sleep, lock and active launcher use;
refresh on return to rest. Clear current cards on failed reads rather than leaving actionable stale data.

Represent unavailable, permission-required, empty and loaded states separately. A passive poll must
not repeatedly trigger Automation prompts. Request permission through an explicit user action using
the existing permission conventions, and render a small actionable explanation when access is missing.

Alternative: Accessibility traversal or parsing terminal output. Rejected as the primary inventory
mechanism because the declared scripting interface supplies structural IDs without output scraping.
Runtime enumeration, timeout behavior and permission handling remain acceptance gates.

### 3. Require an exact association for agent icons

Reuse the AI provider icon mapping: OpenAI asset for Codex and Claude asset for Claude. Use the Ghostty
application icon for an ordinary or unidentified tab. Use the tab title as the description, falling
back to a focused terminal's working-directory basename and then “Terminal”. Truncate visually but
retain the full description in the accessibility label and tooltip.

An agent icon requires an association with a terminal identity and current activity, not a substring
match against a tab title, matching working directory, or an unrelated process elsewhere on the machine.
For split tabs, prefer a verified agent on the focused terminal; otherwise use the one distinct verified
agent kind across the tab, falling back to the terminal icon if kinds conflict.

Read-only research verified that the running `/Applications/Ghostty Tip.app` dictionary additionally
exposes terminal `pid` and `tty`. Upstream `ScriptTerminal.swift` defines that `pid` as the foreground
process group ID, not necessarily the leaf executable PID. Use an exact join between terminal TTY and
foreground group, and a live process's controlling TTY and process group. Verify executable identity
and process start/liveness, including Codex binaries under Node wrappers; do not treat a process-group
leader as the only candidate. Recheck app identity after collection and reject vanished/reused process
records. Inspect only the minimal process identity fields, not commands, terminal output or environment.

`GHOSTTY_SURFACE_ID` is a 64-bit core ID and the scripting terminal ID is a distinct Swift UUID; never
join them directly. The installed Ghostty 1.3.1 release lacks PID/TTY in its dictionary: enumerate its
tabs with generic icons and clearly expose that agent detection requires the richer interface. The
current running Tip build supports the required route, so both agent types must be proven against it.
No shell hooks, external configuration changes or new agentkit schema are required.

Evidence: installed release and running Tip scripting dictionaries, read-only live process metadata,
and upstream [ScriptTerminal.swift](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/AppleScript/ScriptTerminal.swift).
Native Tinycast acceptance on 2026-10-12 confirmed two live tab cards with distinct Codex and Claude
artwork against the running Tip build `24da727f6`. The installed release remains a separate bundle.

Alternative: infer from titles or working directories. Rejected because renamed tabs, two sessions in
one directory and stale agent titles would mislabel ordinary shells.

### 4. Compact cards share appearance, not full-card data or actions

Extract or reuse the agent-card surface and token calculations for a compact icon-plus-single-line
description variant. Keep tab data and click actions outside that shared visual layer. Preserve current
full-card rendering and its settings. The compact view uses interface-size-aware metrics, agent-card
colours, border and radius; do not shrink the full two-line run card to half size.

Retain the existing half-scale launcher's resting footprint as the initial width/height budget, clamped
to the safe display area. Lay out compact cards horizontally at their actual resting size. Use a pure
layout calculation to determine visible cards and reserve a trailing `+N` overflow action. That action
opens a Tinycast-owned list containing the remaining tabs; it is not a system popover. Long labels
truncate before they force the bar to grow beyond its budget. Final point sizes need rendered checking
at all three Interface Sizes; an unreadable layout must be corrected before acceptance.

Alternative: expand indefinitely or horizontally scroll an invisible off-screen inventory. Rejected
because the notch must remain bounded and expose that more tabs exist.

### 5. Separate tab selection from launcher invocation

Clicking a card selects its existing Ghostty tab and activates its owning window. Revalidate IDs against
the live application before selection; a closed tab causes refresh, not creation of another tab. Card
activation does not start a palette session. Expose full-label accessibility actions for each card.

Replace the current whole-surface launcher button with independent card controls and a compact Tinycast
launcher control at the edge. This retains mouse access without making card clicks invoke search.
The launcher control is an app affordance, not a search icon or text input. The hotkey remains unchanged.
When Ghostty is closed or has no tabs, show a short neutral status and retain the launcher control.

Card selection follows the implemented spec; native selection is checked separately from rendering.

### 6. Preserve native focus while changing transition content

Keep the existing policy, transition identities, previous-app capture and exactly-once active-session
effects. At invocation, establish native input focus immediately, swap the compact status content for
the launcher header at the top, then move and uniformly scale that header into place. On dismissal,
capture the mounted header before palette teardown resets its content, move and uniformly scale it to
half size at the top, then swap to status content. Only one resting/transition surface is interactive
at a time.

Card refreshes must not resize or replace the mounted native editor during a transition. Hold the
displayed tab snapshot during travel and apply the newest valid snapshot at rest. Keep the active
window at alpha 1 and mask rendering as the accepted implementation does. Never animate native focus
or defer text selection until after typing begins. Preserve Reduce Motion, rapid reversal, Spaces,
display removal and direct feature invocation behavior.

Alternative: keep the original search snapshot at rest or replace the native editor during animation.
Rejected because the former violates the status-bar request and the latter risks the prior focus bug.

## Risks / Trade-offs

- Runtime TTY/group correspondence can become stale → Recheck the exact join and process identity;
  both agent kinds rendered against the running Tip build during native acceptance.
- Scripting support differs between installed Ghostty builds → Resolve the running bundle and verify
  its declared capabilities; report unavailable integration rather than guessing object shapes.
- Recurring script work can block or return late → Serialize, set execution bounds, coalesce refreshes,
  reject stale generations and stop polling when the surface or login session is inactive.
- Compact cards can become too small → Verify Default/Large/Larger, long labels, narrow displays and
  overflow; preserve accessibility labels without relying on tiny text alone.
- New card controls can steal focus or trigger the launcher → Keep the passive host non-key, separate
  actions, and test physical hotkey typing and prior-app restoration after card use.
- Existing cards contain stale kitty-specific help → Reuse only their appearance; supply Ghostty-specific
  labels and selection behavior on the new view without changing existing full-card behavior.

## Migration Plan

1. Resolve and document the agent identity contract and validate Ghostty inventory against the installed
   app using read-only checks. No personal tab names or terminal output belong in fixtures or logs.
2. Reconcile the completed persistent-launcher UI delta with the main UI baseline, preserving its
   accepted behavior before layering this change's spec modifications.
3. Implement pure inventory reconciliation, classification, stale-response and bounded-layout harnesses;
   then add service/coordinator ownership and the compact view.
4. Integrate status-to-launcher presentation without changing the accepted input focus sequence.
5. Run the full repository checks and native acceptance: tab create/close/rename, splits, both agents,
   ordinary shells, permission failure, Ghostty restart, overflow, card selection, physical hotkey typing,
   dismissal, rapid reversal, themes, sizes and displays. Separate automated and user-confirmed evidence.

No persisted tab history or settings migration is required. Rollback restores the passive header and
removes the new coordinator's startup wiring; keep active palette behavior and user preferences intact.

## Acceptance

The running Tip build rendered both verified agent kinds. The user confirmed exact tab selection,
overflow selection, updates after tab closure, and physical hotkey typing/dismissal. All three interface
sizes were inspected and the user's original size restored. The original 0.5 scale remains a footprint
reference, not a requirement to halve the text inside cards. See
[the verification record](../../../docs/notch-status-bar-verification.md) for automated results and
native evidence boundaries, including scenarios not repeated in this pass.
