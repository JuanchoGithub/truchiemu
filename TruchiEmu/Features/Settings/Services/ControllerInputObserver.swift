import Foundation
import GameController

/// Owns live input observation for a single selected `PlayerController`.
///
/// Mirrors the attach/detach discipline of `StickVisualizerView`:
/// `valueChangedHandler` is persistent on `GCController`, so when switching
/// between controllers or when the view disappears, all handlers must be
/// explicitly nilled out. Otherwise the previous GC controller keeps firing
/// into this observer's published state.
///
/// All callbacks dispatch to the main queue before mutating published state
/// so SwiftUI observers see consistent updates.
@MainActor
final class ControllerInputObserver: ObservableObject {
    static let shared = ControllerInputObserver()

    @Published private(set) var pressed: Set<PadButton> = []
    @Published private(set) var leftStick: (x: Float, y: Float) = (0, 0)
    @Published private(set) var rightStick: (x: Float, y: Float) = (0, 0)
    @Published private(set) var leftTrigger: Float = 0
    @Published private(set) var rightTrigger: Float = 0

    /// Currently observed controller, if any. Used by callers (the test sheet)
    /// to verify the observer is wired to the expected device.
    @Published private(set) var observedPlayerId: UUID?

    private weak var attachedGCController: GCController?
    private var observedSDLInstanceID: Int32?
    private var observedVendorName: String?

    /// Continuation resumed the next time a `PadButton` becomes pressed. Used
    /// by the test sheet's remap rows so a "press any button to remap" flow
    /// shares the observer's handlers instead of stomping them. Carries nil
    /// when the observer is detached before a press arrives.
    private var captureContinuation: CheckedContinuation<PadButton?, Never>?

    private init() {}

    deinit {
        // Detach the input handlers synchronously. SDL stops are intentionally
        // skipped here because the underlying methods are `@MainActor` and
        // can't be called from a non-isolated deinit. The singleton is alive
        // for the entire app run; `stopObserving()` is called on `onDisappear`
        // and the deinit only fires at app exit, by which point SDL itself is
        // shutting down. GC handler clearing is safe off-main because GC
        // documentation permits synchronous nilling of `valueChangedHandler`.
        if let gc = attachedGCController, let gp = gc.extendedGamepad {
            gp.buttonA.valueChangedHandler = nil
            gp.buttonB.valueChangedHandler = nil
            gp.buttonX.valueChangedHandler = nil
            gp.buttonY.valueChangedHandler = nil
            gp.leftShoulder.valueChangedHandler = nil
            gp.rightShoulder.valueChangedHandler = nil
            gp.leftTrigger.valueChangedHandler = nil
            gp.rightTrigger.valueChangedHandler = nil
            gp.leftThumbstickButton?.valueChangedHandler = nil
            gp.rightThumbstickButton?.valueChangedHandler = nil
            gp.dpad.up.valueChangedHandler = nil
            gp.dpad.down.valueChangedHandler = nil
            gp.dpad.left.valueChangedHandler = nil
            gp.dpad.right.valueChangedHandler = nil
            gp.buttonMenu.valueChangedHandler = nil
            gp.buttonOptions?.valueChangedHandler = nil
            if let xbox = gp as? GCXboxGamepad {
                xbox.buttonShare?.valueChangedHandler = nil
            }
            gp.leftThumbstick.valueChangedHandler = nil
            gp.rightThumbstick.valueChangedHandler = nil
        }
    }

    func startObserving(player: PlayerController) {
        // Snapshot whether something was previously attached so the
        // `controllerInputObserverStopped` notification only fires when
        // we *actually* release a previously-claimed handler slot. A
        // re-entrant call (e.g. when the user changes the selected
        // controller inside the test sheet) must NOT broadcast, because
        // doing so would cause the main settings page to re-attach
        // handlers that the observer is about to take over again — a
        // ping-pong that left the main page frozen and the test sheet
        // unable to read the sticks.
        let wasObserving = observedPlayerId != nil
        stopObserving(notifyOthers: wasObserving)
        observedPlayerId = player.id

        if let gc = player.gcController, let gamepad = gc.extendedGamepad {
            attachGCHandlers(gamepad: gamepad, gc: gc)
        } else if player.isSDL, let sdlID = player.sdlInstanceID {
            attachSDLObservers(instanceID: sdlID)
        }
        resetState()
    }

    func stopObserving(notifyOthers: Bool = true) {
        captureContinuation?.resume(returning: nil)
        captureContinuation = nil
        if let gc = attachedGCController, let gamepad = gc.extendedGamepad {
            gamepad.buttonA.valueChangedHandler = nil
            gamepad.buttonB.valueChangedHandler = nil
            gamepad.buttonX.valueChangedHandler = nil
            gamepad.buttonY.valueChangedHandler = nil
            gamepad.leftShoulder.valueChangedHandler = nil
            gamepad.rightShoulder.valueChangedHandler = nil
            gamepad.leftTrigger.valueChangedHandler = nil
            gamepad.rightTrigger.valueChangedHandler = nil
            gamepad.leftThumbstickButton?.valueChangedHandler = nil
            gamepad.rightThumbstickButton?.valueChangedHandler = nil
            gamepad.dpad.up.valueChangedHandler = nil
            gamepad.dpad.down.valueChangedHandler = nil
            gamepad.dpad.left.valueChangedHandler = nil
            gamepad.dpad.right.valueChangedHandler = nil
            gamepad.buttonMenu.valueChangedHandler = nil
            gamepad.buttonOptions?.valueChangedHandler = nil
            if let xbox = gamepad as? GCXboxGamepad {
                xbox.buttonShare?.valueChangedHandler = nil
            }
            gamepad.leftThumbstick.valueChangedHandler = nil
            gamepad.rightThumbstick.valueChangedHandler = nil
        }
        attachedGCController = nil
        if observedSDLInstanceID != nil {
            SDLInputManager.shared.stopButtonObservation()
            SDLInputManager.shared.stopAxisObservation()
            SDLInputManager.shared.stopTriggerObservation()
            observedSDLInstanceID = nil
        }
        observedVendorName = nil
        observedPlayerId = nil
        resetState()
        // Notify any other observer (e.g. `StickVisualizerView` in the main
        // controller settings page) that the GC `valueChangedHandler`
        // chains and SDL axis observer slots we just released are now
        // free, so it can re-install its own handlers. Posted AFTER all
        // the nil-ing is done so listeners can re-attach without being
        // stomped mid-flight by the rest of this function.
        //
        // Suppressed during a re-entrant call from `startObserving` (the
        // caller passes `notifyOthers: false` because nothing observable
        // is actually being released — the next `attach*` call claims
        // the slots back before the listener's onReceive runs).
        if notifyOthers {
            NotificationCenter.default.post(name: .controllerInputObserverStopped, object: nil)
        }
    }

    /// Returns true if this controller's vendor name was already auto-shown
    /// to the user. Used to suppress the "new controller detected" sheet.
    static func hasSeenVendor(_ vendorName: String) -> Bool {
        let seen: Set<String> = AppSettings.get("controllers_seen_vendor_names", type: Set<String>.self) ?? []
        return seen.contains(vendorName)
    }

    /// Mark a vendor name as seen so subsequent reconnects don't auto-pop
    /// the test sheet.
    static func markVendorSeen(_ vendorName: String) {
        var seen: Set<String> = AppSettings.get("controllers_seen_vendor_names", type: Set<String>.self) ?? []
        seen.insert(vendorName)
        AppSettings.set("controllers_seen_vendor_names", value: seen)
    }

    /// Clear the "seen" set so all controllers re-trigger the welcome sheet.
    static func resetSeenVendors() {
        AppSettings.remove("controllers_seen_vendor_names")
    }

    /// Suspends until the next button press is observed on the currently-
    /// wired controller. Resumes with the `PadButton` that was pressed, or
    /// `nil` if the observer is detached before a press arrives.
    /// Only one capture can be in flight at a time; calling again while a
    /// previous one is pending cancels the previous wait.
    func captureNextButton() async -> PadButton? {
        guard observedPlayerId != nil else { return nil }
        captureContinuation?.resume(returning: nil)
        return await withCheckedContinuation { (cont: CheckedContinuation<PadButton?, Never>) in
            self.captureContinuation = cont
        }
    }

    func cancelCapture() {
        captureContinuation?.resume(returning: nil)
        captureContinuation = nil
    }

    private func resetState() {
        pressed = []
        leftStick = (0, 0)
        rightStick = (0, 0)
        leftTrigger = 0
        rightTrigger = 0
    }

    private func attachGCHandlers(gamepad: GCExtendedGamepad, gc: GCController) {
        let threshold: Float = 0.5
        observedVendorName = gc.vendorName

        let onButton: (GCControllerButtonInput, PadButton) -> Void = { [weak self] input, button in
            DispatchQueue.main.async {
                guard let self else { return }
                if input.isPressed {
                    self.pressed.insert(button)
                    if let cont = self.captureContinuation {
                        self.captureContinuation = nil
                        cont.resume(returning: button)
                    }
                } else {
                    self.pressed.remove(button)
                }
            }
        }

        gamepad.buttonA.valueChangedHandler = { input, _, _ in onButton(input, .a) }
        gamepad.buttonB.valueChangedHandler = { input, _, _ in onButton(input, .b) }
        gamepad.buttonX.valueChangedHandler = { input, _, _ in onButton(input, .x) }
        gamepad.buttonY.valueChangedHandler = { input, _, _ in onButton(input, .y) }
        gamepad.leftShoulder.valueChangedHandler = { input, _, _ in onButton(input, .l1) }
        gamepad.rightShoulder.valueChangedHandler = { input, _, _ in onButton(input, .r1) }
        gamepad.leftThumbstickButton?.valueChangedHandler = { input, _, _ in onButton(input, .l3) }
        gamepad.rightThumbstickButton?.valueChangedHandler = { input, _, _ in onButton(input, .r3) }
        gamepad.buttonMenu.valueChangedHandler = { input, _, _ in onButton(input, .start) }
        gamepad.buttonOptions?.valueChangedHandler = { input, _, _ in onButton(input, .select) }
        if let xboxGamepad = gamepad as? GCXboxGamepad {
            xboxGamepad.buttonShare?.valueChangedHandler = { input, _, _ in onButton(input, .share) }
        }
        gamepad.dpad.up.valueChangedHandler = { input, _, _ in onButton(input, .dpadUp) }
        gamepad.dpad.down.valueChangedHandler = { input, _, _ in onButton(input, .dpadDown) }
        gamepad.dpad.left.valueChangedHandler = { input, _, _ in onButton(input, .dpadLeft) }
        gamepad.dpad.right.valueChangedHandler = { input, _, _ in onButton(input, .dpadRight) }

        gamepad.leftTrigger.valueChangedHandler = { [weak self] input, value, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.leftTrigger = value
                if value > threshold { self.pressed.insert(.l2) } else { self.pressed.remove(.l2) }
            }
        }
        gamepad.rightTrigger.valueChangedHandler = { [weak self] input, value, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.rightTrigger = value
                if value > threshold { self.pressed.insert(.r2) } else { self.pressed.remove(.r2) }
            }
        }

        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            DispatchQueue.main.async {
                guard let self else { return }
                self.leftStick = (x, y)
                // Synthesise digital press events for stick-direction remap.
                // Threshold 0.5 matches the rest of the app.
                self.updateStickDirection(isLeft: true, x: x, y: y, threshold: threshold)
            }
        }
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            DispatchQueue.main.async {
                guard let self else { return }
                self.rightStick = (x, y)
                self.updateStickDirection(isLeft: false, x: x, y: y, threshold: threshold)
            }
        }

        attachedGCController = gc
    }

    /// Update the four stick-direction `PadButton` press states for one
    /// stick based on its current (x, y) position. Used by both the GC
    /// `valueChangedHandler` and the SDL axis observer. Each direction
    /// is updated independently so the user can move diagonally during
    /// remap capture. When a capture continuation is pending, the first
    /// direction that crosses the threshold resumes it.
    private func updateStickDirection(isLeft: Bool, x: Float, y: Float, threshold: Float) {
        let up: PadButton = isLeft ? .lStickUp : .rStickUp
        let down: PadButton = isLeft ? .lStickDown : .rStickDown
        let left: PadButton = isLeft ? .lStickLeft : .rStickLeft
        let right: PadButton = isLeft ? .lStickRight : .rStickRight
        if y > threshold { pressed.insert(up) } else { pressed.remove(up) }
        if y < -threshold { pressed.insert(down) } else { pressed.remove(down) }
        if x < -threshold { pressed.insert(left) } else { pressed.remove(left) }
        if x > threshold { pressed.insert(right) } else { pressed.remove(right) }
        if let cont = captureContinuation {
            let pad: PadButton?
            if y > threshold { pad = up }
            else if y < -threshold { pad = down }
            else if x > threshold { pad = right }
            else if x < -threshold { pad = left }
            else { pad = nil }
            if let pad {
                captureContinuation = nil
                cont.resume(returning: pad)
            }
        }
    }

    private func attachSDLObservers(instanceID: Int32) {
        observedSDLInstanceID = instanceID
        SDLInputManager.shared.startButtonObservation(instanceID: instanceID) { [weak self] _, padButton, pressed in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let padButton else { return }
                if pressed {
                    self.pressed.insert(padButton)
                    if let cont = self.captureContinuation {
                        self.captureContinuation = nil
                        cont.resume(returning: padButton)
                    }
                } else {
                    self.pressed.remove(padButton)
                }
            }
        }
        SDLInputManager.shared.startAxisObservation(instanceID: instanceID) { [weak self] lx, ly, rx, ry in
            DispatchQueue.main.async {
                guard let self else { return }
                self.leftStick = (lx, ly)
                self.rightStick = (rx, ry)
                // Same direction synthesis as the GC path so the remap
                // capture flow works for SDL controllers too. SDL axes are
                // already in the [-1, 1] range GameController uses.
                self.updateStickDirection(isLeft: true, x: lx, y: ly, threshold: 0.5)
                self.updateStickDirection(isLeft: false, x: rx, y: ry, threshold: 0.5)
            }
        }
        SDLInputManager.shared.startTriggerObservation(instanceID: instanceID) { [weak self] _, padButton, value in
            DispatchQueue.main.async {
                guard let self else { return }
                switch padButton {
                case .l2: self.leftTrigger = value
                case .r2: self.rightTrigger = value
                default: break
                }
                if value > 0.5 { self.pressed.insert(padButton) } else { self.pressed.remove(padButton) }
            }
        }
    }
}
