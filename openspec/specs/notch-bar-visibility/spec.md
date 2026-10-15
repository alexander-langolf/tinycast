# Notch bar visibility

## Purpose

The user-controlled, default-off preference that decides whether the notch bar exists, including
live show and hide, persistence and the `settings.json` mirror.

## Requirements

### Requirement: Notch bar visibility preference
The system SHALL provide a "Show notch bar" preference in Settings that decides whether the notch bar
exists. The preference SHALL default to off.

#### Scenario: Fresh install
- **WHEN** Tinycast starts with no stored value for the preference
- **THEN** the notch bar is not shown
- **AND** the Settings toggle reads off

#### Scenario: Existing install upgrades
- **WHEN** Tinycast starts after an update on an install that has never set the preference
- **THEN** the notch bar is not shown

#### Scenario: Preference is on at launch
- **WHEN** Tinycast starts with the preference stored as on
- **THEN** the notch bar is shown at the top of the primary display

### Requirement: Live show and hide
The system SHALL apply a change to the preference immediately, without relaunching Tinycast.

#### Scenario: Turning the preference on
- **WHEN** the user turns "Show notch bar" on
- **THEN** the notch bar appears on the primary display
- **AND** it behaves as it does today, including expanding and retracting around palette sessions

#### Scenario: Turning the preference off
- **WHEN** the user turns "Show notch bar" off while the bar is visible
- **THEN** the notch bar is removed from the screen

#### Scenario: Toggled repeatedly
- **WHEN** the user turns the preference off and on again several times
- **THEN** exactly one notch bar is shown after the last change

### Requirement: No cost while hidden
While the preference is off, the system SHALL NOT create the notch panel or its menu-bar probe, and
SHALL NOT run Ghostty polling on the notch bar's behalf.

#### Scenario: Hidden at launch
- **WHEN** Tinycast starts with the preference off
- **THEN** no notch panel exists and no Ghostty status polling is running for the bar

#### Scenario: Hidden after being shown
- **WHEN** the user turns the preference off after the bar was visible
- **THEN** the panel and its menu-bar probe are torn down
- **AND** Ghostty polling stops

### Requirement: Palette is unaffected
The palette SHALL show, hide and take focus identically whether or not the notch bar is visible.

#### Scenario: Palette invoked with the bar hidden
- **WHEN** the preference is off and the user invokes the palette
- **THEN** the palette appears with no notch-related delay, animation or error

### Requirement: Persistence and settings file
The preference SHALL persist across launches, be keyed by the app's bundle identifier like other
preferences, and be carried by the opt-in `settings.json` mirror and by settings backups. It SHALL NOT
grant any capability.

#### Scenario: Persists across launches
- **WHEN** the user turns the preference on and relaunches Tinycast
- **THEN** the notch bar is shown after launch

#### Scenario: Imported from settings.json
- **WHEN** `settings.json` sets the preference and the file is applied
- **THEN** the notch bar is shown or hidden to match, live

#### Scenario: Round-trips through a backup
- **WHEN** settings are exported to a backup and imported on another install
- **THEN** the imported install has the same notch bar preference
