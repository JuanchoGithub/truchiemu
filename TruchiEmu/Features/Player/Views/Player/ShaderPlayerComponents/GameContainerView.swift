import Cocoa

// MARK: - Container view with tracking area for toolbar auto-hide
class GameContainerView: NSView {
    weak var windowController: StandaloneGameWindowController?
    private var lastMouseLocation: NSPoint?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove old tracking areas
        for trackingArea in self.trackingAreas {
            removeTrackingArea(trackingArea)
        }
        // Add new tracking area covering the entire view
        let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    override func mouseMoved(with event: NSEvent) {
        // In fullscreen, the cursor position is pinned to the top of the screen,
        // and mouseMoved events keep firing even though the cursor hasn't moved.
        // Only notify the controller if the mouse actually changed position.
        let location = event.locationInWindow
        if lastMouseLocation != location {
            lastMouseLocation = location
            windowController?.onMouseActivity()
        }
    }
}
