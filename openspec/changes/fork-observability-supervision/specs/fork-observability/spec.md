## ADDED Requirements

### Requirement: Operations are recorded as correlated events

Tinycast SHALL record each traced operation as events that share one correlation ID. The events
SHALL include a start, each step and an end or error, with durations in milliseconds.

#### Scenario: Rewrite in Chrome
- **WHEN** the user runs Rewrite on a Chrome selection
- **THEN** the log holds one correlation ID across the Accessibility read, the BetterTouchTool read, the model request and the result

#### Scenario: Failed step
- **WHEN** the BetterTouchTool read times out
- **THEN** the log holds an event for that step with outcome `timeout` and its duration

### Requirement: User content stays out of the log

Events SHALL NOT contain selected text, prompts, model output, clipboard contents, tokens or
Authorization headers.

#### Scenario: Selection read
- **WHEN** the selection read returns 42 characters
- **THEN** the event records the length 42 and no part of the text

### Requirement: The CLI reads the log without the app

`tinycast logs` SHALL read the JSONL mirror and filter it by correlation ID, operation, level and
age, while Tinycast is not running.

#### Scenario: Filter by correlation ID
- **WHEN** the user runs `tinycast logs --id <id>`
- **THEN** the CLI prints only that operation's events, oldest first
