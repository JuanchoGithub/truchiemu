import Cocoa

class CursorAutoHideManager {
    static let shared = CursorAutoHideManager()
    
    private var hideTimer: Timer?
    private var isCursorHidden = false
    private let hideDelay: TimeInterval = 3.0  // 3 seconds
    
    private let hideDelayFullscreen: TimeInterval = 2.0  // Shorter delay in fullscreen
    private let hideDelayWindowed: TimeInterval = 3.0    // Longer delay when windowed
    
    private init() {}
    
    func startMonitoring(isFullscreen: Bool = false) {
        stopMonitoring()
        
        // Use different delays for fullscreen vs windowed mode
        let delay = isFullscreen ? hideDelayFullscreen : hideDelayWindowed
        
        // Start with the appropriate delay
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.hideCursor()
        }
        
        // Monitor mouse activity across more event types
        setupMouseActivityMonitoring()
        
        // Track app lifecycle for proper enter/exit behavior
        setupAppLifecycleTracking()
    }
    
  private func setupMouseActivityMonitoring() {
    let eventMask: NSEvent.EventTypeMask = [
      .mouseMoved,
      .leftMouseDragged,
      .rightMouseDragged,
      .otherMouseDragged,
      .scrollWheel,
      .leftMouseDown,
      .rightMouseDown,
      .otherMouseDown,
      .leftMouseUp,
      .rightMouseUp,
      .otherMouseUp
    ]
    
    // Use local event monitor (no permissions needed) instead of global
    NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
      self?.handleMouseActivity()
      return event // Return unmodified event
    }
    
    // Start hidden initially after game starts
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
      self?.hideCursor()
    }
  }
    
  private func setupAppLifecycleTracking() {
    // Use target/selector pattern instead of closure to avoid weak reference crashes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppActivation),
      name: NSWorkspace.didActivateApplicationNotification,
      object: nil
    )
    
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppDeactivation),
      name: NSWorkspace.didDeactivateApplicationNotification,
      object: nil
    )
  }
  
  @objc private func handleAppActivation() {
    startMonitoring()
  }
  
  @objc private func handleAppDeactivation() {
    stopMonitoring()
    showCursor()
  }
    
    private func handleMouseActivity() {
        showCursorIfNeeded()
        resetTimer()
    }
    
    private func resetTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { [weak self] _ in
            self?.hideCursor()
        }
    }
    
    private func hideCursor() {
        guard !isCursorHidden else { return }
        
        DispatchQueue.main.async {
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        
        isCursorHidden = true
    }
    
    private func showCursorIfNeeded() {
        guard isCursorHidden else { return }
        
        DispatchQueue.main.async {
            NSCursor.setHiddenUntilMouseMoves(false)
        }
        
        isCursorHidden = false
    }
    
    func stopMonitoring() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
    
    func showCursor() {
        isCursorHidden = false
        DispatchQueue.main.async {
            NSCursor.setHiddenUntilMouseMoves(false)
        }
    }
    
    func updateFullscreenState(isFullscreen: Bool) {
        // Adjust delay based on fullscreen state
        hideTimer?.invalidate()
        
        let delay = isFullscreen ? hideDelayFullscreen : hideDelayWindowed
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.hideCursor()
        }
    }
    
    deinit {
        stopMonitoring()
        showCursor()
    }
}

// MARK: - AppDelegate Integration
extension CursorAutoHideManager {
    static func trackAppDeactivation() {
        // Ensure cursor is visible when app loses focus
        CursorAutoHideManager.shared.showCursor()
    }
}
