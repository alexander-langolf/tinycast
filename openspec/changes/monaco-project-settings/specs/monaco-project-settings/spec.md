## ADDED Requirements

### Requirement: Project-local editor settings

Tinycast SHALL read `editor/monaco.json` under the active `ForkPolicyStore.directory` on each editor open.
The configuration SHALL provide `theme`, `fontFamily`, `fontSize`, `lineHeight`, `minimap`, and `wordWrap`.
The theme path SHALL resolve relative to the configuration file.
The runtime SHALL read no VS Code user settings or extension code.

#### Scenario: Open with the shipped profile
- **WHEN** the editor opens with the shipped configuration and Geist Mono installed
- **THEN** Monaco uses Geist Mono at size 16, line height 1.7, a disabled minimap, enabled wrapping, and the copied Spectrum theme

#### Scenario: Edit settings between opens
- **WHEN** the user edits the configuration and closes and reopens the editor
- **THEN** the editor reads the changed settings without rebuilding the app or page bundle

#### Scenario: Change the server directory
- **WHEN** the active policy store points to another server directory and the editor opens
- **THEN** the editor reads `editor/monaco.json` from that directory

### Requirement: VS Code theme conversion

The page SHALL define a Monaco theme using `vs-dark` for theme type `dark` and `vs` for type `light`.
The page SHALL pass the theme's colour identifiers and values to Monaco.
The page SHALL convert each token scope into a rule with its foreground and font style.
Token foregrounds SHALL omit the leading hash and preserve alpha.
The custom theme and project font SHALL take precedence over app appearance and font-preference changes.

#### Scenario: Convert token styles
- **WHEN** a token entry contains several scopes, an alpha foreground, and a font style
- **THEN** the page emits one rule per scope with the complete hexadecimal foreground and the same font style

#### Scenario: Change app appearance
- **WHEN** the app appearance changes while a project theme is active
- **THEN** Monaco retains the custom theme

### Requirement: Profile failure fallback

A missing or malformed configuration or theme file SHALL discard the project profile.
An unavailable requested font SHALL also discard the project profile.
The editor SHALL use the built-in app theme, Tinycast's monospaced font at size 13, enabled minimap, and disabled wrapping.
Tinycast SHALL record a typed `ForkEvent` failure without file contents or an error dialog.

#### Scenario: Missing configuration
- **WHEN** the configuration file is absent
- **THEN** the editor uses the built-in appearance and records an unreadable policy failure

#### Scenario: Malformed configuration or theme
- **WHEN** a settings or theme file cannot be decoded or contains invalid values
- **THEN** the editor uses the built-in appearance and records a typed policy failure without file contents

#### Scenario: Missing font
- **WHEN** the requested font family is unavailable
- **THEN** the editor uses the built-in appearance and records an invalid-value policy failure
