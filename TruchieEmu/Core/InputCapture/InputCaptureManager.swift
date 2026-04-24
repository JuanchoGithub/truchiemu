import Cocoa
import Combine

// MARK: - Input Capture Manager
// Handles keyboard and mouse input capture for game windows.
// When capturing, all keyboard and mouse input is routed to the active game.
@MainActor
class InputCaptureManager: NSObject, ObservableObject {
    static let shared = InputCaptureManager()

    // Published state for UI binding
    @Published private(set) var isCapturing: Bool = false

    // The window being captured (weak to avoid retain cycle)
    private weak var capturedWindow: NSWindow?

    // Local monitor for detecting clicks outside the window
    private var clickMonitor: Any?

    // Local monitor for Escape key (when capturing)
    private var escapeMonitor: Any?

    // Fullscreen state for menu bar hiding
    private var wasInFullscreen: Bool = false

    // MARK: - Accessibility Permissions

    var hasAccessibilityPermissions: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Start Capture

    func startCapture(window: NSWindow) {
        guard !isCapturing else { return }

        capturedWindow = window
        isCapturing = true

        // Hide the cursor
        NSCursor.hide()

        // Store fullscreen state and hide menu bar if needed
        wasInFullscreen = window.styleMask.contains(.fullScreen)
        if wasInFullscreen {
            window.styleMask.remove(.fullSizeContentView)
            window.titlebarAppearsTransparent = false
            // In true fullscreen, macOS hides the menu bar automatically
        }

        // Setup click-outside monitor to release capture
        setupClickOutsideMonitor()

        // Post notification for UI to show capture indicator
        NotificationCenter.default.post(name: .inputCaptureStateChanged, object: nil, userInfo: ["isCapturing": true])

        LoggerService.info(category: "InputCapture", "Input capture started")
    }

    // MARK: - Stop Capture

    func stopCapture() {
        guard isCapturing else { return }

        isCapturing = false

        // Show the cursor again
        NSCursor.unhide()

        // Restore fullscreen state if needed
        if let window = capturedWindow, wasInFullscreen {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
        }

        // Remove monitors
        removeClickOutsideMonitor()

        capturedWindow = nil

        // Post notification for UI to hide capture indicator
        NotificationCenter.default.post(name: .inputCaptureStateChanged, object: nil, userInfo: ["isCapturing": false])

        LoggerService.info(category: "InputCapture", "Input capture stopped")
    }

    // MARK: - Toggle Capture

    func toggleCapture(window: NSWindow) {
        if isCapturing {
            stopCapture()
        } else {
            startCapture(window: window)
        }
    }

    // MARK: - Click Outside Detection

    private func setupClickOutsideMonitor() {
        // Monitor for left mouse down events globally
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let window = self.capturedWindow else { return }

            // Check if the click is outside our window
            let clickLocation = event.locationInWindow
            let windowFrame = window.frame

            // Convert click location from screen coordinates
            if !windowFrame.contains(clickLocation) {
                // Click is outside - stop capture
                Task { @MainActor in
                    self.stopCapture()
                }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - Cmd+F10 Handler

    // Called from the window controller when Cmd+F10 is pressed
    func handleToggleHotkey(window: NSWindow) {
        toggleCapture(window: window)
    }

    // MARK: - Window Resignation Handler

    // Called when the window loses key status
    func handleWindowResignedKey() {
        if isCapturing {
            stopCapture()
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        stopCapture()
        removeClickOutsideMonitor()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let inputCaptureStateChanged = Notification.Name("InputCaptureStateChanged")
}