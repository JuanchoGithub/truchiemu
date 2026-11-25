# Time Machine Scrub Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Time Machine scrubber usable with the D-pad, the left stick, and the mouse.

**Architecture:** The gamepad path gains a held-direction state machine in `EmulatorRunner`. It reads the physical D-pad and stick state on every controller event, steps once on a new hold, and then repeats the step on a main-queue dispatch timer until the direction is released. The mouse path gains an interactive hit rectangle. `GameTimeBarOverlay` publishes the slider rectangle as a SwiftUI preference, and `StandaloneGameWindowController` copies that rectangle into `SafeHostingView.interactiveRect` so that the hosting view forwards mouse events to the slider and passes all other events to the game.

**Tech Stack:** Swift 5, SwiftUI, AppKit, GameController, Dispatch, Xcode

**Spec:** GitHub issue #43 "The rewind scrub is very difficult to move" (`https://github.com/JuanchoGithub/truchiemu/issues/43`). The issue reporter asks for the D-pad left/right and the mouse to work.

## Global Constraints

- The project has no test target. Verify each task with `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build` and a manual check of the described behavior.
- The fix must work with the shipped GameController framework on macOS 26.0 and later. Do not use new framework APIs.
- Do not add new user-visible strings. The change must not need new translation keys.
- Do not change the `CFBundleVersion`. The TCC grants of the user depend on it.
- Wrap every new `LoggerService.debug` or `LoggerService.extreme` call in `#if LOG_DEBUG` or `#if LOG_EXTREME`. Use `LoggerService.info` for messages that must exist in Release builds.
- Keep the changes inside the files listed in each task. Do not refactor adjacent code.
- The scrubber must keep working with the keyboard. The keyboard path in `FocusableMTKView` must not change.

## Review Focus

- A held D-pad or stick must stop stepping when the user releases the direction. A stuck repeat timer must not keep moving the playhead.
- The repeat must stop when the user leaves Time Machine scrub mode.
- The left stick must scrub on systems whose core mapping has no `.lStickLeft` or `.lStickRight` binding.
- A click outside the slider must still reach the game view. The overlay covers the whole window, so a wrong hit rectangle blocks the whole game.
- The mouse must not change the emulation speed. The slider must not leave the game in a paused state after the drag ends.

---

### Task 1: Held-direction scrubbing for the D-pad and the sticks

**Files:**
- Modify: `TruchiEmu/Core/Engine/Runners/Runners/BaseRunner.swift`

**Interfaces:**
- Consumes: `EmulatorRunner.stepTimeMachine(direction: Int)` (existing, `@MainActor`)
- Consumes: `EmulatorRunner.timeMachineScrubDirection(for:mapping:extendedGamepad:) -> Int` (existing)
- Produces: `EmulatorRunner.timeMachineHeldScrubDirection(extendedGamepad:) -> Int`
- Produces: `EmulatorRunner.updateScrubRepeat(direction: Int)` (`@MainActor`)
- Produces: `EmulatorRunner.stopScrubRepeat()` (`@MainActor`)

- [x] **Step 1: Add the repeat state and the timer to `EmulatorRunner`**

Add the state next to the other Time Machine properties (after `isRewindingStorage`):

```swift
/// Direction that the user holds for the auto-repeat. -1 moves toward the
/// past, +1 moves toward the present, and 0 means that no direction is
/// held.
@MainActor private var scrubRepeatDirection: Int = 0

/// Timer that repeats the scrub step while a direction is held.
@MainActor private var scrubRepeatTimer: DispatchSourceTimer?

/// Delay before the first repeat. The first press always steps once at once.
private static let scrubRepeatInitialDelay: TimeInterval = 0.35

/// Interval between the repeated steps while a direction is held.
private static let scrubRepeatInterval: TimeInterval = 0.08
```

- [x] **Step 2: Add the repeat methods**

Add these methods next to `stepTimeMachine(direction:)`:

```swift
/// Start, continue, or stop the auto-repeat of the scrub step.
/// `direction` is -1 for the past and +1 for the present.
/// A new direction steps once at once and then repeats.
@MainActor
func updateScrubRepeat(direction: Int) {
    guard direction != 0 else {
        stopScrubRepeat()
        return
    }
    guard direction != scrubRepeatDirection else { return }
    scrubRepeatDirection = direction
    stopScrubRepeatTimer()
    LoggerService.info(category: "TimeMachine", "Stepping gamepad → dir=\(direction)")
    stepTimeMachine(direction: direction)
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + Self.scrubRepeatInitialDelay,
                   repeating: Self.scrubRepeatInterval)
    timer.setEventHandler { [weak self] in
        Task { @MainActor in self?.scrubRepeatTick() }
    }
    scrubRepeatTimer = timer
    timer.resume()
}

/// Repeat the scrub step.
@MainActor
private func scrubRepeatTick() {
    guard isRewinding, scrubRepeatDirection != 0 else {
        stopScrubRepeat()
        return
    }
    stepTimeMachine(direction: scrubRepeatDirection)
}

/// Stop the repeat. The playhead must not move after this call.
@MainActor
func stopScrubRepeat() {
    stopScrubRepeatTimer()
    scrubRepeatDirection = 0
}

/// Cancel the repeat timer without clearing the held direction.
@MainActor
private func stopScrubRepeatTimer() {
    scrubRepeatTimer?.cancel()
    scrubRepeatTimer = nil
}
```

- [x] **Step 3: Stop the repeat when the user leaves or enters scrub mode**

In `enterTimeMachineMode()` add `stopScrubRepeat()` before `applyPauseState(...)`.
In `exitTimeMachineMode()` add `stopScrubRepeat()` as the first statement of the method body, before the `guard isRewinding else { return }` line.
In `stop()` add `stopScrubRepeat()` so that the timer is cancelled when the game closes.

- [x] **Step 4: Read the held direction from the physical gamepad state**

Add these methods next to `timeMachineScrubDirection(for:mapping:extendedGamepad:)`:

```swift
/// Current horizontal scrub direction from the physical gamepad state.
/// GameController reports only changes. A held direction therefore
/// produces no new event, so the state must be read directly from the
/// D-pad and from the sticks.
func timeMachineHeldScrubDirection(extendedGamepad: GCExtendedGamepad) -> Int {
    let dpad = extendedGamepad.dpad
    if dpad.left.isPressed { return -1 }
    if dpad.right.isPressed { return 1 }
    let leftDirection = Self.stickDirection(extendedGamepad.leftThumbstick)
    if leftDirection != 0 { return leftDirection }
    return Self.stickDirection(extendedGamepad.rightThumbstick)
}

/// Direction of a stick. The axis value gives the direction. The left and
/// right buttons are the fallback for a stick that reports only its
/// extreme positions.
private static func stickDirection(_ stick: GCControllerDirectionPad) -> Int {
    let axisDirection = scrubDirection(forAxisValue: stick.xAxis.value)
    if axisDirection != 0 { return axisDirection }
    if stick.left.isPressed { return -1 }
    if stick.right.isPressed { return 1 }
    return 0
}

/// Direction for an analog axis value. Values inside the dead zone are
/// neutral.
private static func scrubDirection(forAxisValue value: Float) -> Int {
    let deadZone: Float = 0.5
    if value <= -deadZone { return -1 }
    if value >= deadZone { return 1 }
    return 0
}
```

- [x] **Step 5: Make the D-pad and the sticks work without a core mapping**

Replace the body of `timeMachineScrubDirection(for:mapping:extendedGamepad:)` with:

```swift
func timeMachineScrubDirection(for element: GCControllerElement, mapping: ControllerGamepadMapping, extendedGamepad: GCExtendedGamepad?) -> Int {
    if let pad = extendedGamepad {
        // A stick can arrive as a direction pad, as its axis, or as one of
        // its direction buttons. The axis value gives the direction.
        for stick in [pad.leftThumbstick, pad.rightThumbstick] {
            if element === stick || element === stick.xAxis
                || element === stick.left || element === stick.right {
                return Self.stickDirection(stick)
            }
        }
        // The D-pad can arrive as a direction pad or as one of its
        // direction buttons.
        let dpad = pad.dpad
        if element === dpad {
            if dpad.left.isPressed { return -1 }
            if dpad.right.isPressed { return 1 }
            return 0
        }
        if element === dpad.left { return dpad.left.isPressed ? -1 : 0 }
        if element === dpad.right { return dpad.right.isPressed ? 1 : 0 }
    }
    // Any other direction pad gives the direction through its buttons.
    if let directionPad = element as? GCControllerDirectionPad {
        if directionPad.left.isPressed { return -1 }
        if directionPad.right.isPressed { return 1 }
        return 0
    }
    // The core mapping decides which physical control moves the playhead.
    // Only the horizontal directions can scrub.
    for (btn, btnMapping) in mapping.buttons {
        guard btn == .left || btn == .right || btn == .lStickLeft || btn == .lStickRight ||
              btn == .rStickLeft || btn == .rStickRight else { continue }
        if !elementMatches(element, mapping: btnMapping, extendedGamepad: extendedGamepad) { continue }
        switch btn {
        case .left, .lStickLeft, .rStickLeft: return -1
        case .right, .lStickRight, .rStickRight: return 1
        default: return 0
        }
    }
    return 0
}
```

- [x] **Step 6: Use the new state machine in `processGamepadElement`**

Replace the `if self.isRewindingStorage { ... }` block with:

```swift
if self.isRewindingStorage {
    let elementDirection = self.timeMachineScrubDirection(for: element, mapping: mapping, extendedGamepad: extendedGamepad)
    let physicalDirection = self.timeMachineHeldScrubDirection(extendedGamepad: extendedGamepad)
    let direction = elementDirection != 0 ? elementDirection : physicalDirection
    #if LOG_DEBUG
    LoggerService.debug(category: "TimeMachine", "Gamepad element: elementDir=\(elementDirection) physicalDir=\(physicalDirection) dir=\(direction)")
    #endif
    if direction != 0 {
        let capturedDirection = direction
        Task { @MainActor in self.updateScrubRepeat(direction: capturedDirection) }
        // The core must not receive the scrub input.
        return
    }
    // No direction is held any more. Stop the repeat.
    Task { @MainActor in self.stopScrubRepeat() }
}
```

- [x] **Step 7: Build and check the result**

Run: `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build`
Expected: the build succeeds with no new warnings.

Manual check: enter Time Machine scrub mode. Hold the D-pad left. The playhead must move to the past at once and must keep moving. Release the D-pad. The playhead must stop. Hold the left stick left on a system whose core mapping has no horizontal stick binding. The playhead must move. Leave scrub mode while a direction is held. The playhead must stop.

### Task 2: Mouse drag on the scrub slider

**Files:**
- Modify: `TruchiEmu/Features/Player/Views/Player/ShaderPlayerComponents/GameTimeBarOverlay.swift`
- Modify: `TruchiEmu/Features/Player/Views/Player/ShaderPlayerComponents/StandaloneGameWindowController.swift`
- Modify: `TruchiEmu/Features/Player/Views/Player/ShaderPlayerComponents/StandaloneGameWindowController+Toolbar.swift`

**Interfaces:**
- Consumes: `SafeHostingView.usesInteractiveRect` and `SafeHostingView.interactiveRect` (existing)
- Produces: `SafeHostingView.passesThroughWhenInteractiveRectEmpty: Bool`
- Produces: `GameTimeBarOverlay.onHitRectChanged: ((CGRect) -> Void)?`
- Produces: `StandaloneGameWindowController.updateTimeBarHitRect(_ rect: CGRect)`

- [x] **Step 1: Let the hosting view pass events through when the rectangle is empty**

In `SafeHostingView` in `StandaloneGameWindowController.swift` add the property:

```swift
/// Pass all events through when `interactiveRect` is empty. The Time Machine
/// overlay covers the whole window, so it must not block the game when the
/// scrub bar is not visible.
var passesThroughWhenInteractiveRectEmpty = false
```

Change the empty rectangle case in `hitTest(_:)` from `guard !interactiveRect.isEmpty else { return result }` to:

```swift
guard !interactiveRect.isEmpty else {
    return passesThroughWhenInteractiveRectEmpty ? nil : result
}
```

- [x] **Step 2: Publish the slider rectangle from the overlay**

In `GameTimeBarOverlay.swift` add the preference key at the end of the file:

```swift
/// Reports the interactive area of the scrub bar to the window controller.
private struct TimeBarHitRectPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
    }
}
```

Add the callback property to `GameTimeBarOverlay`:

```swift
/// Called when the interactive area of the scrub bar changes. The window
/// controller uses the rectangle to route mouse events to the slider.
var onHitRectChanged: ((CGRect) -> Void)? = nil
```

Add `.coordinateSpace(name: "timeBarRoot")` to the root `VStack` of the body and add these modifiers to the root `VStack`:

```swift
.onPreferenceChange(TimeBarHitRectPreferenceKey.self) { rect in
    onHitRectChanged?(rect)
}
.onChange(of: isOverlayVisible) { _, visible in
    // The slider is gone when the bubble is hidden. Clear the
    // rectangle so that the overlay does not block the game.
    if !visible {
        onHitRectChanged?(.zero)
    }
}
```

Add the publisher to the `Slider` in the body. The background must come before the offset, so that the offset moves the publisher too:

```swift
.frame(height: 20)
.background(
    GeometryReader { proxy in
        Color.clear.preference(
            key: TimeBarHitRectPreferenceKey.self,
            // The rectangle must include the
            // offset below. The background is
            // applied before the offset so that
            // the offset moves the publisher too.
            value: proxy.frame(in: .named("timeBarRoot"))
                .insetBy(dx: 0, dy: -8)
        )
    }
)
.offset(y: 22)
```

- [x] **Step 3: Copy the rectangle into the hosting view**

In `StandaloneGameWindowController.swift` change the creation of the time bar view to:

```swift
let timeBarView = SafeHostingView(rootView: AnyView(GameTimeBarOverlay(runner: runner) { [weak self] rect in
    self?.updateTimeBarHitRect(rect)
}))
timeBarView.translatesAutoresizingMaskIntoConstraints = false
timeBarView.wantsLayer = true
// Allow the slider to receive clicks while empty regions pass through to
// the game view below.
timeBarView.isPassThroughOverlay = false
timeBarView.passesThroughEmptyAreas = true
timeBarView.usesInteractiveRect = true
timeBarView.passesThroughWhenInteractiveRectEmpty = true
timeBarView.layer?.backgroundColor = NSColor.clear.cgColor
```

Add the method to `StandaloneGameWindowController+Toolbar.swift`:

```swift
/// Copy the interactive area of the Time Machine scrub bar into the
/// hosting view so that the slider receives mouse events.
@MainActor
func updateTimeBarHitRect(_ rect: CGRect) {
    timeBarOverlayView?.interactiveRect = rect
}
```

- [x] **Step 4: Seek while the user drags**

In `GameTimeBarOverlay.swift` change the `set` closure of the `Slider` binding so that the game follows the thumb:

```swift
set: { newValue in
    sliderValue = newValue
    // Follow the thumb while the user drags so the game shows the
    // snapshot under the pointer.
    seekToSliderPosition()
}
```

Thin the live seek so that a fast drag does not queue many state restores. Add the state property and change the seek method:

```swift
/// Time of the last live seek. A live seek restores a full emulator
/// state, so a fast mouse drag must not queue many restores.
@State private var lastLiveSeekTime: Date = .distantPast
```

```swift
/// Minimum time between two live seeks during a mouse drag.
private static let liveSeekInterval: TimeInterval = 0.05

private func seekToSliderPosition(force: Bool = false) {
    guard hasBuffer, newestFrame > oldestFrame else { return }
    if !force {
        let now = Date()
        guard now.timeIntervalSince(lastLiveSeekTime) >= Self.liveSeekInterval else { return }
        lastLiveSeekTime = now
    }
    let target = oldestFrame + UInt64(sliderValue * Double(newestFrame - oldestFrame))
    Task { @MainActor in
        _ = runner.rewindToFrame(target)
    }
}
```

The `onEditingChanged` closure resets the timer at the start of a drag and forces the final seek at the end of the drag:

```swift
onEditingChanged: { editing in
    isDragging = editing
    if editing {
        // The first seek of a drag must not
        // be thinned out.
        lastLiveSeekTime = .distantPast
    }
    // Apply the new slider position immediately
    // so live-feedback works while dragging.
    seekToSliderPosition(force: !editing)
}
```

- [x] **Step 5: Build and check the result**

Run: `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build`
Expected: the build succeeds with no new warnings.

Manual check: enter Time Machine scrub mode. Drag the slider thumb. The game must show the snapshot under the thumb while the user drags. Click on the game area outside the slider. The game must receive the click. Leave scrub mode. The game area must receive clicks again.

### Task 3: Verify the whole change

**Files:**
- Modify: `docs/superpowers/plans/2026-11-25-time-machine-scrub-input.md` (mark the steps as done)

- [x] **Step 1: Build the Debug configuration**

Run: `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 2: Check the keyboard path**

Manual check: enter Time Machine scrub mode and use the left and right arrow keys. The playhead must still move one snapshot per key press.

- [x] **Step 3: Commit**

Run: `git add docs/superpowers/plans/2026-11-25-time-machine-scrub-input.md TruchiEmu/Core/Engine/Runners/Runners/BaseRunner.swift TruchiEmu/Features/Player/Views/Player/ShaderPlayerComponents/GameTimeBarOverlay.swift TruchiEmu/Features/Player/Views/Player/ShaderPlayerComponents/StandaloneGameWindowController.swift TruchiEmu/Features/Player/Views/Player/ShaderPlayerComponents/StandaloneGameWindowController+Toolbar.swift`
Run: `git commit -m "Fix Time Machine scrub input for D-pad, sticks, and mouse"`
