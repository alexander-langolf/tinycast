## ADDED Requirements

### Requirement: Browser selections come from BetterTouchTool

Tinycast SHALL read a browser selection through BetterTouchTool's "Run JavaScript in Browser"
action before it tries a ⌘C borrow. This applies when the Accessibility read returns no text, the
target app is a supported browser, and BetterTouchTool is running.

#### Scenario: Selection in Chrome under Secure Input
- **WHEN** text is selected in a Google Chrome page, Secure Event Input is on, and the user runs Rewrite
- **THEN** Rewrite receives the selected text

#### Scenario: Selection in a text field
- **WHEN** part of a Chrome text field's value is selected
- **THEN** the read returns that part

#### Scenario: BetterTouchTool not running
- **WHEN** BetterTouchTool is not running
- **THEN** Tinycast does not launch it and continues to the ⌘C borrow

### Requirement: The read leaves the clipboard alone

A read through BetterTouchTool SHALL send no keystroke and SHALL not change the clipboard.

#### Scenario: Clipboard after a read
- **WHEN** the clipboard holds "alpha" and Tinycast reads the Chrome selection "beta" through BetterTouchTool
- **THEN** the clipboard holds "alpha" and clipboard history has no "beta" entry
