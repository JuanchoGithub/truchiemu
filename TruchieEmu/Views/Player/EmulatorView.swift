import SwiftUI

// MARK: - EmulatorView (DEPRECATED)
/// This view is deprecated. All game launching is now handled by StandaloneGameWindowController.
/// This struct is kept for backward compatibility and will be removed in a future version.
/// 
/// Migration: Instead of presenting EmulatorView, use:
///   let runner = EmulatorRunner.forSystem(systemID)
///   let controller = StandaloneGameWindowController(runner: runner)
///   controller.showWindow(nil)
///   controller.launch(rom: rom, coreID: coreID)
struct EmulatorView: View {
    let rom: ROM
    let coreID: String
    @Environment(\.dismiss) private var dismiss
    @State private var windowController: StandaloneGameWindowController?

    init(rom: ROM, coreID: String) {
        self.rom = rom
        self.coreID = coreID
    }

    var body: some View {
        // This view auto-launches via StandaloneGameWindowController on appear
        Color.black
            .ignoresSafeArea()
            .onAppear {
                guard let sysID = rom.systemID else { return }
                let runner = EmulatorRunner.forSystem(sysID)
                let controller = StandaloneGameWindowController(runner: runner)
                self.windowController = controller
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                controller.launch(rom: rom, coreID: coreID)
            }
            .onDisappear {
                windowController?.window?.close()
            }
    }
}