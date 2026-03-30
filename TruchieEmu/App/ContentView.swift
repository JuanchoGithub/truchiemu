import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var libraryAutomation: LibraryAutomationCoordinator
    @State private var selectedFilter: LibraryFilter = .recent
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
        VStack(spacing: 0) {
            NavigationSplitView {
                SystemSidebarView(selectedFilter: $selectedFilter)
            } detail: {
                LibraryGridView(
                    filter: selectedFilter,
                    selectedROM: $selectedROM,
                    searchText: $searchText
                )
                .navigationTitle(navigationTitle)
            }
            .navigationSplitViewStyle(.balanced)

            if libraryAutomation.isActive {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: libraryAutomation.progress)
                        .progressViewStyle(.linear)
                    Text(libraryAutomation.statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        }
        .sheet(item: $coreManager.pendingDownload) { pending in
            CoreDownloadSheet(pending: pending)
        }
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
