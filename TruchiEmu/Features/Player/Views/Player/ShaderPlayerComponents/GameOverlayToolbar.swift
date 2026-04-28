import SwiftUI

// MARK: - Game Overlay Toolbar View
struct GameOverlayToolbar: View {
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject var windowController: StandaloneGameWindowController
    @ObservedObject var captureManager = InputCaptureManager.shared

    var body: some View {
        ZStack {
            // Input capture indicator (top center)
            if captureManager.isCapturing {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.white.opacity(0.9))
                        Text("Input Captured")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.8))
                    )
                    .offset(y: -100) // Position above the toolbar

                    Spacer()
                }
            }

            // Main toolbar at bottom
            VStack {
                Spacer()
                toolbarContent
            }
        }
    }

    private var toolbarContent: some View {
        HStack(spacing: 12) {
            // Stop Button
            ToolbarButton(
                icon: "power",
                label: "Stop",
                danger: true
            ) {
                windowController.window?.close()
            }

            Divider()
                .frame(height: 30)
                .opacity(0.3)

            // Pause Button
            PauseResumeButton(runner: runner)

            // Reload Button (mouse-down trigger)
            ReloadButton(runner: runner)

            Divider()
                .frame(height: 30)
                .opacity(0.3)

            // Save Button
            ToolbarButton(
                icon: "square.and.arrow.down",
                label: "Save"
            ) {
                Task { @MainActor in
                    _ = runner.saveState(slot: runner.currentSlot)
                }
            }

            // Load Button
            ToolbarButton(
                icon: "square.and.arrow.down.on.square",
                label: "Load"
            ) {
                Task { @MainActor in
                    _ = runner.loadState(slot: runner.currentSlot)
                }
            }

            // Slot Selector
            SlotSelectorButton(
                currentSlot: runner.currentSlot,
                onSlotChange: { newSlot in
                    runner.currentSlot = newSlot
                }
            )

            Divider()
                .frame(height: 30)
                .opacity(0.3)

            // Cheats Button
            ToolbarButton(
                icon: "wand.and.stars",
                label: "Cheats"
            ) {
                windowController.showCheatManager()
            }

            // Fullscreen Button
            FullscreenButton(windowController: windowController)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.75))
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
        )
    }
}