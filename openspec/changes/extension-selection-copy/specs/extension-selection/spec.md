## ADDED Requirements

### Requirement: getSelectedText falls back to a borrowed copy

An extension's `getSelectedText()` SHALL read the target app's selection through Accessibility
first. When that read returns no text and the command is user-initiated, Tinycast SHALL borrow a
⌘C copy from the target app through `TextInjector.copySelection` and SHALL return its text. When
both reads return no text, `getSelectedText()` SHALL fail with the existing no-selection error.

#### Scenario: Selection in Chrome
- **WHEN** text is selected in a Google Chrome page and the user runs an extension command that calls `getSelectedText()`
- **THEN** the call returns the selected text

#### Scenario: Selection readable through Accessibility
- **WHEN** the target app reports the selection through Accessibility
- **THEN** the call returns it and sends no ⌘C

#### Scenario: Nothing selected
- **WHEN** nothing is selected in the target app
- **THEN** the call fails with the no-selection error

### Requirement: The clipboard ends unchanged

A borrowed copy SHALL restore the pasteboard's previous contents and SHALL add no entry to
clipboard history.

#### Scenario: Clipboard after a borrowed copy
- **WHEN** the clipboard holds "alpha" and an extension reads the Chrome selection "beta"
- **THEN** the clipboard holds "alpha" afterwards and clipboard history has no "beta" entry from the read

### Requirement: The palette survives the borrow

When the palette is on screen, the borrow SHALL hide the palette before sending ⌘C and SHALL show
it again in extension-command mode afterwards, whether or not the copy succeeded.

#### Scenario: View command
- **WHEN** a view command calls `getSelectedText()` with Chrome as the target and the palette on screen
- **THEN** the palette shows the command again after the read

### Requirement: Background and menu-bar runs send no keystrokes

A background launch or a menu-bar command SHALL read the selection through Accessibility only.

#### Scenario: Background launch
- **WHEN** a background command calls `getSelectedText()` and Accessibility returns no text
- **THEN** the call fails with the no-selection error and no ⌘C is sent
