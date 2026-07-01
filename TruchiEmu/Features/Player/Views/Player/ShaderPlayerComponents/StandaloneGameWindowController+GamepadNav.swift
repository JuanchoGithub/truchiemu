import Cocoa
import SwiftUI

extension StandaloneGameWindowController {

    @MainActor
    func showGamepadToolbar() {
        hideToolbarTimer?.invalidate()
        isGamepadToolbarMode = true
        gamepadToolbarFocusedIndex = 0

        let ctx = GamepadGameToolbarContext(itemCount: gamepadToolbarButtonCount)
        ctx.ownedWindow = window
        ctx.onSelect = { [weak self] _ in self?.gamepadToolbarActivateFocusedButton() }
        ctx.onDismiss = { [weak self] in self?.exitGamepadToolbarMode() }
        ctx.onNavigate = { [weak self] in
            guard let self, let ctx = self.gameToolbarNavContext else { return }
            self.gamepadToolbarFocusedIndex = ctx.focusIndex
        }
        gameToolbarNavContext = ctx
        GamepadNavContextStack.shared.push(ctx)

        let nav = GamepadNavigationManager.shared
        let sysID = runner?.systemID.lowercased()
        nav.suppressLeftStickInToolbar = (sysID == "dos" || sysID == "scummvm")
        if !isToolbarVisible {
            showToolbar()
        }
        if let r = runner, !r.isPaused {
            r.isPaused = true
            XPCBridgeAdapter.shared.setPaused(true)
        }
    }

    @MainActor
    func exitGamepadToolbarMode() {
        isGamepadToolbarMode = false
        gamepadToolbarFocusedIndex = nil

        if let ctx = gameToolbarNavContext {
            GamepadNavContextStack.shared.remove(ctx)
        }
        gameToolbarNavContext = nil

        let nav = GamepadNavigationManager.shared
        nav.suppressLeftStickInToolbar = false
        if let r = runner {
            r.isPaused = false
        }
        XPCBridgeAdapter.shared.setPaused(false)
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
        guard let idx = gamepadToolbarFocusedIndex, let r = runner else { return }
        var buttonIndex = 0
        if idx == buttonIndex { window?.close(); return }
        buttonIndex += 1
        if idx == buttonIndex { r.togglePause(); return }
        buttonIndex += 1
        if idx == buttonIndex { r.reloadGame(); return }
        buttonIndex += 1
        if idx == buttonIndex {
            if !saveStatesDisabled {
                HardcoreModeManager.shared.attemptSaveState { [weak self] in
                    guard let self else { return }
                    Task { @MainActor in _ = r.saveState(slot: r.currentSlot) }
                }
            }
            return
        }
        buttonIndex += 1
        if idx == buttonIndex {
            if !saveStatesDisabled {
                HardcoreModeManager.shared.attemptLoadState { [weak self] in
                    guard let self else { return }
                    Task { @MainActor in _ = r.loadState(slot: r.currentSlot) }
                }
            }
            return
        }
        buttonIndex += 1
        if idx == buttonIndex { return }
        buttonIndex += 1
        if idx == buttonIndex { showCheatManager(); return }
        if trainingModeViewModel.hasGameData {
            buttonIndex += 1
            if idx == buttonIndex { toggleTrainingModeOverlay(); return }
        }
        if gameGuideViewModel.hasGuideData {
            buttonIndex += 1
            if idx == buttonIndex { toggleGuideSidebar(); return }
        }
        buttonIndex += 1
        if idx == buttonIndex { toggleFullscreen(); return }
        buttonIndex += 1
        if idx == buttonIndex { toggleAutoFullscreen(); return }
    }

    var gamepadToolbarButtonCount: Int {
        var count = 9
        if trainingModeViewModel.hasGameData { count += 1 }
        if gameGuideViewModel.hasGuideData { count += 1 }
        return count
    }
}
