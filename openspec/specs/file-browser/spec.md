# File browser

## Purpose

Describe Tinycast's implemented File Navigator at commit `9f065751`, inspected on 2026-10-12.
This feature area captures current browser behavior, not proposed functionality. The UI command is
**Browse Files**; the implementation lives in `Tinycast/Features/FileNavigator/`.

This area owns navigation, listings, picks, previews, actions, terminal integration and recovery.
The [search baseline](../search/spec.md) owns candidate engines, matching, ranking, recursive scan
limits and home-index lifecycle. Global and subtree search are browser modes that use those contracts.

## Requirements

### Requirement: Browser entry points establish an explicit destination

The browser SHALL open from Browse Files, launcher path input, terminal context and Search Files.
Browse Files SHALL start at the most recent folder, or home when none exists. Launcher routing SHALL
map bare `~` and bare `/` to home and preserve longer `~/…` or `/…` input.

#### Scenario: Open a search result in the browser
- **WHEN** Search Files activates a folder or invokes Show in File Navigator
- **THEN** a folder opens itself
- **AND** a file opens its parent with that file requested as the focused row after loading

#### Scenario: Open from a terminal
- **WHEN** the terminal's browse action opens File Navigator
- **THEN** it supplies the terminal's tracked working directory and originating instance

### Requirement: The input represents the path and filter

Path input SHALL resolve its directory portion and use its last segment as a filename filter.
Words without a path prefix SHALL use the browser's independent global FileSearchSession with
configured file scopes. Clearing the entire input SHALL return to the launcher.

#### Scenario: Filter a folder
- **WHEN** the input is `~/github/agentkit/li`
- **THEN** the browser lists `~/github/agentkit/` filtered by `li`
- **AND** subsequent filter edits reuse a completed listing when the folder and listing mode match

#### Scenario: Complete or move upward
- **WHEN** Tab is pressed on a focused row
- **THEN** the input completes that row, entering it if it is a folder
- **WHEN** Shift-Tab is pressed in folder mode above filesystem root
- **THEN** the browser moves to the parent and requests focus on the folder just left

### Requirement: Direct listings preserve filesystem identity and package boundaries

Direct listings SHALL run off-main and publish batches of 500 rows. They SHALL preserve logical
symlink paths, treat packages as file rows, reject package roots for browsing and reject canonical
ancestor cycles. Hidden and ignored entries SHALL be suppressed by default; Command-Shift-period
SHALL reveal them in direct listings. Search visibility remains governed by the search baseline.

#### Scenario: Browse an application bundle's parent
- **WHEN** an application or installer package occurs in a direct listing
- **THEN** it appears as a file-like leaf rather than a browsable directory

#### Scenario: Present rows
- **WHEN** a listing has no filter
- **THEN** folders precede files and names are ordered case-insensitively with path ties
- **AND** global and subtree rows show parent paths to distinguish locations

### Requirement: Picks survive navigation but belong to one browser session

The browser SHALL keep an ordered set of picked absolute logical paths independently of focus.
Space SHALL toggle the focused pick and advance focus in browsing mode; global word-search mode
SHALL allow Space to enter query text. Command-A SHALL add all visible rows without duplicate picks.

#### Scenario: Act on picks from several folders
- **WHEN** the user picks entries and navigates to another folder
- **THEN** the picks remain the action targets instead of the newly focused row
- **AND** Enter opens actions whenever any picks exist

#### Scenario: Visibility changes or files disappear
- **WHEN** a refresh hides a picked entry through filtering or visibility rules
- **THEN** the pick remains
- **WHEN** a listing proves a picked path has vanished
- **THEN** that pick is removed

#### Scenario: End the browser session
- **WHEN** the browser stops on palette hide or departure
- **THEN** picks, listing rows, candidate memory, panels and preview results are cleared

### Requirement: Activation and actions use the current target set

Enter SHALL descend into a focused folder when no picks exist; on a file or with picks it SHALL
open the action panel. Actions SHALL use picks when present, otherwise the focused row. Before
execution, target and folder existence SHALL be checked off-main and the request, destination,
target set and cancellation state SHALL be checked before dispatch.

#### Scenario: Target becomes unavailable
- **WHEN** validation finds a target missing
- **THEN** Tinycast reports that an item is no longer available through its HUD
- **AND** retains the browser instead of executing the action

#### Scenario: Navigate from a search result
- **WHEN** exactly one target is selected in global or subtree search
- **THEN** the action panel offers Show in File Navigator
- **AND** choosing it exits subtree mode, opens the target folder or file's parent, and preserves
  picks and terminal origin while requesting focus on a file target

#### Scenario: Copy context for an agent
- **WHEN** Hand to an agent is selected
- **THEN** Tinycast copies an absolute-path context block and shows a confirmation HUD
- **AND** no agent is started and no message is sent

The current action set is Edit in Fresh, Open with default app, Open Ghostty here, Open in Ghostty
app, Quick Look, Copy path(s), Copy relative path(s), Reveal in Finder, Show in File Navigator,
Search below this folder, Hand to an agent and Bookmark folder. Availability depends on targets
and mode. Folder actions use the current browser folder. Quick Look uses the first target.

### Requirement: Editor and terminal actions preserve their distinct destinations

Edit SHALL pass only file targets to the configured editor command, defaulting to `fresh` when
blank. The first file's parent SHALL be the working directory; file arguments SHALL be relative,
shell-quoted and protected against leading-dash interpretation. The editor override MAY include
shell arguments and SHALL be mirrored as `fileNavigator.editor`.

#### Scenario: Edit selected files
- **WHEN** Edit in Fresh executes
- **THEN** an embedded editor terminal opens when the Ghostty renderer is enabled
- **AND** otherwise Tinycast opens the command through the external Ghostty launcher

#### Scenario: Open a shell here
- **WHEN** Command-T or Open Ghostty here executes
- **THEN** an embedded terminal opens in the current folder
- **WHEN** Command-O or Open in Ghostty app executes
- **THEN** an external Ghostty shell opens in that folder

#### Scenario: Return the directory to the originating terminal
- **WHEN** Control-G is pressed with an existing origin that accepts commands
- **THEN** Tinycast validates the folder, sends a quoted `cd --` command, hides the palette and
  focuses that terminal
- **AND** an absent or unavailable origin produces a HUD message instead

### Requirement: Preview follows focus independently of picks

Preview SHALL default on and follow the focused row after a 90-millisecond debounce. Command-Y
SHALL toggle preview and collapse expansion when hiding it. Command-Shift-Y SHALL toggle expanded
preview, enabling preview if needed. Expanded preview SHALL hide the list while keeping the path
input mounted and row navigation active. Expansion SHALL reset when the browser stops.

#### Scenario: Expand the preview
- **WHEN** preview expands
- **THEN** the body requests 680 scaled points plus palette chrome, capped to the visible screen
- **AND** the surface uses the existing FileSearch preview rendering without the split Information block

#### Scenario: Scroll without leaving the path field
- **WHEN** Option-Up or Option-Down is pressed
- **THEN** the supported preview scrolls by a page without moving input focus or row selection
- **AND** adding Shift requests the preview's beginning or end
- **AND** unavailable, hidden or unsupported preview scrolling consumes the chord without navigation

#### Scenario: Dismiss layers
- **WHEN** Escape reaches the browser with expanded preview
- **THEN** expansion collapses first
- **WHEN** Escape reaches an unexpanded browser with Quick Look open
- **THEN** Quick Look closes
- **AND** subsequent reducer Escape handling clears global words to home or trims the folder filter,
  then clears picks, then closes the browser; open menus retain their own dismissal priority

### Requirement: Bookmarks and recent folders remain channel scoped

Command-B SHALL show bookmarks followed by recent folders not already bookmarked. Bookmark folder
SHALL append the current folder only once. Recents SHALL retain at most ten folders. Both lists
SHALL persist under the bundle identifier's file-navigator defaults prefix.

#### Scenario: Select a saved folder
- **WHEN** a bookmark or recent folder is selected
- **THEN** the browser navigates there and leaves subtree mode
- **AND** an empty panel shows a disabled No bookmarks or recent folders yet row

### Requirement: Missing folders and denied access have distinct recovery

A missing folder SHALL leave the typed input visible with no rows or preview and a No folder
status. The coordinator SHALL retain a recovery destination based on the last successfully listed
folder, falling back to home if that folder is missing. Permission denial SHALL show a grant-access
row that opens macOS Files and Folders privacy settings, without claiming access has been granted.

#### Scenario: Recover from an invalid path
- **WHEN** Shift-Tab or Escape is pressed after a missing-folder result
- **THEN** input returns to the validated recovery folder instead of guessing the nearest typed ancestor

#### Scenario: Display an empty or pending listing
- **WHEN** a listing has no rows
- **THEN** its status takes priority, followed by Loading while pending, No files found for global
  search, or No matching entries for folder browsing

### Requirement: Live refresh and asynchronous work belong to the browser

AppCore SHALL own the lazy FileNavigatorCoordinator, exposed to views through the environment.
The browser SHALL watch only its current listed folder for write, delete and rename events with a
150-millisecond debounce. Batches, rankings and scheduled preview selection SHALL validate request identity
and cancellation before publication. Stopping SHALL cancel owned listing, preview and action work,
stop the watcher and cancel the global search session.

#### Scenario: Folder changes while visible
- **WHEN** the watched folder emits a change
- **THEN** the active browser reloads and attempts to preserve the focused path
- **AND** late work from a previous input or destination cannot replace current rows

## Implementation map

Paths are relative to the repository root; filenames grouped in one cell share their directory.

| Responsibility | Source |
| --- | --- |
| Ownership and teardown | `Tinycast/App/AppCore.swift` |
| Navigation, picks and available actions | `Tinycast/Features/FileNavigator/Model/FileNavigatorState.swift`, `FileNavigatorPath.swift`, `FileNavigatorAction.swift` |
| Coordination, lifecycle and keyboard handling | `Tinycast/Features/FileNavigator/UI/FileNavigatorCoordinator.swift` |
| Palette actions, rows and empty states | `Tinycast/Features/FileNavigator/UI/FileNavigatorScreen.swift`, `FileNavigatorView.swift`, `FileNavigatorList.swift` |
| Preview and keyboard scrolling | `Tinycast/Features/FileNavigator/UI/FileNavigatorPreview.swift`, `FileNavigatorPreviewGeometry.swift`, `FileNavigatorPreviewScrollTarget.swift` |
| Listings, filesystem policy and watching | `Tinycast/Features/FileNavigator/Service/DirectoryLister.swift`, `FolderWatcher.swift` |
| External action validation and editor command | `Tinycast/Features/FileNavigator/Service/FileNavigatorActionsAdapter.swift` |
| Settings | `Tinycast/Features/FileNavigator/Settings/FileNavigatorSettingsView.swift`, `Tinycast/Features/Settings/Model/SettingsFileKey.swift` |

## Evidence and limitations

This is a source-inspected baseline. `Tests/file-navigator-test.swift` exercises model-level path,
pick, action, preview-state and filtering contracts. It does not establish live watcher, permissions,
terminal, preview rendering or coordinator race behavior. No app build, harness execution or rendered
verification was performed for this artifact.

- The browser has one list and preview, with no column browser, rename, move, delete or create-file
  action in its current action enum. Bookmarks can be added and selected; the panel has no remove action.
- Only the current folder is watched, not every descendant of a recursive search.
- Preview scrolling depends on an exposed scroll view or supported PDF navigation. Media, folder
  previews and out-of-process Quick Look providers without an exposed scroll view can do nothing.
- Space picks in browsing mode, so it is not ordinary typed whitespace there; global words accept it.
- A pasted directory without its trailing slash filters the parent rather than immediately entering
  that directory. Paths containing spaces can be pasted or completed from a row.
- Preview visibility and direct-listing reveal survive coordinator reuse, but are not persisted
  across relaunch. Expanded preview resets on stop.
- Watch setup can fail silently. The privacy-settings action has no explicit automatic retry on
  return, and filesystem permission prompts remain controlled by macOS.
- Pre-action validation is guarded, but external Ghostty completion can hide the palette without
  rechecking destination identity. Shared preview metadata loading has no explicit cancellation
  guard before assigning its detached result. This baseline does not claim complete race protection.
- The action labelled Open with default app delegates a single target to FileSearchCoordinator:
  a single folder therefore opens in File Navigator. Multi-target opening uses NSWorkspace.
- Single-file opening hides the palette before launching; validation-failure retention does not
  imply that every external launch failure keeps the browser visible.
- The editor action is still labelled Edit in Fresh even when the editor command is overridden.
- `docs/features/file-navigator.md` contains historical branch/verification notes and says global
  ripgrep search includes dot entries unconditionally. Current global hidden search defaults off;
  direct reveal and recursive visibility remain separate, as recorded in the search baseline.

Related documentation: `docs/features/file-navigator.md` and `docs/features/file-search.md`.
