import SwiftUI

struct GameOverlayToolbar: View {
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject var windowController: StandaloneGameWindowController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

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

            Divider()
                .frame(height: 30)
                .opacity(0.3)

            PauseResumeButton(runner: runner)

            RestartButton(runner: runner)

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

            ToolbarButton(
                icon: "square.and.arrow.down.on.square",
                label: loc.localized("toolbar.load"),
                disabled: windowController.saveStatesDisabled
            ) {
                Task { @MainActor in
                    _ = runner.loadState(slot: runner.currentSlot)
                }
            }

            SlotSelectorButton(
                currentSlot: runner.currentSlot,
                onSlotChange: { newSlot in
                    runner.currentSlot = newSlot
                },
                runner: runner,
                disabled: windowController.saveStatesDisabled
            )

            Divider()
                .frame(height: 30)
                .opacity(0.3)

        ToolbarButton(
            icon: "wand.and.stars",
            label: loc.localized("toolbar.cheats")
        ) {
            windowController.showCheatManager()
        }

FightTrainingToolbarButton(windowController: windowController)

GameGuideToolbarButton(windowController: windowController)

FullscreenButton(windowController: windowController)

            AutoFullscreenButton(windowController: windowController)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled).opacity(0.85))
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
        )
    }
}