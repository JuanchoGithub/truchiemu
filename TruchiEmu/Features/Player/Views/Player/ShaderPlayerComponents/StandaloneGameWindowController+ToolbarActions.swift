import Cocoa
import SwiftUI

enum GameToolbarActionSource {
    case mouse
    case gamepad
}

extension StandaloneGameWindowController {

    @MainActor
    func performToolbarItem(_ id: GameToolbarItemID, source: GameToolbarActionSource = .mouse) {
        guard isToolbarItemEnabled(id) else { return }
        switch id {
        case .stop:
            if source == .gamepad && !isStopConfirmArmed {
                isStopConfirmArmed = true
                return
            }
            window?.close()
        case .pauseResume:
            runner?.togglePause()
            if source == .gamepad {
                wasPausedBeforeGamepadToolbar = false
                exitGamepadToolbarMode()
            }
        case .restart:
            runner?.reloadGame()
            if source == .gamepad {
                exitGamepadToolbarMode()
            }
        case .save:
            guard !saveStatesDisabled else { return }
            HardcoreModeManager.shared.attemptSaveState { [weak self] in
                Task { @MainActor in
                    guard let self, let runner = self.runner else { return }
                    _ = runner.saveState(slot: runner.currentSlot)
                }
            }
        case .load:
            guard !saveStatesDisabled else { return }
            cancelToolbarAutoHide()
            isSlotPickerShown = true
        case .undoLoad:
            HardcoreModeManager.shared.attemptLoadState { [weak self] in
                Task { @MainActor in _ = self?.runner?.undoLoadState() }
            }
        case .record:
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
        case .rewind:
            HardcoreModeManager.shared.attemptRewind { [weak self] in
                guard let self else { return }
                if source == .gamepad {
                    self.exitGamepadToolbarMode()
                }
                self.runner?.toggleTimeMachineMode()
            }
        case .fastForward:
            HardcoreModeManager.shared.attemptFastForward { [weak self] in
                self?.runner?.toggleFastForward()
            }
        case .slowMotion:
            HardcoreModeManager.shared.attemptSlowMotion { [weak self] in
                self?.runner?.toggleSlowMotion()
            }
        case .cheats:
            showCheatManager(gamepad: source == .gamepad)
        case .training:
            toggleTrainingModeOverlay()
        case .guide:
            toggleGuideSidebar()
        case .shader:
            openShaderEditorForRunningGame()
        case .bezel:
            presentBezelSelectorForRunningGame()
        case .fullscreen:
            toggleFullscreen()
        }
    }

    @MainActor
    func isToolbarItemEnabled(_ id: GameToolbarItemID) -> Bool {
        switch id {
        case .save, .load, .undoLoad:
            return !saveStatesDisabled
        default:
            return true
        }
    }

    @MainActor
    func isToolbarItemActive(_ id: GameToolbarItemID) -> Bool {
        switch id {
        case .pauseResume:
            return runner?.isPaused == true
        case .record:
            return StreamRecordingService.shared.isUserRecording
        case .rewind:
            return runner?.isRewinding == true
        case .fastForward:
            return (runner?.speedMultiplier ?? 1) > 1
        case .slowMotion:
            return (runner?.speedMultiplier ?? 1) < 1
        case .training:
            return TrainingModeManager.shared.isMenuVisible
        case .guide:
            return gameGuideViewModel.isSidebarVisible
        case .shader:
            return isShaderEditorShown
        case .bezel:
            return bezelImage != nil
        case .fullscreen:
            return isFullscreen
        default:
            return false
        }
    }

    @MainActor
    func openShaderEditorForRunningGame() {
        guard let rom = currentGameROM else { return }
        LiveShaderEditManager.shared.presentEditor(on: self, rom: rom)
    }

    @MainActor
    func presentBezelSelectorForRunningGame() {
        guard let rom = currentGameROM, let library else { return }
        let systemID = rom.systemID ?? "default"
        let selector = BezelSelectorWindowController(
            rom: rom,
            systemID: systemID,
            library: library,
            onBezelSelected: { [weak self] filename in
                guard let self, var updated = self.currentGameROM else { return }
                updated.settings.bezelFileName = filename
                self.currentGameROM = updated
                Task { @MainActor in
                    await self.loadBezelForGame(systemID: systemID, rom: updated)
                }
            }
        )
        bezelSelectorController = selector
        selector.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        selector.window?.makeKeyAndOrderFront(nil)
    }
}
