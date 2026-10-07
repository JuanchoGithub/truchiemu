import Cocoa
import SwiftUI

extension StandaloneGameWindowController {

    @MainActor
    func showGamepadToolbar() {
        // Guard against a second open while already open. Each open pushes
        // a nav context. A duplicate push leaks the first context. The stale
        // context then keeps routing A (Select) to the toolbar after close.
        // Pressing A on the Restart button calls reloadGame and looks like
        // "A+B resets the game".
        if isGamepadToolbarMode && gameToolbarNavContext != nil { return }
        hideToolbarTimer?.invalidate()
        isGamepadToolbarMode = true
        GamepadNavigationManager.shared.isGamepadToolbarActive = true
        gamepadToolbarFocusedIndex = 0
        isStopConfirmArmed = false

        let ctx = GamepadGameToolbarContext(itemCount: gamepadToolbarButtonCount)
        ctx.ownedWindow = window
        ctx.skipIndices = computeHiddenToolbarIndices()
        ctx.onSelect = { [weak self] _ in self?.gamepadToolbarActivateFocusedButton() }
        ctx.onDismiss = { [weak self] in self?.exitGamepadToolbarMode() }
        ctx.onNavigate = { [weak self] in
            guard let self, let ctx = self.gameToolbarNavContext else { return }
            self.gamepadToolbarFocusedIndex = ctx.focusIndex
            if ctx.focusIndex != 0 {
                self.isStopConfirmArmed = false
            }
        }
        gameToolbarNavContext = ctx
        GamepadNavContextStack.shared.push(ctx)

        let nav = GamepadNavigationManager.shared
        let sysID = runner?.systemID.lowercased()
        nav.suppressLeftStickInToolbar = (sysID == "dos" || sysID == "scummvm")
        if !isToolbarVisible {
            showToolbar()
        }
        // Keep the toolbar visible while navigating by gamepad; don't let the
        // mouse-activity auto-hide timer dismiss it during couch play.
        hideToolbarTimer?.invalidate()
        hideToolbarTimer = nil
        // Pause the game while navigating the toolbar. Remember whether it was
        // already paused so exiting the toolbar restores that state instead of
        // unconditionally resuming.
        if let r = runner {
            wasPausedBeforeGamepadToolbar = r.isPaused
            r.setPaused(true)
        }
        // Releases during toolbar nav are dropped, so Start+Select stick in
        // the core. Clear them now or A+B after close looks like a reset.
        XPCBridgeAdapter.shared.clearAllJoypadInputs()
    }

    @MainActor
    func exitGamepadToolbarMode() {
        isGamepadToolbarMode = false
        gamepadToolbarFocusedIndex = nil
        GamepadNavigationManager.shared.isGamepadToolbarActive = false
        isStopConfirmArmed = false

        if let ctx = gameToolbarNavContext {
            GamepadNavContextStack.shared.remove(ctx)
        }
        gameToolbarNavContext = nil

        let nav = GamepadNavigationManager.shared
        nav.suppressLeftStickInToolbar = false
        // Clear again. Presses made inside the toolbar must not leak into
        // the game when it resumes.
        XPCBridgeAdapter.shared.clearAllJoypadInputs()
        if let r = runner {
            r.setPaused(wasPausedBeforeGamepadToolbar)
        }
        scheduleHideToolbar()
    }

    @MainActor
    func gamepadToolbarNavigateLeft() {
        guard isGamepadToolbarMode, let ctx = gameToolbarNavContext else { return }
        gamepadToolbarFocusedIndex = ctx.focusIndex
    }

    @MainActor
    func gamepadToolbarNavigateRight() {
        guard isGamepadToolbarMode, let ctx = gameToolbarNavContext else { return }
        gamepadToolbarFocusedIndex = ctx.focusIndex
    }

    @MainActor
    func gamepadToolbarActivateFocusedButton() {
        // Never fire toolbar buttons when toolbar mode is off. This stops
        // a late A press from hitting Restart (reloadGame) after close.
        guard isGamepadToolbarMode else { return }
        guard let idx = gamepadToolbarFocusedIndex, let r = runner else { return }
        var buttonIndex = 0
        // 0: Stop (gamepad-only confirm; mouse clicks bypass this and close immediately)
        if idx == buttonIndex {
            if isStopConfirmArmed {
                window?.close()
            } else {
                isStopConfirmArmed = true
            }
            return
        }
        buttonIndex += 1
        // 1: Pause / Resume -> close toolbar and resume play (matches spec)
        if idx == buttonIndex {
            exitGamepadToolbarMode()
            return
        }
        buttonIndex += 1
        // 2: Restart -> reload, close toolbar, resume
        if idx == buttonIndex {
            r.reloadGame()
            exitGamepadToolbarMode()
            return
        }
        buttonIndex += 1
        // 3: Save State -> save, keep toolbar open, game stays paused (per spec)
        if idx == buttonIndex {
            if !saveStatesDisabled {
                HardcoreModeManager.shared.attemptSaveState {
                    Task { @MainActor in _ = r.saveState(slot: r.currentSlot) }
                }
            }
            return
        }
        buttonIndex += 1
        // 4: Load State -> load, close toolbar and resume (per spec)
        if idx == buttonIndex {
            if !saveStatesDisabled {
                HardcoreModeManager.shared.attemptLoadState {
                    Task { @MainActor in
                        _ = r.loadState(slot: r.currentSlot)
                        self.exitGamepadToolbarMode()
                    }
                }
            }
            return
        }
        buttonIndex += 1
        // 5: Slot picker -> open the slot popover (driven by isSlotPickerShown)
        if idx == buttonIndex {
            if !saveStatesDisabled {
                isSlotPickerShown = true
            }
            return
        }
        buttonIndex += 1
        // 6: Record / Stream -> mirrors the mouse onTapGesture: clear error,
        // stop connecting / recording, or open the stream-picker popover.
        if idx == buttonIndex {
            let recordingService = StreamRecordingService.shared
            if recordingService.streamError != nil {
                recordingService.streamError = nil
            } else if case .connecting = recordingService.streamStatus {
                recordingService.stop()
            } else if recordingService.isUserRecording {
                recordingService.stop()
            } else {
                isRecordStreamPickerShown = true
            }
            return
        }
        buttonIndex += 1
        // 7: Cheats -> open the cheat popover (mirrors the slot/record popovers)
        if idx == buttonIndex {
            HardcoreModeManager.shared.attemptUseCheats {
                self.isCheatPickerShown = true
            }
            return
        }
        // 8 (conditional): Training
        if trainingModeViewModel.hasGameData {
            buttonIndex += 1
            if idx == buttonIndex { toggleTrainingModeOverlay(); return }
        }
        // 9 (conditional): Guide
        if gameGuideViewModel.hasGuideData {
            buttonIndex += 1
            if idx == buttonIndex { toggleGuideSidebar(); return }
        }
        buttonIndex += 1
        // 10/11: Fullscreen
        if idx == buttonIndex { toggleFullscreen(); return }
        buttonIndex += 1
        // 11/12: Auto-fullscreen
        if idx == buttonIndex { toggleAutoFullscreen(); return }
    }

    var gamepadToolbarButtonCount: Int {
        // Indices: 0 stop, 1 pause, 2 restart, 3 save, 4 load, 5 slot,
        //          6 record, 7 cheats, [8 training], [9 guide], 10/11 fullscreen, 11/12 auto-fullscreen
        var count = 8
        if trainingModeViewModel.hasGameData { count += 1 }
        if gameGuideViewModel.hasGuideData { count += 1 }
        count += 2 // fullscreen + auto-fullscreen
        return count
    }

    /// Indices of toolbar buttons that are currently hidden (feature unsupported
    /// for this game, e.g. training/guide). Gamepad navigation skips these so the
    /// focus ring never lands on an invisible control.
    private func computeHiddenToolbarIndices() -> Set<Int> {
        var visible = Set([0, 1, 2, 3, 4, 5, 6, 7])
        if trainingModeViewModel.hasGameData { visible.insert(8) }
        if gameGuideViewModel.hasGuideData { visible.insert(9) }
        // Fullscreen / auto-fullscreen sit after the conditional buttons.
        let fullscreen = 8 + (trainingModeViewModel.hasGameData ? 1 : 0) + (gameGuideViewModel.hasGuideData ? 1 : 0)
        visible.insert(fullscreen)
        visible.insert(fullscreen + 1)
        return Set((0..<gamepadToolbarButtonCount).filter { !visible.contains($0) })
    }
}
