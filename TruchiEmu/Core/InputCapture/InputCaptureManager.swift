import Cocoa
import Combine
import CoreGraphics

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
    private var mouseMonitor: Any?
    private var escapeMonitor: Any?
    private var localEventMonitors: [Any] = []

    // Fullscreen state for menu bar hiding
    private var wasInFullscreen: Bool = false

    // ESC triple-press escape detection
    private var escapePressTimestamps: [TimeInterval] = []
    private let escapeTripleWindow: TimeInterval = 1.0
    @Published private(set) var lastEscapeToastMessage: String? = nil
    @Published private(set) var captureStartTime: Date? = nil

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
        captureStartTime = Date()

        LoggerService.info(category: "InputCapture", "!!! DEBUG: STARTING CAPTURE WITH NEW VERSION !!!")

        // Hide the cursor
        NSCursor.hide()

        // Dissociate cursor position from mouse movement.
        // This prevents the hidden cursor from hitting screen edges,
        // ensuring raw deltas (NSEvent.deltaX/deltaY) continue flowing.
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))

        // Store fullscreen state and hide menu bar if needed
        wasInFullscreen = window.styleMask.contains(.fullScreen)
        if wasInFullscreen {
            window.styleMask.remove(.fullSizeContentView)
            window.titlebarAppearsTransparent = false
            // In true fullscreen, macOS hides the menu bar automatically
        }

        // Setup mouse and keyboard event monitors
        setupEventMonitors()

        // Setup click-outside monitor to release capture
        setupClickOutsideMonitor()

        // Listen for app resigning active to release capture
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        // Post notification for UI to show capture indicator
        NotificationCenter.default.post(name: .inputCaptureStateChanged, object: nil, userInfo: ["isCapturing": true])

        showEscapeToast(captured: true)

        LoggerService.info(category: "InputCapture", "Input capture started")
    }

    // MARK: - Stop Capture

    func stopCapture(reason: String = "Unknown") {
        guard isCapturing else { return }

        isCapturing = false
        captureStartTime = nil

        // Show the cursor again
        NSCursor.unhide()

        // Re-associate cursor with mouse movement
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))

        // Restore fullscreen state if needed
        if let window = capturedWindow, wasInFullscreen {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
        }

        // Remove monitors
        removeEventMonitors()
        removeClickOutsideMonitor()

        // Remove app resignation observer
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)

        capturedWindow = nil

        // Post notification for UI to hide capture indicator
        NotificationCenter.default.post(name: .inputCaptureStateChanged, object: nil, userInfo: ["isCapturing": false])

        LoggerService.info(category: "InputCapture", "Input capture stopped. Reason: \(reason)")
    }

    @objc private func handleAppResignActive() {
        stopCapture(reason: "App resigned active")
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
                    self.stopCapture(reason: "Click outside window")
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

    // MARK: - Event Monitors

    private func setupEventMonitors() {
        let masks: [NSEvent.EventTypeMask] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel
        ]
        for mask in masks {
            let handle = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.handleMouseEvent(event)
                return event
            }
            localEventMonitors.append(handle)
        }

        let escapeHandle = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isCapturing else { return event }
            if event.keyCode == 53 {
                self.handleEscapePress()
                return nil
            }
            if event.modifierFlags.contains(.command) && event.keyCode == 46 {
                self.stopCapture(reason: "Cmd-M shortcut")
                self.showEscapeToast(captured: false)
                return nil
            }
            return event
        }
        localEventMonitors.append(escapeHandle)
    }

    private func handleEscapePress() {
        let now = Date().timeIntervalSince1970
        escapePressTimestamps.append(now)
        escapePressTimestamps = escapePressTimestamps.filter { now - $0 < escapeTripleWindow }

        if escapePressTimestamps.count >= 3 {
            escapePressTimestamps.removeAll()
            stopCapture(reason: "ESC×3 escape combo")
            showEscapeToast(captured: false)
        }
    }

    private func showEscapeToast(captured: Bool) {
        let loc = LocalizationManager.shared
        if captured {
            lastEscapeToastMessage = loc.localized("input.escapeToast.captured")
        } else {
            lastEscapeToastMessage = loc.localized("input.escapeToast.released")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.lastEscapeToastMessage = nil
        }
    }
    
    private func handleMouseEvent(_ event: NSEvent) {
        guard let window = capturedWindow else { return }

        if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
            if isClickOnGuideSidebar(event, in: window) {
                stopCapture(reason: "Click on guide sidebar")
                showEscapeToast(captured: false)
                return
            }
        }

        let windowLocation = event.locationInWindow

        if let newEvent = NSEvent.mouseEvent(
            with: event.type,
            location: windowLocation,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: event.clickCount,
            pressure: event.pressure
        ) {
            window.sendEvent(newEvent)
        }
    }
    
    private func isClickOnGuideSidebar(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard let contentView = window.contentView else { return false }
        let clickInWindow = event.locationInWindow
        for view in contentView.subviews {
            if view.responds(to: Selector(("consumesMouseEventsInFrame"))) {
                if let consumes = view.value(forKey: "consumesMouseEventsInFrame") as? Bool, consumes {
                    let clickInView = view.convert(clickInWindow, from: nil)
                    if view.bounds.contains(clickInView) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func forwardMouseEvent(_ event: NSEvent) {
        guard let window = capturedWindow else { return }
        
        LoggerService.debug(category: "InputCapture", "Forwarding mouse event: type=\(event.type), location=\(event.locationInWindow)")
        
        // Create a new mouse event with the same properties and send it to the window
        // Note: buttonNumber is not available in all NSEvent.mouseEvent variants
        let mouseEvent = NSEvent.mouseEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: event.clickCount,
            pressure: event.pressure
        )
        
        if let mouseEvent = mouseEvent {
            window.sendEvent(mouseEvent)
        }
    }

    private func removeEventMonitors() {
        for monitor in localEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        localEventMonitors.removeAll()
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    // Called from the window controller when Cmd+F10 is pressed
    func handleToggleHotkey(window: NSWindow) {
        toggleCapture(window: window)
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
    static let toggleGuideSidebar = Notification.Name("ToggleGuideSidebar")
    static let guideControllerSelect = Notification.Name("GuideControllerSelect")
    static let guideControllerBack = Notification.Name("GuideControllerBack")
}