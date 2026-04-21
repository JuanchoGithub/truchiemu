import Cocoa
import MetalKit

// MARK: - Focusable MTKView for macOS keyboard input
class FocusableMTKView: MTKView {
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    
    // Tracks active game keys to properly release them on keyUp
    private var activeGameKeys: Set<Int> = []
    
    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
    
    override func keyDown(with event: NSEvent) {
        // Escape - pass through
        if event.keyCode == 53 {
            super.keyDown(with: event)
            return
        }
        
        // Save state hotkeys (only process when not in text input)
        if event.modifierFlags.isEmpty || event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 96: // F5 - Quick Save
                Task { @MainActor in
                    _ = runner?.saveState(slot: runner!.currentSlot)
                }
                return
                
            case 98: // F7 - Quick Load
                Task { @MainActor in
                    let success = runner?.loadState(slot: runner!.currentSlot) ?? false
                    if success {
                        // Show undo hint
                    }
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
                // Fall through to normal key handling
                break
                
            default:
                break
            }
        }
        
        // Normal game key
        if let rid = runner?.mapKey(event.keyCode) {
            activeGameKeys.insert(rid)
            runner?.setKeyState(retroID: rid, pressed: true)
        }
    }
    
    override func keyUp(with event: NSEvent) {
        // Release game keys
        if let rid = runner?.mapKey(event.keyCode) {
            activeGameKeys.remove(rid)
            runner?.setKeyState(retroID: rid, pressed: false)
        }
        super.keyUp(with: event)
    }
    
    // Allow runner to be weak so we don't leak
    weak var runner: EmulatorRunner?
}
