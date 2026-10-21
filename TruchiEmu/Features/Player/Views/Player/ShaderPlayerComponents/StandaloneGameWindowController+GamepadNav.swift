import Cocoa
import SwiftUI

extension StandaloneGameWindowController {

    @MainActor
    func showGamepadToolbar() {
        if isGamepadToolbarMode && gameToolbarNavContext != nil {
            if !isToolbarVisible {
                showToolbar()
            }
            return
        }
        hideToolbarTimer?.invalidate()
        isGamepadToolbarMode = true
        GamepadNavigationManager.shared.isGamepadToolbarActive = true
        gamepadToolbarFocusedIndex = 0
        isStopConfirmArmed = false
        isSlotPickerShown = false
        isRecordStreamPickerShown = false
        isToolbarMoreShown = false

        let itemIDs = activeToolbarItemIDs
        let itemCount = itemIDs.count + (toolbarHasMore ? 1 : 0)
        guard itemCount > 0 else {
            isGamepadToolbarMode = false
            GamepadNavigationManager.shared.isGamepadToolbarActive = false
            return
        }

        let ctx = GamepadGameToolbarContext(itemCount: itemCount)
        ctx.ownedWindow = window
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
        hideToolbarTimer?.invalidate()
        hideToolbarTimer = nil
        if let r = runner {
            wasPausedBeforeGamepadToolbar = r.isPaused
            r.setPaused(true)
        }
        XPCBridgeAdapter.shared.clearAllJoypadInputs()
    }

    @MainActor
    func exitGamepadToolbarMode() {
        isGamepadToolbarMode = false
        gamepadToolbarFocusedIndex = nil
        GamepadNavigationManager.shared.isGamepadToolbarActive = false
        GamepadNavigationManager.shared.suppressGameInputsUntil = CACurrentMediaTime() + 0.25
        isStopConfirmArmed = false
        isToolbarMoreShown = false

        if let ctx = gameToolbarNavContext {
            GamepadNavContextStack.shared.remove(ctx)
        }
        gameToolbarNavContext = nil

        let nav = GamepadNavigationManager.shared
        nav.suppressLeftStickInToolbar = false
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
        guard isGamepadToolbarMode else { return }
        guard let idx = gamepadToolbarFocusedIndex else { return }
        let itemIDs = activeToolbarItemIDs

        if idx < itemIDs.count {
            performToolbarItem(itemIDs[idx], source: .gamepad)
            return
        }

        if idx == itemIDs.count && toolbarHasMore {
            isToolbarMoreShown = true
        }
    }

    @MainActor
    private var activeToolbarItemIDs: [GameToolbarItemID] {
        if !toolbarInlineItemIDs.isEmpty { return toolbarInlineItemIDs }
        return GameToolbarModel.availableItems(
            runner: runner,
            windowController: self,
            preferences: GameToolbarPreferences.shared
        ).map(\.id)
    }
}
