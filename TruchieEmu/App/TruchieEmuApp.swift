import SwiftUI

@main
struct TruchieEmuApp: App {
    @StateObject private var library = ROMLibrary()
    @StateObject private var coreManager = CoreManager()
    @StateObject private var controllerService = ControllerService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
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

        Settings {
            SettingsView()
                .environmentObject(library)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
        }
    }
}
