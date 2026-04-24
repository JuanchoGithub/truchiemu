import SwiftUI
import Combine
import GameController
import Foundation

// MARK: - Main Settings View
struct SettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.colorScheme) private var colorScheme
    
    enum Page: Hashable, Codable, RawRepresentable, Identifiable {
        
        var id: String { rawValue }
        case general, library, cores, controllers, boxArt, display, cheats, bezels, retroAchievements, logging, about
        
        var rawValue: String {
            switch self {
            case .general: return "general"
            case .library: return "library"
            case .cores: return "cores"
            case .controllers: return "controllers"
            case .boxArt: return "boxArt"
            case .display: return "display"
            case .cheats: return "cheats"
            case .bezels: return "bezels"
            case .retroAchievements: return "retroAchievements"
            case .logging: return "logging"
            case .about: return "about"
            }
        }
        
        init?(rawValue: String) {
            switch rawValue {
            case "general": self = .general
            case "library": self = .library
            case "cores": self = .cores
            case "controllers": self = .controllers
            case "boxArt": self = .boxArt
            case "display": self = .display
            case "cheats": self = .cheats
            case "bezels": self = .bezels
            case "retroAchievements": self = .retroAchievements
            case "logging": self = .logging
            case "about": self = .about
            default: return nil
            }
        }
        
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .library: return "book.fill"
            case .cores: return "cpu.fill"
            case .controllers: return "gamecontroller.fill"
            case .boxArt: return "photo.stack.fill"
            case .display: return "tv.fill"
            case .cheats: return "wand.and.stars"
            case .bezels: return "rectangle.on.rectangle"
            case .retroAchievements: return "trophy.fill"
            case .logging: return "doc.text.fill"
            case .about: return "info.circle.fill"
            }
        }
        
        var label: String {
            switch self {
            case .general: return "General"
            case .library: return "Library"
            case .cores: return "Cores"
            case .controllers: return "Controllers"
            case .boxArt: return "Box Art"
            case .display: return "Display"
            case .cheats: return "Cheats"
            case .bezels: return "Bezels"
            case .retroAchievements: return "Retro Achievements"
            case .logging: return "Logging"
            case .about: return "About"
            }
        }
        
        var searchKeywords: String {
            switch self {
            case .general:
                return "general app application version build notifications settings preferences"
            case .library:
                return "library folders roms games scan rescan hidden bios"
            case .cores:
                return "cores emulator download update system"
            case .controllers:
                return "controllers gamepad keyboard mapping player buttons input"
            case .boxArt:
                return "box art thumbnail images pictures cover"
            case .display:
                return "display screen shader preset bezel"
            case .cheats:
                return "cheats codes cheat code action replay"
            case .bezels:
                return "bezel frame overlay monitor"
            case .retroAchievements:
                return "retro achievements achievements hardcore"
            case .logging:
                return "logging log debug console output"
            case .about:
                return "about info version truchie emu emulator"
            }
        }
    }
    
    static let allPages: [Page] = [
        .boxArt, .cheats, .controllers, .cores, .bezels, .display,
        .general, .library, .logging, .retroAchievements, .about
    ]
    
    // Use @AppStorage so it persists and can be set before openSettings() is called
    @AppStorage("settings_selectedTab") private var selectedPageRaw: String = "general"
    
    @State private var selectedPage: Page = .general
    @State private var searchText: String = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    let system: SystemInfo?
    
    // Sync state with AppStorage when view appears
    private func syncWithStorage() {
        if let page = Page(rawValue: selectedPageRaw) {
            selectedPage = page
        }
    }
    
    // Update storage when selection changes
    private func updateStorage() {
        selectedPageRaw = selectedPage.rawValue
    }
    
    init(system: SystemInfo? = nil, initialPage: SettingsView.Page? = nil) {
        self.system = system
        
        if let initial = initialPage {
            _selectedPage = State(initialValue: initial)
        }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - native macOS sidebar styling
            List(selection: $selectedPage) {
                ForEach(filteredPages) { page in
                    sidebarItem(for: page)
                        .tag(page)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
            .navigationTitle("Settings")
            .toolbar(removing: .sidebarToggle)
            .frame(minWidth: 200)
        } detail: {
            // Content area
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 750, minHeight: 500)
        .onAppear {
            if system != nil {
                // Only sync if no initialPage was provided
                if selectedPage == .general && selectedPageRaw == "general" {
                    // First appearance, potentially show initialPage from init
                }
            } else {
                syncWithStorage()
            }
        }
        .onChange(of: selectedPage) { _, newValue in
            updateStorage()
        }
        .sheet(item: $coreManager.pendingDownload) { pending in
            CoreDownloadSheet(pending: pending)
        }
    }
    
    private var filteredPages: [Page] {
        if searchText.isEmpty {
            return Self.allPages
        }
        return Self.allPages.filter { page in
            page.label.localizedLowercase.fuzzyMatch(searchText) ||
            page.searchKeywords.localizedLowercase.fuzzyMatch(searchText)
        }
    }
    
    private func sidebarItem(for page: Page) -> some View {
        HStack(spacing: 8) {
            Image(systemName: page.icon)
                .font(.system(size: 14, weight: .medium))
                .symbolVariant(.fill)
                .frame(width: 20)
                .fixedSize()
            Text(page.label)
                .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
    
    // MARK: - Detail Content
    @ViewBuilder
    private var detailContent: some View {
        Group {
            switch selectedPage {
            case .general:     GeneralSettingsView(searchText: $searchText)
            case .library:     LibrarySettingsView(searchText: $searchText)
            case .cores:       CoreSettingsView(searchText: $searchText)
            case .controllers: ControllerSettingsView(systemID: system?.id, searchText: $searchText)
            case .boxArt:      BoxArtSettingsView(searchText: $searchText)
            case .display:     DisplaySettingsView(searchText: $searchText)
            case .cheats:      CheatSettingsView(system: system, searchText: $searchText)
            case .bezels:     BezelSettingsView(system: system, searchText: $searchText)
            case .retroAchievements: RetroAchievementsSettingsView(searchText: $searchText, system: system)
            case .logging:     LoggingSettingsView(searchText: $searchText)
            case .about:       AboutView()
            }
        }
        .frame(minWidth: 550, minHeight: 420)
    }
}

// MARK: - Fuzzy Search Helper
extension String {
    func fuzzyMatch(_ query: String) -> Bool {
        if query.isEmpty { return true }
        let lowerString = self.localizedLowercase
        let lowerQuery = query.localizedLowercase
        
        var stringIndex = lowerString.startIndex
        var queryIndex = lowerQuery.startIndex
        
        while stringIndex < lowerString.endIndex && queryIndex < lowerQuery.endIndex {
            if lowerString[stringIndex] == lowerQuery[queryIndex] {
                queryIndex = lowerQuery.index(after: queryIndex)
            }
            stringIndex = lowerString.index(after: stringIndex)
        }
        
        // If we reached the end of the query, it means all characters were found in order
        return queryIndex == lowerQuery.endIndex
    }
}
