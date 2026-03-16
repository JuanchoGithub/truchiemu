import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @State private var selectedSystem: SystemInfo? = nil
    @State private var selectedROM: ROM? = nil
    @State private var showOnboarding = false
    @State private var searchText = ""

    var body: some View {
        Group {
            if library.hasCompletedOnboarding {
                mainInterface
            } else {
                OnboardingView()
            }
        }
        .onAppear {
            if !library.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
    }

    private var mainInterface: some View {
        NavigationSplitView {
            SystemSidebarView(selectedSystem: $selectedSystem)
        } content: {
            LibraryGridView(
                system: selectedSystem,
                selectedROM: $selectedROM,
                searchText: searchText
            )
            .searchable(text: $searchText, prompt: "Search games…")
            .navigationTitle(selectedSystem?.name ?? "All Games")
        } detail: {
            if let rom = selectedROM {
                GameDetailView(rom: rom)
            } else {
                EmptyDetailView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
