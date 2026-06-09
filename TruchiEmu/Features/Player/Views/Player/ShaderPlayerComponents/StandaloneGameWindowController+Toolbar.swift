import Cocoa
import SwiftUI

// MARK: - Toolbar Auto-Hide

extension StandaloneGameWindowController {

    @MainActor
    func onMouseActivity() {
        guard !InputCaptureManager.shared.isCapturing else { return }
        if isToolbarVisible {
            scheduleHideToolbar()
        } else {
            showToolbar()
        }
    }

    @MainActor
    func showToolbar() {
        guard !InputCaptureManager.shared.isCapturing else { return }

        if isToolbarVisible {
            scheduleHideToolbar()
            return
        }

        toolbarView?.isHidden = false
        toolbarView?.alphaValue = 0
        isToolbarVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            toolbarView?.animator().alphaValue = 1
        }
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
                    self?.toolbarView?.isHidden = true
                }
            }
        }
    }

    @MainActor
    func hideToolbarImmediateForCapture() {
        hideToolbarTimer?.invalidate()
        hideToolbarTimer = nil
        toolbarView?.isHidden = true
        toolbarView?.alphaValue = 0
        isToolbarVisible = false
    }

    @MainActor
    func showToolbarAfterCapture() {
        toolbarView?.isHidden = false
        showToolbar()
    }
}
