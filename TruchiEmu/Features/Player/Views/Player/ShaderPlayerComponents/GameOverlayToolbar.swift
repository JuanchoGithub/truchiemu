import SwiftUI

struct GameOverlayToolbar: View {
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject var windowController: StandaloneGameWindowController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var focusedIndex: Int? {
        windowController.isGamepadToolbarMode ? windowController.gamepadToolbarFocusedIndex : nil
    }

    var body: some View {
        ZStack {
            VStack {
                Spacer()
                toolbarContent
            }
        }
    }

    private var toolbarContent: some View {
        HStack(spacing: 12) {
            ToolbarButton(
                icon: "power",
                label: loc.localized("toolbar.stop"),
                danger: true
            ) {
                windowController.window?.close()
            }
            .gamepadToolbarFocus(index: 0, focusedIndex: focusedIndex)

            Divider()
                .frame(height: 30)
                .opacity(0.3)

            PauseResumeButton(runner: runner)
                .gamepadToolbarFocus(index: 1, focusedIndex: focusedIndex)

            RestartButton(runner: runner)
                .gamepadToolbarFocus(index: 2, focusedIndex: focusedIndex)

            Divider()
                .frame(height: 30)
                .opacity(0.3)

            ToolbarButton(
                icon: "square.and.arrow.down",
                label: loc.localized("toolbar.save"),
                disabled: windowController.saveStatesDisabled
            ) {
                Task { @MainActor in
                    _ = runner.saveState(slot: runner.currentSlot)
                }
            }
            .gamepadToolbarFocus(index: 3, focusedIndex: focusedIndex)

            ToolbarButton(
                icon: "square.and.arrow.down.on.square",
                label: loc.localized("toolbar.load"),
                disabled: windowController.saveStatesDisabled
            ) {
                Task { @MainActor in
                    _ = runner.loadState(slot: runner.currentSlot)
                }
            }
            .gamepadToolbarFocus(index: 4, focusedIndex: focusedIndex)

            SlotSelectorButton(
                currentSlot: runner.currentSlot,
                onSlotChange: { newSlot in
                    runner.currentSlot = newSlot
                },
                runner: runner,
                disabled: windowController.saveStatesDisabled
            )
            .gamepadToolbarFocus(index: 5, focusedIndex: focusedIndex)

            Divider()
                .frame(height: 30)
                .opacity(0.3)

            RecordStreamButton(runner: runner)
                .gamepadToolbarFocus(index: 6, focusedIndex: focusedIndex)

            Divider()
                .frame(height: 30)
                .opacity(0.3)

            ToolbarButton(
                icon: "wand.and.stars",
                label: loc.localized("toolbar.cheats")
            ) {
                windowController.showCheatManager()
            }
            .gamepadToolbarFocus(index: 7, focusedIndex: focusedIndex)

            FightTrainingToolbarButton(windowController: windowController)
                .gamepadToolbarFocus(index: trainingFocusIndex, focusedIndex: focusedIndex)

            GameGuideToolbarButton(windowController: windowController)
                .gamepadToolbarFocus(index: guideFocusIndex, focusedIndex: focusedIndex)

            FullscreenButton(windowController: windowController)
                .gamepadToolbarFocus(index: fullscreenFocusIndex, focusedIndex: focusedIndex)

            AutoFullscreenButton(windowController: windowController)
                .gamepadToolbarFocus(index: autoFullscreenFocusIndex, focusedIndex: focusedIndex)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled).opacity(0.85))
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
        )
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
        var idx = 9
        if windowController.trainingModeViewModel.hasGameData { idx += 1 }
        if windowController.gameGuideViewModel.hasGuideData { idx += 1 }
        return idx
    }

    private var autoFullscreenFocusIndex: Int {
        var idx = 10
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
