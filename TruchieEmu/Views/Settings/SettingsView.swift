import SwiftUI
import Combine
import GameController

// MARK: - Main Settings View
struct SettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    
    private enum Page: Hashable { case general, library, cores, controllers, boxArt, display, cheats, bezels, retroAchievements, logging, about }
    @State private var selectedPage: Page = .general
    
    var body: some View {
        HStack(spacing: 0) {
            // Custom sidebar (no NavigationSplitView = no toggle button)
            List(selection: $selectedPage) {
                sidebarItem(icon: "photo.stack.fill", label: "Box Art", page: .boxArt)
                sidebarItem(icon: "wand.and.stars", label: "Cheats", page: .cheats)
                sidebarItem(icon: "gamecontroller.fill", label: "Controllers", page: .controllers)
                sidebarItem(icon: "cpu.fill", label: "Cores", page: .cores)
                sidebarItem(icon: "rectangle.on.rectangle", label: "Bezels", page: .bezels)
                sidebarItem(icon: "tv.fill", label: "Display", page: .display)
                sidebarItem(icon: "gearshape.fill", label: "General", page: .general)
                sidebarItem(icon: "book.fill", label: "Library", page: .library)
                sidebarItem(icon: "doc.text.fill", label: "Logging", page: .logging)
                sidebarItem(icon: "trophy.fill", label: "RetroAchievements", page: .retroAchievements)
                sidebarItem(icon: "info.circle.fill", label: "About", page: .about)
            }
            .listStyle(.sidebar)
            .frame(width: 180)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            // Content area
            Group {
                switch selectedPage {
                case .general:     GeneralSettingsView()
                case .library:     LibrarySettingsView()
                 case .cores:       CoreSettingsView()
                 case .controllers: ControllerSettingsView()
                 case .boxArt:      BoxArtSettingsView()
                case .display:     DisplaySettingsView()
                case .cheats:      CheatSettingsView()
                case .bezels:      BezelSettingsView()
                case .retroAchievements: RetroAchievementsSettingsView()
                case .logging:     LoggingSettingsView()
                case .about:       AboutView()
                }
             }
             .frame(minWidth: 550, minHeight: 420)
         }
         .frame(minWidth: 750, minHeight: 500)
         .sheet(item: $coreManager.pendingDownload) { pending in
             CoreDownloadSheet(pending: pending)
         }
     }
    
    private func sidebarItem(icon: String, label: String, page: Page) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .symbolVariant(.fill)
                .frame(width: 28, height: 20)
                .fixedSize()
            Text(label)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .tag(page)
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