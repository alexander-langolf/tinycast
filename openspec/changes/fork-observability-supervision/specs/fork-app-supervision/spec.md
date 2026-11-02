## ADDED Requirements

### Requirement: BetterTouchTool is kept running

Tinycast SHALL launch BetterTouchTool when it is not running at Tinycast launch, after it
terminates, and before a BetterTouchTool call. Tinycast SHALL relaunch it at most 3 times in 10
minutes.

#### Scenario: BetterTouchTool quits
- **WHEN** BetterTouchTool terminates while Tinycast runs
- **THEN** Tinycast relaunches it after 2 s and logs the relaunch

#### Scenario: BetterTouchTool is down at Rewrite
- **WHEN** BetterTouchTool is not running and the user runs Rewrite on a Chrome selection
- **THEN** Tinycast launches BetterTouchTool, waits up to 3 s for it to answer, and reads the selection

#### Scenario: Relaunch loop
- **WHEN** BetterTouchTool terminates a fourth time within 10 minutes
- **THEN** Tinycast does not relaunch it and reports the state `gaveUp`

### Requirement: Health is readable from outside the app

Tinycast SHALL expose `tinycast://health` through the Automation API, and `tinycast health` SHALL
print it.

#### Scenario: Health check
- **WHEN** the user runs `tinycast health`
- **THEN** the CLI prints each supervised app's state, the Secure Event Input state with its owner, and the Accessibility permission
