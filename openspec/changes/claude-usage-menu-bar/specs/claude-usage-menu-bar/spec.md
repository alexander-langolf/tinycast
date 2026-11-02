## ADDED Requirements

### Requirement: Usage item is an independent menu bar item

Tinycast SHALL offer a Claude usage item as its own `MenuBarExtra`, inserted only by the Claude
account's **Menu Bar** preference. The preference SHALL offer **Disabled**, **Usage Icon**, **Session
Percent** and **Session and Week**. The usage item SHALL NOT read or change `showInMenuBar` or
`calendarMenuBarDisplay`. Dragging the usage item out of the menu bar SHALL set the preference to
**Disabled**.

#### Scenario: Enable from settings
- **WHEN** the user picks **Session Percent** in Claude Account settings
- **THEN** the usage item appears in the menu bar
- **AND** the Tinycast and calendar items keep their current state

#### Scenario: Drag out
- **WHEN** the user drags the usage item out of the menu bar
- **THEN** the preference reads **Disabled**
- **AND** the other two items are unchanged

### Requirement: Label shows plan utilisation

With a snapshot available, **Session Percent** SHALL show the session utilisation as a whole
percentage, for example `42%`. **Session and Week** SHALL show the session and all-models weekly values,
for example `42% · 18%`. **Usage Icon** SHALL show a gauge symbol only. Without a snapshot, every
display mode SHALL show the gauge symbol. The label SHALL carry an accessibility label that names
Tinycast and the values shown.

#### Scenario: Session and week
- **WHEN** the latest snapshot reports session 42 and all-models weekly 18
- **AND** the display is **Session and Week**
- **THEN** the label reads `42% · 18%`

#### Scenario: No snapshot
- **WHEN** no fetch has succeeded since launch
- **THEN** the label shows the gauge symbol in every display mode

### Requirement: Menu lists every reported window

The usage menu SHALL list each usage window in the latest snapshot. The session window SHALL come
first, then the all-models weekly window, then each model-scoped weekly window. Each row SHALL show the window's
name, its percentage and its local reset time. The menu SHALL end with **Refresh Now** and **Claude
Account Settings…**.

#### Scenario: Model-scoped weekly window
- **WHEN** the snapshot includes a `weekly_scoped` limit for the model named Fable
- **THEN** the menu shows a Fable weekly row after the all-models weekly row

#### Scenario: Unknown window
- **WHEN** the snapshot includes a limit whose `kind` Tinycast does not know
- **THEN** the menu shows that limit under its raw `kind` value

### Requirement: Usage refreshes only while it is watched

Tinycast SHALL fetch usage only while two conditions hold: the usage item is inserted, and the Claude
account is signed in. Tinycast SHALL fetch when both conditions become true, every five minutes while
they stay true, after the system wakes, and when the user chooses **Refresh Now**. A fetch that
completes after the item was removed, after sign-out, or after a newer fetch started SHALL NOT change
the displayed values.

#### Scenario: Item removed mid-fetch
- **WHEN** the user disables the item while a fetch is in flight
- **THEN** no further fetch is scheduled
- **AND** the in-flight result is discarded

#### Scenario: Disabled item
- **WHEN** the preference is **Disabled**
- **THEN** Tinycast makes no usage requests

### Requirement: Signed-out and failure states

Signed out, the usage item SHALL show the gauge symbol, and its menu SHALL offer **Sign In to
Claude…**. After a failed fetch, the label SHALL keep the last snapshot's values. The menu SHALL
then show when the values were last updated and a one-line error message. A 401 response SHALL
trigger one retry with a refreshed token. A 429 response SHALL wait for the next scheduled poll.

#### Scenario: Token expired
- **WHEN** the usage request returns 401
- **THEN** Tinycast refreshes the token once and retries
- **AND** a second 401 shows the error in the menu without signing out a valid refresh token

#### Scenario: Network failure after a success
- **WHEN** a fetch fails after an earlier fetch succeeded
- **THEN** the label still shows the earlier values
- **AND** the menu shows the time of the last successful update

### Requirement: Usage data stays in memory

The usage fetch SHALL use a private ephemeral URL session with no URL cache. The usage snapshot SHALL
NOT be written to disk, `UserDefaults`, `settings.json` or a backup.

#### Scenario: Relaunch
- **WHEN** Tinycast relaunches
- **THEN** the label shows the gauge symbol until the first fetch succeeds
