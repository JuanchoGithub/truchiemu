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
    @ObservedObject private var loc = LocalizationManager.shared
    
    enum Page: Hashable, Codable, RawRepresentable, Identifiable {
        
        var id: String { rawValue }
        case general, library, cores, controllers, boxArt, display, cheats, bezels, retroAchievements, genre, logging, about
        
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
            case .genre: return "genre"
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
            case "genre": self = .genre
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
            case .genre: return "tag.fill"
            case .logging: return "doc.text.fill"
            case .about: return "info.circle.fill"
            }
        }
        
        var label: String {
            switch self {
            case .general: return LocalizationManager.shared.localized("settings.general")
            case .library: return LocalizationManager.shared.localized("settings.library")
            case .cores: return LocalizationManager.shared.localized("settings.cores")
            case .controllers: return LocalizationManager.shared.localized("settings.controllers")
            case .boxArt: return LocalizationManager.shared.localized("settings.boxArt")
            case .display: return LocalizationManager.shared.localized("settings.display")
            case .cheats: return LocalizationManager.shared.localized("settings.cheats")
            case .bezels: return LocalizationManager.shared.localized("settings.bezels")
            case .retroAchievements: return LocalizationManager.shared.localized("settings.retroAchievements")
            case .genre: return LocalizationManager.shared.localized("settings.genre")
            case .logging: return LocalizationManager.shared.localized("settings.logging")
            case .about: return LocalizationManager.shared.localized("settings.about")
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
            case .genre:
                return "genre genres tag categories merge rename"
            case .logging:
                return "logging log debug console output"
            case .about:
                return "about info version truchie emu emulator"
            }
        }
    }
    
    private struct PageGroup: Identifiable {
        let id: String
        let label: String
        let pages: [Page]
    }
    
    static let allPages: [Page] = [
        .boxArt, .cheats, .controllers, .cores, .bezels, .display,
        .general, .genre, .library, .logging, .retroAchievements, .about
    ]
    
    private static let pageGroups: [PageGroup] = [
        PageGroup(id: "general", label: LocalizationManager.shared.localized("settingsGroup.general"), pages: [.general, .library]),
        PageGroup(id: "systems", label: LocalizationManager.shared.localized("settingsGroup.systems"), pages: [.cores, .controllers]),
        PageGroup(id: "visuals", label: LocalizationManager.shared.localized("settingsGroup.visuals"), pages: [.boxArt, .display, .bezels, .cheats]),
        PageGroup(id: "advanced", label: LocalizationManager.shared.localized("settingsGroup.advanced"), pages: [.retroAchievements, .genre, .logging, .about]),
    ]
    
    @State private var selectedPage: Page = .general
    @State private var searchText: String = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    let system: SystemInfo?
    
    // Sync state with AppSettings when view appears
    private func syncWithStorage() {
        if let page = Page(rawValue: AppSettings.getString("settings_selectedTab", defaultValue: "general") ?? "general") {
            selectedPage = page
        }
    }

    // Update storage when selection changes
    private func updateStorage() {
        AppSettings.set("settings_selectedTab", value: selectedPage.rawValue)
    }
    
    init(system: SystemInfo? = nil, initialPage: SettingsView.Page? = nil) {
        self.system = system
        
        if let initial = initialPage {
            _selectedPage = State(initialValue: initial)
        }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedPage) {
                if searchText.isEmpty {
                    ForEach(Self.pageGroups) { group in
                        Section(header: Text(group.label.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .padding(.top, 8)
                        ) {
                            ForEach(group.pages) { page in
                                sidebarItem(for: page)
                                    .tag(page)
                            }
                        }
                    }
                } else {
                    ForEach(filteredPages) { page in
                        sidebarItem(for: page)
                            .tag(page)
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: loc.localized("settings.search"))
            .navigationTitle(loc.localized("settings.title"))
            .toolbar(removing: .sidebarToggle)
            .frame(minWidth: 200)
        } detail: {
            // Content area
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .environment(SystemDatabaseWrapper.shared)
        .frame(minWidth: 750, minHeight: 500)
        .onAppear {
            if system != nil {
                // Only sync if no initialPage was provided
                if selectedPage == .general && AppSettings.getString("settings_selectedTab", defaultValue: "general") == "general" {
                    // First appearance, potentially show initialPage from init
                }
            } else {
                syncWithStorage()
            }
        }
        .onChange(of: selectedPage) { _, newValue in
            if coreManager.isDownloadingCore && newValue != .cores {
                selectedPage = .cores
                return
            }
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
            .symbolVariant(selectedPage == page ? .fill : .none)
            .frame(width: 20)
            .fixedSize()
            .foregroundColor(selectedPage == page ? AppColors.brandAccent : AppColors.textSecondary(colorScheme))
            Text(page.label)
            .font(AppTypography.callout)

            if coreManager.isDownloadingCore && page == .cores {
                Spacer()
                ProgressView()
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
    
    // MARK: - Detail Content
    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppColors.brandAccent.opacity(0.3))
                .frame(height: 1)
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
            case .genre:       GenreSettingsView(searchText: $searchText)
            case .logging:     LoggingSettingsView(searchText: $searchText)
            case .about:       AboutView()
        }
        }
        .frame(minWidth: 550, minHeight: 420)

        if coreManager.isDownloadingCore {
            CoreDownloadStatusBar(coreManager: coreManager)
        }
    }
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
