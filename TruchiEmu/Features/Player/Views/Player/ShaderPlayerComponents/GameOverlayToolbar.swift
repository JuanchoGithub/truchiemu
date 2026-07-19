import SwiftUI

struct GameOverlayToolbar: View {
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject var windowController: StandaloneGameWindowController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var hardcoreManager = HardcoreModeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var saveLoadDisabled: Bool {
        windowController.saveStatesDisabled
    }

    private var focusedIndex: Int? {
        windowController.isGamepadToolbarMode ? windowController.gamepadToolbarFocusedIndex : nil
    }

    var body: some View {
        ZStack {
            VStack {
                Spacer()
                toolbarContent
                    .environment(\.toolbarCompactMode, compactMode)
            }
        }
    }

    private var compactMode: ToolbarCompactMode {
        let w = windowController.windowContentSize.width
        if w >= 850 { return .full }
        if w >= 480 { return .compact }
        return .iconOnly
    }

    private var toolbarContent: some View {
        HStack(spacing: spacing) {
            ToolbarButton(
                icon: stopButtonIcon,
                label: stopButtonLabel,
                danger: true
            ) {
                windowController.window?.close()
            }
            .gamepadToolbarFocus(index: 0, focusedIndex: focusedIndex)

            toolbarDivider

            PauseResumeButton(runner: runner)
                .gamepadToolbarFocus(index: 1, focusedIndex: focusedIndex)

            RestartButton(runner: runner)
                .gamepadToolbarFocus(index: 2, focusedIndex: focusedIndex)

            toolbarDivider

            ToolbarButton(
                icon: "square.and.arrow.down",
                label: loc.localized("toolbar.save"),
                disabled: saveLoadDisabled
            ) {
                HardcoreModeManager.shared.attemptSaveState {
                    Task { @MainActor in
                        _ = runner.saveState(slot: runner.currentSlot)
                    }
                }
            }
            .gamepadToolbarFocus(index: 3, focusedIndex: focusedIndex)

            ToolbarButton(
                icon: "square.and.arrow.down.on.square",
                label: loc.localized("toolbar.load"),
                disabled: saveLoadDisabled
            ) {
                HardcoreModeManager.shared.attemptLoadState {
                    Task { @MainActor in
                        _ = runner.loadState(slot: runner.currentSlot)
                    }
                }
            }
            .gamepadToolbarFocus(index: 4, focusedIndex: focusedIndex)

            SlotSelectorButton(
                currentSlot: runner.currentSlot,
                isDropdownShown: $windowController.isSlotPickerShown,
                onSlotChange: { newSlot in
                    runner.currentSlot = newSlot
                    AppHaptics.selection()
                },
                runner: runner,
                disabled: saveLoadDisabled
            )
            .gamepadToolbarFocus(index: 5, focusedIndex: focusedIndex)

            toolbarDivider

            RecordStreamButton(
                runner: runner,
                isDropdownShown: $windowController.isRecordStreamPickerShown
            )
            .gamepadToolbarFocus(index: 6, focusedIndex: focusedIndex)

            toolbarDivider

            ToolbarButton(
                icon: "wand.and.stars",
                label: loc.localized("toolbar.cheats")
            ) {
                HardcoreModeManager.shared.attemptUseCheats {
                    windowController.showCheatManager()
                }
            }
            .gamepadToolbarFocus(index: 7, focusedIndex: focusedIndex)
            .popover(isPresented: $windowController.isCheatPickerShown, arrowEdge: .top) {
                if let rom = windowController.currentGameROM {
                    CheatPickerView(rom: rom, windowController: windowController)
                        .frame(width: 380, height: 440)
                }
            }

            FightTrainingToolbarButton(windowController: windowController)
                .gamepadToolbarFocus(index: trainingFocusIndex, focusedIndex: focusedIndex)

            GameGuideToolbarButton(windowController: windowController)
                .gamepadToolbarFocus(index: guideFocusIndex, focusedIndex: focusedIndex)

            FullscreenButton(windowController: windowController)
                .gamepadToolbarFocus(index: fullscreenFocusIndex, focusedIndex: focusedIndex)

            AutoFullscreenButton(windowController: windowController)
                .gamepadToolbarFocus(index: autoFullscreenFocusIndex, focusedIndex: focusedIndex)
        }
        .padding(.horizontal, containerPaddingH)
        .padding(.vertical, containerPaddingV)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled).opacity(0.85))
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
        )
    }

    private var stopButtonIcon: String {
        windowController.isGamepadToolbarMode && windowController.isStopConfirmArmed
            ? "checkmark.circle.fill"
            : "power"
    }

    private var stopButtonLabel: String {
        windowController.isGamepadToolbarMode && windowController.isStopConfirmArmed
            ? loc.localized("toolbar.confirmStop")
            : loc.localized("toolbar.stop")
    }

    @ViewBuilder
    private var toolbarDivider: some View {
        if compactMode != .iconOnly {
            Divider()
                .frame(height: 30)
                .opacity(0.3)
        }
    }

    private var spacing: CGFloat {
        switch compactMode {
        case .full: return 12
        case .compact: return 6
        case .iconOnly: return 2
        }
    }

    private var containerPaddingH: CGFloat {
        switch compactMode {
        case .full: return 16
        case .compact: return 8
        case .iconOnly: return 4
        }
    }

    private var containerPaddingV: CGFloat {
        switch compactMode {
        case .full: return 10
        case .compact: return 6
        case .iconOnly: return 4
        }
    }

    private var trainingFocusIndex: Int {
        windowController.trainingModeViewModel.hasGameData ? 8 : -1
    }

    private var guideFocusIndex: Int {
        var idx = 8
        if windowController.trainingModeViewModel.hasGameData { idx += 1 }
        return windowController.gameGuideViewModel.hasGuideData ? idx : -1
    }

    private var fullscreenFocusIndex: Int {
        var idx = 8
        if windowController.trainingModeViewModel.hasGameData { idx += 1 }
        if windowController.gameGuideViewModel.hasGuideData { idx += 1 }
        return idx
    }

    private var autoFullscreenFocusIndex: Int {
        var idx = 9
        if windowController.trainingModeViewModel.hasGameData { idx += 1 }
        if windowController.gameGuideViewModel.hasGuideData { idx += 1 }
        return idx
    }
}

extension View {
    func gamepadToolbarFocus(index: Int, focusedIndex: Int?) -> some View {
        self.overlay(alignment: .center) {
            if let focused = focusedIndex, focused == index {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.brandAccent, lineWidth: 2)
                    .padding(-3)
            }
        }
    }
}
