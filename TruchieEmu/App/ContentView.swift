import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @State private var selectedFilter: LibraryFilter = .all
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
            SystemSidebarView(selectedFilter: $selectedFilter)
        } content: {
            LibraryGridView(
                filter: selectedFilter,
                selectedROM: $selectedROM,
                searchText: searchText
            )
            .searchable(text: $searchText, prompt: "Search games…")
            .navigationTitle(navigationTitle)
        } detail: {
            if let rom = selectedROM {
                GameDetailView(rom: rom)
            } else {
                EmptyDetailView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var navigationTitle: String {
        switch selectedFilter {
        case .all: return "All Games"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .system(let sys): return sys.name
        }
    }
}
