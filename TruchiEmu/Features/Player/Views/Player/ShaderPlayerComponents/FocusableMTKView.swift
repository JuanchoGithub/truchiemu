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

        // Start input capture on click if not already capturing
        if let window = self.window, !InputCaptureManager.shared.isCapturing {
            let coreID = runner?.rom?.systemID?.lowercased() ?? ""
            if coreID == "dos" || coreID == "scummvm" {
                InputCaptureManager.shared.startCapture(window: window)
            }
        }

        LibretroBridgeSwift.setMouseButton(0, pressed: true)
    }

    override func mouseUp(with event: NSEvent) {
        LibretroBridgeSwift.setMouseButton(0, pressed: false)
    }

    override func rightMouseDown(with event: NSEvent) {
        LibretroBridgeSwift.setMouseButton(1, pressed: true)
    }

    override func rightMouseUp(with event: NSEvent) {
        LibretroBridgeSwift.setMouseButton(1, pressed: false)
    }

    override func mouseMoved(with event: NSEvent) {
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
            LibretroBridgeSwift.addMouseDelta(dx, y: dy)
        }

        // Update pointer position for RETRO_DEVICE_POINTER
        updatePointerPosition(event)
    }

    override func scrollWheel(with event: NSEvent) {
        // macOS scroll wheel sends discrete steps, normalize to match libretro expectations
        let delta = Int16(event.scrollingDeltaY * 120) // 120 per "notch"
        if delta != 0 {
            LibretroBridgeSwift.addMouseWheelDelta(delta)
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
        LibretroBridgeSwift.setPointerPosition(normalizedX, y: normalizedY, pressed: isPressed)
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

        // 1. Mapped Path: Send to Joypad mapping (for standard cores)
        if let rid = runner?.mapKey(event.keyCode) {
            runner?.setKeyState(retroID: rid, pressed: true)
        }

        // 2. Raw Path: Send to Libretro core (for DOS/ScummVM)
        dispatchKeyboardEvent(event, down: true)
    }

    override func keyUp(with event: NSEvent) {
        // 1. Mapped Path: Send to Joypad mapping (for standard cores)
        if let rid = runner?.mapKey(event.keyCode) {
            runner?.setKeyState(retroID: rid, pressed: false)
        }

        // 2. Raw Path: Send to Libretro core (for DOS/ScummVM)
        dispatchKeyboardEvent(event, down: false)
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

        LibretroBridgeSwift.dispatchKeyboardEvent(
            keycode: retroKey,
            character: character,
            modifiers: modifiers,
            down: down
        )
    }

}
