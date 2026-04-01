import SwiftUI

@main
struct TruchieEmuApp: App {
    @StateObject private var library = ROMLibrary()
    @StateObject private var coreManager = CoreManager()
    @StateObject private var controllerService = ControllerService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
                .environmentObject(LibraryAutomationCoordinator.shared)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Library") {
                Button("Rescan Library") {
                    if let url = library.romFolderURL {
                        Task { await library.rescanLibrary(at: url) }
                    }
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
                .disabled(library.romFolderURL == nil || library.isScanning)
            }
        }

        WindowGroup("Game Info", id: "game-info", for: ROM.ID.self) { $romID in
            if let romID = romID, let rom = library.roms.first(where: { $0.id == romID }) {
                GameDetailView(rom: rom)
                    .environmentObject(library)
                    .environmentObject(coreManager)
                    .environmentObject(controllerService)
                    .frame(minWidth: 500, minHeight: 600)
            } else {
                Text("Select a game from the library")
                    .foregroundColor(.secondary)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(library)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
        }
        .windowToolbarStyle(.unified)
    }
}
