import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var categoryManager: CategoryManager
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var libraryAutomation: LibraryAutomationCoordinator
    @EnvironmentObject var controllerService: ControllerService
    @StateObject private var metadataSync = MetadataSyncCoordinator.shared
    @ObservedObject var wizard = SetupWizardState.shared
    
    @State private var selectedFilter: LibraryFilter = .recent
    @State private var selectedROM: ROM? = nil
    @State private var showOnboarding = false
    @State private var searchText = ""
    @State private var showCreateCategorySheet = false
    @State private var editingCategory: GameCategory? = nil

    var body: some View {
        Group {
            if !library.hasCompletedOnboarding {
                // Show the setup wizard for first-time users
                SetupWizardView(wizard: wizard)
                    .environmentObject(library)
                    .environmentObject(categoryManager)
                    .environmentObject(coreManager)
                    .environmentObject(controllerService)
            } else if library.roms.isEmpty {
                // Wizard was completed but no games found - guide user to add games
                SetupWizardView(wizard: wizard)
                    .environmentObject(library)
                    .environmentObject(categoryManager)
                    .environmentObject(coreManager)
                    .environmentObject(controllerService)
                    .onAppear {
                        // Skip the welcome step since they've already been through the wizard;
                        // send them straight to the getStarted step.
                        if wizard.currentStep == .getStarted {
                            // Already at the right step, just add any folders
                        }
                    }
            } else {
                mainInterface
            }
        }
    }

    private var mainInterface: some View {
        ZStack {
            VStack(spacing: 0) {
                NavigationSplitView {
                    SystemSidebarView(
                        selectedFilter: $selectedFilter,
                        showCreateCategorySheet: $showCreateCategorySheet,
                        editingCategory: $editingCategory
                    )
                } detail: {
                    LibraryGridView(
                        showCreateCategorySheet: $showCreateCategorySheet,
                        filter: selectedFilter,
                        selectedROM: $selectedROM,
                        searchText: $searchText
                    )
                    .navigationTitle(navigationTitle)
                }
                .navigationSplitViewStyle(.balanced)
                .sheet(isPresented: $showCreateCategorySheet) {
                    CreateCategorySheet()
                }
                .sheet(item: $editingCategory) { category in
                    EditCategorySheet(category: category)
                }

                // Status bar for library automation or metadata sync
                if let activeStatus = activeBackgroundTask {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: activeStatus.progress)
                            .progressViewStyle(.linear)
                        Text(activeStatus.statusLine)
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
            
            // Confetti overlay for celebration moments
            ConfettiOverlay()
        }
        .sheet(item: $coreManager.pendingDownload) { pending in
            CoreDownloadSheet(pending: pending)
        }
        .onAppear {
            // After wizard completion, start on All Games until at least one game has been played.
            let hasPlayedGames = library.roms.contains { $0.lastPlayed != nil || $0.timesPlayed > 0 }
            if !hasPlayedGames {
                selectedFilter = .all
            }
        }
    }

    /// Shows whichever background task is currently active (library automation takes precedence).
    private var activeBackgroundTask: (progress: Double, statusLine: String)? {
        if libraryAutomation.isActive {
            return (libraryAutomation.progress, libraryAutomation.statusLine)
        }
        if metadataSync.isActive {
            return (metadataSync.progress, metadataSync.statusLine)
        }
        return nil
    }

    private var navigationTitle: String {
        switch selectedFilter {
        case .all: return "All Games"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .system(let sys): return sys.name
        case .category(let id):
            if let category = categoryManager.categories.first(where: { $0.id == id }) {
                return category.name
            }
            return "Category"
        case .hidden: return "Hidden Games"
        }
    }
}
