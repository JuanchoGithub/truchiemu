import Cocoa
import SwiftUI

// MARK: - Toolbar Auto-Hide

extension StandaloneGameWindowController {

    @MainActor
    func onMouseActivity() {
        showToolbar()
    }

    @MainActor
    private func showToolbar() {
        if !isToolbarVisible {
            isToolbarVisible = true
            toolbarView?.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                toolbarView?.animator().alphaValue = 1
            }
        }
        // Restart timer on real mouse activity (filtered by GameContainerView)
        scheduleHideToolbar()
    }

    func scheduleHideToolbar() {
        hideToolbarTimer?.invalidate()
        hideToolbarTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hideToolbar()
            }
        }
    }

    @MainActor
    func hideToolbar() {
        if isToolbarVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                toolbarView?.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.isToolbarVisible = false
                }
            }
        }
    }
}
