## ADDED Requirements

### Requirement: Inventory current external Ghostty tabs

The status bar SHALL show one card per current tab in the running external Ghostty application,
including ordinary shells. Cards SHALL use application-launch, window and tab identity, preserve
window/tab order, and contain an icon and a short description. Description priority SHALL be tab
title, focused-terminal directory basename, then Terminal. Full text SHALL remain accessible.

#### Scenario: Multiple windows and splits
- **WHEN** Ghostty has multiple windows, tabs and split terminal surfaces
- **THEN** each tab appears once and its terminal surfaces remain associated with that tab
- **AND** Tinycast embedded terminals and unrelated agent runs are not added as Ghostty tabs

#### Scenario: Tabs change
- **WHEN** a tab opens, closes, moves or changes title
- **THEN** the next successful refresh reconciles by identity without duplicating the card

### Requirement: Identify live agents using terminal association

A tab SHALL display the Codex or Claude provider icon only when current agent activity is associated
with a terminal in that tab. Title substrings, working-directory equality and unrelated running
processes SHALL NOT suffice. The focused terminal's verified agent SHALL take precedence; otherwise
one distinct verified kind across the tab SHALL be used. Conflicting or unavailable identities SHALL
use the Ghostty icon. Codex and Claude identification MUST both be demonstrated before completion.

#### Scenario: Agent is running in a tab
- **WHEN** verified live Codex or Claude activity is associated with that tab's terminal identity
- **THEN** the card shows the corresponding existing AI provider icon

#### Scenario: Agent exits or title is misleading
- **WHEN** the agent exits, the association is no longer valid, or a shell title only mentions an agent
- **THEN** the card uses the Ghostty icon rather than retaining or inventing an agent identity

#### Scenario: Split tab contains different agents
- **WHEN** a tab contains verified Codex and Claude terminals
- **THEN** the focused terminal determines the icon if it has a verified agent
- **AND** a focused ordinary shell with conflicting other agents uses the Ghostty icon

### Requirement: Observe without taking over the desktop

The coordinator SHALL read Ghostty without launching it, focusing it, opening tabs or reading terminal
output. Visible idle status SHALL refresh on an approximately two-second cadence and relevant process
lifecycle changes. Requests SHALL be serialized, bounded and coalesced; stale responses SHALL be
rejected. Recurring requests SHALL stop while the login session is inactive, during sleep, while the
active palette replaces the status bar, and on termination.

#### Scenario: Ghostty restarts during a request
- **WHEN** a response belongs to an earlier application launch or lifecycle generation
- **THEN** it is discarded and cannot restore old cards

#### Scenario: Integration unavailable
- **WHEN** Ghostty is closed, lacks the required interface, denies access, or a request fails
- **THEN** the status bar shows the corresponding neutral empty or unavailable state
- **AND** no stale card remains actionable and polling does not repeatedly prompt for permission

#### Scenario: Enable Automation access
- **WHEN** the user activates the permission-required status action
- **THEN** Tinycast uses its permission flow to request Ghostty access explicitly
- **AND** background polling alone does not initiate that request

### Requirement: Select the existing tab

Activating a card SHALL revalidate the application and tab identity, select that existing tab and
activate its window without opening a new tab or launching an agent. Card activation SHALL NOT start
a palette session. Each card SHALL expose an accessible action with the full tab description.

#### Scenario: Select or close a tab
- **WHEN** a user activates a current card
- **THEN** Ghostty selects its corresponding tab and window
- **AND** if the tab has disappeared, Tinycast refreshes instead of selecting another tab by index
