## MODIFIED Requirements

### Requirement: Editor and terminal actions preserve their distinct destinations

Edit SHALL route by the editor kind setting. With Terminal, Edit SHALL pass only file targets to the
configured editor command, defaulting to `fresh` when blank. The first file's parent SHALL be the working
directory; file arguments SHALL be relative, shell-quoted and protected against leading-dash
interpretation. The editor override MAY include shell arguments and SHALL be mirrored as
`fileNavigator.editor`. With Monaco, Edit SHALL open the first file target in the Monaco editor and SHALL
NOT start a terminal instance. The editor kind SHALL be mirrored as `fileNavigator.editorKind`.

#### Scenario: Edit selected files
- **WHEN** Edit executes with the Terminal editor kind
- **THEN** an embedded editor terminal opens when the Ghostty renderer is enabled
- **AND** otherwise Tinycast opens the command through the external Ghostty launcher

#### Scenario: Edit with Monaco
- **WHEN** Edit executes with the Monaco editor kind
- **THEN** the first selected file opens in Monaco in its own panel
- **AND** no terminal instance or external Ghostty window is created

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
