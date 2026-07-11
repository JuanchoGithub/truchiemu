import Cocoa
import MetalKit

// MARK: - Focusable MTKView for macOS keyboard and mouse input
class FocusableMTKView: MTKView {
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    private static let slotActions: [HotkeyAction] = [.slot0, .slot1, .slot2, .slot3, .slot4, .slot5, .slot6, .slot7, .slot8, .slot9]

    weak var runner: EmulatorRunner?
    weak var windowController: StandaloneGameWindowController?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in self.trackingAreas {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)

        if let toolbarView = windowController?.toolbarView,
           !toolbarView.isHidden,
           toolbarView.window == self.window {
            let clickLocation = event.locationInWindow
            let toolbarFrame = toolbarView.frame
            if toolbarFrame.contains(clickLocation) {
                return
            }
        }

        if let window = self.window, !InputCaptureManager.shared.isCapturing {
            let sidebarOpen = windowController?.gameGuideViewModel.isSidebarVisible == true
            if shouldCaptureInputForCurrentGame() && !sidebarOpen {
                InputCaptureManager.shared.startCapture(window: window)
                return
            }
        }

        if InputCaptureManager.shared.isCapturing {
            XPCBridgeAdapter.shared.setMouseButton(0, pressed: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if InputCaptureManager.shared.isCapturing {
            XPCBridgeAdapter.shared.setMouseButton(0, pressed: false)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if InputCaptureManager.shared.isCapturing {
            XPCBridgeAdapter.shared.setMouseButton(1, pressed: true)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        if InputCaptureManager.shared.isCapturing {
            XPCBridgeAdapter.shared.setMouseButton(1, pressed: false)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        #if LOG_DEBUG
        // LoggerService.debug(category: "InputCapture", "Mouse moved: dx=\(event.deltaX), dy=\(event.deltaY), inCapture=\(InputCaptureManager.shared.isCapturing)")
        #endif
        updateMouseDelta(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateMouseDelta(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        updateMouseDelta(with: event)
    }

    private func updateMouseDelta(with event: NSEvent) {
        if InputCaptureManager.shared.isCapturing {
            let dx = Int16(clamping: Int(event.deltaX))
            let dy = Int16(clamping: Int(event.deltaY))

            if dx != 0 || dy != 0 {
                XPCBridgeAdapter.shared.addMouseDelta(dx, y: dy)
            }
        }

        updatePointerPosition(event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard InputCaptureManager.shared.isCapturing else { return }
        let delta = Int16(event.scrollingDeltaY * 120) // 120 per "notch"
        if delta != 0 {
            XPCBridgeAdapter.shared.addMouseWheelDelta(delta)
        }
    }

    // MARK: - Pointer Position

    private func updatePointerPosition(_ event: NSEvent) {
        guard InputCaptureManager.shared.isCapturing else { return }

        let location = event.locationInWindow
        let size = self.bounds.size

        guard size.width > 0 && size.height > 0 else { return }

        // Convert to libretro coordinate space: -0x7fff to 0x7fff
        // Clamp ratios to [0, 1] to prevent Int16 overflow during conversion
        let ratioX = max(0.0, min(1.0, location.x / size.width))
        let ratioY = max(0.0, min(1.0, 1.0 - location.y / size.height))
        let normalizedX = Int16(ratioX * 2.0 * 0x7FFF - 0x7FFF)
        let normalizedY = Int16(ratioY * 2.0 * 0x7FFF - 0x7FFF)

        let isPressed = (NSEvent.pressedMouseButtons & 0x1) != 0
        XPCBridgeAdapter.shared.setPointerPosition(normalizedX, y: normalizedY, pressed: isPressed)
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        let hotkeys = HotkeyConfigManager.shared
        let systemID = runner?.systemID

        if hotkeys.matches(.screenshot, systemID: systemID, event: event) {
            Task { @MainActor in
                self.runner?.performScreenshot()
            }
            return
        }

        if hotkeys.matches(.saveState, systemID: systemID, event: event) {
            HardcoreModeManager.shared.attemptSaveState { [weak self] in
                Task { @MainActor in _ = self?.runner?.saveState(slot: self!.runner!.currentSlot) }
            }
            return
        }
        if hotkeys.matches(.loadState, systemID: systemID, event: event) {
            HardcoreModeManager.shared.attemptLoadState { [weak self] in
                Task { @MainActor in _ = self?.runner?.loadState(slot: self!.runner!.currentSlot) }
            }
            return
        }
        if hotkeys.matches(.undoLoadState, systemID: systemID, event: event) {
            Task { @MainActor in _ = runner?.undoLoadState() }
            return
        }
        if hotkeys.matches(.slotNext, systemID: systemID, event: event) {
            Task { @MainActor in runner?.nextSlot() }
            return
        }
        if hotkeys.matches(.slotPrev, systemID: systemID, event: event) {
            Task { @MainActor in runner?.previousSlot() }
            return
        }
        for slot in 0...9 {
            if hotkeys.matches(Self.slotActions[slot], systemID: systemID, event: event) {
                Task { @MainActor in runner?.currentSlot = slot }
                return
            }
        }

        if let windowCtrl = windowController, windowCtrl.trainingModeViewModel.isTrainingEnabled {
            if hotkeys.matches(.trainingReset, systemID: systemID, event: event) {
                Task { @MainActor in windowCtrl.trainingModeViewModel.performReset() }
                return
            }
            if hotkeys.matches(.trainingToggleRecording, systemID: systemID, event: event) {
                Task { @MainActor in windowCtrl.trainingModeViewModel.toggleRecording() }
                return
            }
            if hotkeys.matches(.trainingStartPlayback, systemID: systemID, event: event) {
                Task { @MainActor in TrainingModeManager.shared.startTapePlayback() }
                return
            }
        }

        if hotkeys.matches(.rewind, systemID: systemID, event: event) {
            HardcoreModeManager.shared.attemptRewind { [weak self] in
                Task { @MainActor in self?.runner?.toggleTimeMachineMode() }
            }
            return
        }
        // While in Time Machine scrub mode, left/right arrow keys step the
        // playhead across saved snapshots. Any other key the user has bound
        // to the core's left/right (e.g., A/D) is also intercepted —
        // see mapKey below. Uses isRewindingStorage for a non-isolated read.
        if let runner = self.runner, runner.isRewindingStorage {
            if event.keyCode == 123 { // kVK_LeftArrow
                LoggerService.info(category: "TimeMachine", "Keyboard ← arrow → stepping back")
                Task { @MainActor in runner.stepTimeMachine(direction: -1) }
                return
            }
            if event.keyCode == 124 { // kVK_RightArrow
                LoggerService.info(category: "TimeMachine", "Keyboard → arrow → stepping forward")
                Task { @MainActor in runner.stepTimeMachine(direction: 1) }
                return
            }
            if let mapped = runner.mapKey(event.keyCode),
               mapped.retroID == 6 || mapped.retroID == 7 {
                let dir = mapped.retroID == 6 ? -1 : 1
                LoggerService.info(category: "TimeMachine", "Keyboard bound key keyCode=\(event.keyCode) retroID=\(mapped.retroID) → stepping dir=\(dir)")
                Task { @MainActor in runner.stepTimeMachine(direction: dir) }
                return
            } else if runner.mapKey(event.keyCode) != nil {
                // Log the bind to figure out why left/right binding not match.
                if let mapped = runner.mapKey(event.keyCode) {
                    LoggerService.debug(category: "TimeMachine", "Keyboard mapped keyCode=\(event.keyCode) → retroID=\(mapped.retroID) (NOT 6/7, ignored in scrub mode)")
                }
            }
        }
        if hotkeys.matches(.slowMotion, systemID: systemID, event: event) {
            HardcoreModeManager.shared.attemptSlowMotion { [weak self] in
                Task { @MainActor in self?.runner?.toggleSlowMotion() }
            }
            return
        }
        if hotkeys.matches(.fastForward, systemID: systemID, event: event) {
            HardcoreModeManager.shared.attemptFastForward { [weak self] in
                Task { @MainActor in self?.runner?.toggleFastForward() }
            }
            return
        }

        if hotkeys.matches(.toggleTrainingMode, systemID: systemID, event: event) {
            if let windowCtrl = windowController {
                Task { @MainActor in TrainingModeManager.shared.setEnabled(!windowCtrl.trainingModeViewModel.isTrainingEnabled) }
            }
            return
        }

        // For DOS/ScummVM games, bypass ALL TruchiEmu keyboard handling and send properly mapped keys to DOSBOX
        if shouldCaptureInputForCurrentGame() {
            #if LOG_DEBUG
            LoggerService.debug(category: "InputCapture", "DOS/ScummVM keyDown event: keyCode=\(event.keyCode), characters='\(event.characters ?? "")', charactersIgnoringModifiers='\(event.charactersIgnoringModifiers ?? "")'")
            #endif
            
            // Convert Mac key code to libretro key code using the proper mapper
            let retroKey = RetroKeycodeMapper.retroKey(fromMacOS: event.keyCode)
            guard retroKey != 0 else { 
                #if LOG_DEBUG
                LoggerService.debug(category: "InputCapture", "Unmapped key for DOS/ScummVM: keyCode=\(event.keyCode)")
                #endif
                return 
            }
            
            // Convert modifiers to retro format
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.shift) { modifiers |= 1 << 0 }
            if event.modifierFlags.contains(.control) { modifiers |= 1 << 1 }
            if event.modifierFlags.contains(.option) { modifiers |= 1 << 2 }
            if event.modifierFlags.contains(.command) { modifiers |= 1 << 3 }
            
            // Get the proper character - if shift is pressed and it's a letter, use uppercase
            var characterValue: UInt32 = 0
            if let chars = event.charactersIgnoringModifiers {
                if event.modifierFlags.contains(.shift) {
                    // For shift+letter, convert to uppercase
                    characterValue = UInt32(chars.uppercased().unicodeScalars.first?.value ?? 0)
                } else {
                    characterValue = UInt32(chars.unicodeScalars.first?.value ?? 0)
                }
            }
            
            #if LOG_DEBUG
            // LoggerService.debug(category: "InputCapture", "DOS/ScummVM sending keyDown: retroKey=\(retroKey), modifiers=\(modifiers), character=\(characterValue)")
            #endif
            
            // Send properly mapped key event directly to core
            XPCBridgeAdapter.shared.dispatchKeyboardEvent(
                keycode: retroKey,
                character: characterValue,
                modifiers: modifiers,
                down: true
            )
        } else {
            #if LOG_DEBUG
            // LoggerService.debug(category: "InputCapture", "Mapped keyboard event for standard core: keyCode=\(event.keyCode)")
            #endif
            // For standard cores, use the normal mapped path
            if let mapped = runner?.mapKey(event.keyCode) {
                runner?.setKeyState(retroID: mapped.retroID, player: mapped.player, pressed: true)
            }
        }
    }

    override func keyUp(with event: NSEvent) {

        // Rewind is now a toggle (press once to enter, again to exit). No
        // key-up handling needed.

        // For DOS/ScummVM games, bypass ALL TruchiEmu keyboard handling and send properly mapped keys to DOSBOX
        if shouldCaptureInputForCurrentGame() {
            #if LOG_DEBUG
            // LoggerService.debug(category: "InputCapture", "DOS/ScummVM keyUp event: keyCode=\(event.keyCode)")
            #endif
            
            // Convert Mac key code to libretro key code using the proper mapper
            let retroKey = RetroKeycodeMapper.retroKey(fromMacOS: event.keyCode)
            guard retroKey != 0 else { 
                #if LOG_DEBUG
                // LoggerService.debug(category: "InputCapture", "Unmapped key for DOS/ScummVM: keyCode=\(event.keyCode)")
                #endif
                return 
            }
            
            // Convert modifiers to retro format
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.shift) { modifiers |= 1 << 0 }
            if event.modifierFlags.contains(.control) { modifiers |= 1 << 1 }
            if event.modifierFlags.contains(.option) { modifiers |= 1 << 2 }
            if event.modifierFlags.contains(.command) { modifiers |= 1 << 3 }
            
            // Get the proper character - if shift is pressed and it's a letter, use uppercase
            var characterValue: UInt32 = 0
            if let chars = event.charactersIgnoringModifiers {
                if event.modifierFlags.contains(.shift) {
                    // For shift+letter, convert to uppercase
                    characterValue = UInt32(chars.uppercased().unicodeScalars.first?.value ?? 0)
                } else {
                    characterValue = UInt32(chars.unicodeScalars.first?.value ?? 0)
                }
            }
            
            // Send properly mapped key event directly to core
            #if LOG_DEBUG
            // LoggerService.debug(category: "InputCapture", "DOS/ScummVM sending keyUp: retroKey=\(retroKey), modifiers=\(modifiers), character=\(characterValue)")
            #endif
            XPCBridgeAdapter.shared.dispatchKeyboardEvent(
                keycode: retroKey,
                character: characterValue,
                modifiers: modifiers,
                down: false
            )
        } else {
            #if LOG_DEBUG
            // LoggerService.debug(category: "InputCapture", "Mapped keyUp event for standard core: keyCode=\(event.keyCode)")
            #endif
            // For standard cores, use the normal mapped path
            if let mapped = runner?.mapKey(event.keyCode) {
                runner?.setKeyState(retroID: mapped.retroID, player: mapped.player, pressed: false)
            }
        }
    }

    private func dispatchKeyboardEvent(_ event: NSEvent, down: Bool) {
        // Translate macOS virtual keycode → libretro RETROK_* value.
        // Without this, the core receives meaningless hardware scan codes
        // (e.g., 'A' = 0x00) instead of the expected RETROK values
        // (e.g., RETROK_a = 97). This is why keyboard input failed in-game.
        let retroKey = RetroKeycodeMapper.retroKey(fromMacOS: event.keyCode)

        // Skip unmapped keys (RETROK_UNKNOWN = 0)
        guard retroKey != 0 else { return }

        let character = UInt32(event.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0)
        let modifiers = RetroKeycodeMapper.retroMod(from: event.modifierFlags)

        XPCBridgeAdapter.shared.dispatchKeyboardEvent(
            keycode: retroKey,
            character: character,
            modifiers: modifiers,
            down: down
        )
    }

    // MARK: - Input Capture Helpers

    /// Returns true if the current game should use full input capture (DOS/ScummVM)
    func shouldCaptureInputForCurrentGame() -> Bool {
        guard let runner = runner else { return false }
        let systemID = runner.systemID.lowercased()
        return systemID == "dos" || systemID == "scummvm"
    }

    /// Updates input capture state when the runner changes
    func updateRunner() {
        // Stop capture if the runner changed (different game/system)
        if InputCaptureManager.shared.isCapturing && !shouldCaptureInputForCurrentGame() {
            InputCaptureManager.shared.stopCapture(reason: "Runner changed")
        }

        // Update window reference in runner
        runner?.window = self.window
                runner?.gameWindow = self.window
                LoggerService.info(category: "FocusableMTKView", "updateRunner: set gameWindow=\(String(describing: self.window))")

        // Auto-start input capture for DOS/ScummVM games (unless sidebar is open)
        if let window = self.window, !InputCaptureManager.shared.isCapturing {
            let sidebarOpen = windowController?.gameGuideViewModel.isSidebarVisible == true
            if shouldCaptureInputForCurrentGame() && !sidebarOpen {
                InputCaptureManager.shared.startCapture(window: window)
            }
        }
    }

}
