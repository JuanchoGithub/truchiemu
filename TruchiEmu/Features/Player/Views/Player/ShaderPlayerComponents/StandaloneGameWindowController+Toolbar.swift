import Cocoa
import SwiftUI

// MARK: - Toolbar Auto-Hide

extension StandaloneGameWindowController {

    @MainActor
    func updateToolbarHitRect(_ rect: CGRect) {
        (toolbarView as? SafeHostingView<AnyView>)?.interactiveRect = rect
    }

    @MainActor
    func onMouseActivity() {
        guard !InputCaptureManager.shared.isCapturing else { return }
        if isGamepadToolbarMode { return }
        if isToolbarHovered { return }
        if isToolbarInteractionActive { return }
        if isToolbarVisible {
            scheduleHideToolbar()
        } else {
            showToolbar()
        }
    }

    @MainActor
    var isToolbarInteractionActive: Bool {
        isSlotPickerShown
        || isRecordStreamPickerShown
        || isCheatPickerShown
        || isToolbarMoreShown
    }

    @MainActor
    func toolbarHoverChanged(_ hovering: Bool) {
        isToolbarHovered = hovering
        if hovering {
            cancelToolbarAutoHide()
        } else if isToolbarVisible {
            scheduleHideToolbar()
        }
    }

    @MainActor
    func showToolbar() {
        toolbarFadeGeneration &+= 1

        if isGamepadToolbarMode {
            toolbarView?.isHidden = false
            toolbarView?.alphaValue = 1
            isToolbarVisible = true
            return
        }

        guard !InputCaptureManager.shared.isCapturing else { return }

        if let r = self.runner, r.isRewinding { return }

        if isToolbarVisible {
            toolbarView?.isHidden = false
            toolbarView?.alphaValue = 1
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

    @MainActor
    func scheduleHideToolbar() {
        hideToolbarTimer?.invalidate()
        hideToolbarTimer = nil

        guard !isGamepadToolbarMode else { return }
        guard !isToolbarHovered else { return }
        guard !isToolbarInteractionActive else { return }
        guard !GameToolbarPreferences.shared.pinVisible else { return }

        hideToolbarTimer = Timer.scheduledTimer(
            withTimeInterval: GameToolbarPreferences.shared.effectiveAutoHideDelay,
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hideToolbar()
            }
        }
    }

    @MainActor
    func cancelToolbarAutoHide() {
        hideToolbarTimer?.invalidate()
        hideToolbarTimer = nil
    }

    @MainActor
    func resumeToolbarAutoHide() {
        guard !isGamepadToolbarMode else { return }
        scheduleHideToolbar()
    }

    @MainActor
    func hideToolbar() {
        if isGamepadToolbarMode || isToolbarHovered || isToolbarInteractionActive {
            return
        }
        if GameToolbarPreferences.shared.pinVisible { return }
        if isToolbarVisible {
            let generation = toolbarFadeGeneration
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                toolbarView?.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if generation != self.toolbarFadeGeneration {
                        if self.isToolbarVisible {
                            self.toolbarView?.isHidden = false
                            self.toolbarView?.alphaValue = 1
                        }
                        return
                    }
                    if self.isToolbarHovered || self.isToolbarInteractionActive {
                        self.toolbarView?.isHidden = false
                        self.toolbarView?.alphaValue = 1
                        return
                    }
                    if GameToolbarPreferences.shared.pinVisible {
                        self.toolbarView?.isHidden = false
                        self.toolbarView?.alphaValue = 1
                        return
                    }
                    self.isToolbarVisible = false
                    self.isToolbarHovered = false
                    self.toolbarView?.isHidden = true
                }
            }
        }
    }

    @MainActor
    func hideToolbarImmediateForCapture() {
        toolbarFadeGeneration &+= 1
        hideToolbarTimer?.invalidate()
        hideToolbarTimer = nil
        isToolbarHovered = false
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
