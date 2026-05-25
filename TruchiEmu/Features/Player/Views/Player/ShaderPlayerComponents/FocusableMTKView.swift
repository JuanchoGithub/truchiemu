import Cocoa
import MetalKit

// MARK: - Focusable MTKView for macOS keyboard and mouse input
class FocusableMTKView: MTKView {
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }



    // Allow runner to be weak so we don't leak
    weak var runner: EmulatorRunner?

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)

        // Auto-start input capture for DOS/ScummVM games on first click
        if let window = self.window, !InputCaptureManager.shared.isCapturing {
            if shouldCaptureInputForCurrentGame() {
                InputCaptureManager.shared.startCapture(window: window)
                LoggerService.info(category: "InputCapture", "Started capture for DOS/ScummVM game")
            }
        }

        LoggerService.debug(category: "InputCapture", "Mouse down: button=0, inCapture=\(InputCaptureManager.shared.isCapturing)")
        XPCBridgeAdapter.shared.setMouseButton(0, pressed: true)
    }

    override func mouseUp(with event: NSEvent) {
        XPCBridgeAdapter.shared.setMouseButton(0, pressed: false)
    }

    override func rightMouseDown(with event: NSEvent) {
        XPCBridgeAdapter.shared.setMouseButton(1, pressed: true)
    }

    override func rightMouseUp(with event: NSEvent) {
        XPCBridgeAdapter.shared.setMouseButton(1, pressed: false)
    }

    override func mouseMoved(with event: NSEvent) {
        LoggerService.debug(category: "InputCapture", "Mouse moved: dx=\(event.deltaX), dy=\(event.deltaY), inCapture=\(InputCaptureManager.shared.isCapturing)")
        updateMouseDelta(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateMouseDelta(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        updateMouseDelta(with: event)
    }

    private func updateMouseDelta(with event: NSEvent) {
        // Use raw NSEvent deltas instead of window coordinates.
        // event.deltaX/deltaY give hardware-level mouse movement that
        // doesn't clamp at window/screen edges — critical when the
        // cursor is hidden and captured for DOS/ScummVM games.
        let dx = Int16(clamping: Int(event.deltaX))
        let dy = Int16(clamping: Int(event.deltaY))  // macOS Y is already inverted for libretro

        if dx != 0 || dy != 0 {
            XPCBridgeAdapter.shared.addMouseDelta(dx, y: dy)
        }

        // Update pointer position for RETRO_DEVICE_POINTER
        updatePointerPosition(event)
    }

    override func scrollWheel(with event: NSEvent) {
        // macOS scroll wheel sends discrete steps, normalize to match libretro expectations
        let delta = Int16(event.scrollingDeltaY * 120) // 120 per "notch"
        if delta != 0 {
            XPCBridgeAdapter.shared.addMouseWheelDelta(delta)
        }
    }

    // MARK: - Pointer Position

    private func updatePointerPosition(_ event: NSEvent) {
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
        // Save state hotkeys - these are handled specially, not sent to core
        if event.modifierFlags.isEmpty || event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 96: // F5 - Quick Save
                Task { @MainActor in
                    _ = runner?.saveState(slot: runner!.currentSlot)
                }
                return
            case 98: // F7 - Quick Load
                Task { @MainActor in
                    _ = runner?.loadState(slot: runner!.currentSlot)
                }
                return
            case 97: // F6 - Slot +1
                Task { @MainActor in
                    runner?.nextSlot()
                }
                return
            case 95: // F4 - Slot -1
                Task { @MainActor in
                    runner?.previousSlot()
                }
                return
            case 6: // Z key (for Cmd+Z Undo)
                if event.modifierFlags.contains(.command) {
                    Task { @MainActor in
                        _ = runner?.undoLoadState()
                    }
                    return
                }
            default:
                break
            }
        }

        // For DOS/ScummVM games, bypass ALL TruchiEmu keyboard handling and send properly mapped keys to DOSBOX
        if shouldCaptureInputForCurrentGame() {
            LoggerService.debug(category: "InputCapture", "DOS/ScummVM keyDown event: keyCode=\(event.keyCode), characters='\(event.characters ?? "")', charactersIgnoringModifiers='\(event.charactersIgnoringModifiers ?? "")'")
            
            // Convert Mac key code to libretro key code using the proper mapper
            let retroKey = RetroKeycodeMapper.retroKey(fromMacOS: event.keyCode)
            guard retroKey != 0 else { 
                LoggerService.debug(category: "InputCapture", "Unmapped key for DOS/ScummVM: keyCode=\(event.keyCode)")
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
            
            LoggerService.debug(category: "InputCapture", "DOS/ScummVM sending keyDown: retroKey=\(retroKey), modifiers=\(modifiers), character=\(characterValue)")
            
            // Send properly mapped key event directly to core
            XPCBridgeAdapter.shared.dispatchKeyboardEvent(
                keycode: retroKey,
                character: characterValue,
                modifiers: modifiers,
                down: true
            )
        } else {
            LoggerService.debug(category: "InputCapture", "Mapped keyboard event for standard core: keyCode=\(event.keyCode)")
            // For standard cores, use the normal mapped path
            if let rid = runner?.mapKey(event.keyCode) {
                runner?.setKeyState(retroID: rid, pressed: true)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        // For DOS/ScummVM games, bypass ALL TruchiEmu keyboard handling and send properly mapped keys to DOSBOX
        if shouldCaptureInputForCurrentGame() {
            LoggerService.debug(category: "InputCapture", "DOS/ScummVM keyUp event: keyCode=\(event.keyCode)")
            
            // Convert Mac key code to libretro key code using the proper mapper
            let retroKey = RetroKeycodeMapper.retroKey(fromMacOS: event.keyCode)
            guard retroKey != 0 else { 
                LoggerService.debug(category: "InputCapture", "Unmapped key for DOS/ScummVM: keyCode=\(event.keyCode)")
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
            LoggerService.debug(category: "InputCapture", "DOS/ScummVM sending keyUp: retroKey=\(retroKey), modifiers=\(modifiers), character=\(characterValue)")
            XPCBridgeAdapter.shared.dispatchKeyboardEvent(
                keycode: retroKey,
                character: characterValue,
                modifiers: modifiers,
                down: false
            )
        } else {
            LoggerService.debug(category: "InputCapture", "Mapped keyUp event for standard core: keyCode=\(event.keyCode)")
            // For standard cores, use the normal mapped path
            if let rid = runner?.mapKey(event.keyCode) {
                runner?.setKeyState(retroID: rid, pressed: false)
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
    private func shouldCaptureInputForCurrentGame() -> Bool {
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
        
        // Auto-start input capture for DOS/ScummVM games
        if let window = self.window, !InputCaptureManager.shared.isCapturing {
            if shouldCaptureInputForCurrentGame() {
                InputCaptureManager.shared.startCapture(window: window)
            }
        }
    }

}
