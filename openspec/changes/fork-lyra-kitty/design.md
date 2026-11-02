## Context

The rewrite command reads Accessibility snapshots for editable fields.
Kitty's Accessibility value represents the prompt glyph, and its element bounds represent the terminal surface.
Kitty remote control provides the focused terminal window's selected text.

## Goals / Non-Goals

**Goals:**

- Read the focused kitty window's selected text through a dedicated adapter.
- Stream the rewrite in the existing card near the pointer.
- Copy completed responses without terminal insertion.
- Cancel and reap an owned kitten process within a bounded read.
- Preserve text-free traces.

**Non-Goals:**

- Terminal insertion, paste, or simulated keystrokes.
- Remote-control configuration discovery or editing.
- Kitty support for the headless rewrite tool.
- Changes to the shared quick-action selection chain.

## Decisions

### 1. The adapter targets the frontmost kitty process

`ForkKittySelectionSource` conforms to `ForkSelectionSource`.
The adapter recognises `net.kovidgoyal.kitty` and resolves `Contents/MacOS/kitten` from the running bundle URL.
The command uses `@ --to unix:/tmp/kitty.sock-<pid> get-text --match state:focused --extent selection`.
The process identifier comes from the frontmost kitty application captured at invocation.
Kitty appends that identifier to the configured `listen_on unix:/tmp/kitty.sock` base.
The explicit socket selects the application instance, and `state:focused` selects that instance's focused terminal window.
The adapter does not fall back to another process, Accessibility, the clipboard, or a shell.
A missing socket or changed socket convention produces the read-failure HUD.

### 2. The read owns its child process

Foundation `Process` launches kitten directly with a one-second deadline.
`runObservingExit()` provides the process-exit signal.
A concurrent dispatch queue drains the output pipe and reaps the child without blocking the main actor.
Output has a 4 MiB cap, and standard error goes to the null device.
Timeout, cancellation, and excess output terminate the owned process.
The selection trace records length, bundle ID, and numeric error code.
The trace excludes selection text, command output, socket contents, and rewrite text.

### 3. Plain-text streaming shares the existing model path

The coordinator routes kitty before requesting an Accessibility element.
The plain-text service overload accepts text, a policy snapshot, and a destination-validity closure.
The overload exposes no apply parameter.
Both overloads use the same model routing, prompts, strict completion, cleaning, and streaming code.
The coordinator retains the captured kitty process and selection across mode changes.
Cancellation, generation, application identity, and process lifetime guard asynchronous results.
Read failures show a short HUD and leave the card hidden.

### 4. Copy-only acceptance owns Return

The controller marks the kitty rewrite as Copy-only.
Return and keypad Enter enter the controller's acceptance method.
A completed Copy-only response goes to the general pasteboard and dismisses the card without calling the apply closure.
The copy icon uses the same completed response and keeps the card visible.
Partial responses, loading, and errors expose no copyable response.
The Lyra service also rejects kitty targets at its insertion boundary.
The headless rewrite entry point rejects kitty before an Accessibility read.

### 5. Pointer placement uses AppKit coordinates

The controller captures `NSEvent.mouseLocation` when the command starts.
The card starts beside and below the pointer, flips above when needed, and clamps within the pointer display's visible frame.
Streaming height changes reuse the captured pointer position.
The kitty path performs no Accessibility coordinate conversion.

### 6. Fix on pause excludes kitty explicitly

`scheduleFix` checks the target bundle before consulting Fix policy timing.
The focus observer excludes kitty before subscribing to text changes or reading an Accessibility snapshot.
This exclusion holds even when a custom policy accepts the short prompt glyph.

## Risks / Trade-offs

- The socket convention depends on the configured `/tmp/kitty.sock` base and enabled remote control.
- Native pointer placement, first-click delivery, and Return interception require a Dev check.
- Localization catalog synchronization and translations require Claude's follow-up outside the worker's listed file scope.

## Follow-up

`ForkSelectionAdapters` excludes the kitty reader because Rewrite and Fix Grammar quick actions paste their output into the target application.
Those quick actions need a terminal-safe delivery decision before accepting remote-control selections.
This change does not establish terminal safety for the shared quick-action path.

## Verification

The worker authors implementation and harness source without tests, builds, typechecking, lint, or app launch.
Claude owns strict OpenSpec validation, harness execution, the Debug build, localization, and native Dev checks.
