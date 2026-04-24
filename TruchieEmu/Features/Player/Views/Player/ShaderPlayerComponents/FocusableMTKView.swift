import Cocoa
import MetalKit

// MARK: - Focusable MTKView for macOS keyboard and mouse input
class FocusableMTKView: MTKView {
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    // Track last mouse position for delta calculation
    private var lastMouseLocation: NSPoint = .zero
    private var isMouseTrackingActive: Bool = false

    // Allow runner to be weak so we don't leak
    weak var runner: EmulatorRunner?

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)

        // Start input capture on click if not already capturing
        if let window = self.window, !InputCaptureManager.shared.isCapturing {
            InputCaptureManager.shared.startCapture(window: window)
        }

        LibretroBridgeSwift.setMouseButton(0, pressed: true)
        lastMouseLocation = event.locationInWindow
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
        let currentLocation = event.locationInWindow
        let deltaX = Int16(currentLocation.x - lastMouseLocation.x)
        let deltaY = Int16(lastMouseLocation.y - currentLocation.y) // Invert Y for libretro

        if deltaX != 0 || deltaY != 0 {
            LibretroBridgeSwift.setMouseDeltaX(deltaX, y: deltaY)
            lastMouseLocation = currentLocation
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

        // Send keyboard event to libretro core via callback or polling state
        dispatchKeyboardEvent(event, down: true)
    }

    override func keyUp(with event: NSEvent) {
        dispatchKeyboardEvent(event, down: false)
    }

    private func dispatchKeyboardEvent(_ event: NSEvent, down: Bool) {
        let keycode = UInt32(event.keyCode)
        let character = UInt32(event.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0)
        let modifiers = encodeModifiers(event.modifierFlags)

        LibretroBridgeSwift.dispatchKeyboardEvent(
            keycode: keycode,
            character: character,
            modifiers: modifiers,
            down: down
        )
    }

    private func encodeModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mod: UInt32 = 0
        if flags.contains(.shift) { mod |= (1 << 0) }
        if flags.contains(.control) { mod |= (1 << 1) }
        if flags.contains(.option) { mod |= (1 << 2) }
        if flags.contains(.command) { mod |= (1 << 3) }
        if flags.contains(.capsLock) { mod |= (1 << 4) }
        return mod
    }

}
