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
    @State private var hasPendingThemeChanges: Bool = false
    @State private var revertRequest: Int = 0
    @State private var applyRequest: Int = 0
    @State private var showThemeChangeConfirmation: Bool = false
    @State private var pendingPageChange: Page?
    @State private var activePendingTheme: AccentColorTheme = .samus
    @State private var activePendingCustomColor: Color = Color(.sRGB, red: 0.031, green: 0.569, blue: 0.698)
    @State private var activePendingToolbarAccent: Bool = true
    @State private var activePendingTintedSurfaces: Bool = true
    @State private var activePendingAppearanceMode: AppearanceMode = .automatic
    
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
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if searchText.isEmpty {
                        ForEach(Self.pageGroups) { group in
                            Text(group.label.uppercased())
                                .font(AppTypography.sectionHeader)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            ForEach(group.pages) { page in
                                sidebarItem(for: page)
                            }
                        }
                    } else {
                        ForEach(filteredPages) { page in
                            sidebarItem(for: page)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
            .searchable(text: $searchText, placement: .sidebar, prompt: loc.localized("settings.search"))
            .navigationTitle(loc.localized("settings.title"))
            .toolbar(removing: .sidebarToggle)
            .frame(minWidth: 200)
        } detail: {
            detailContent
                .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        }
.navigationSplitViewStyle(.balanced)
.toolbarBackground(
    AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled),
    for: .windowToolbar
)
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
            updateStorage()
        }
        .confirmationDialog(
            loc.localized("settings.theme.applyChangesTitle"),
            isPresented: $showThemeChangeConfirmation,
            titleVisibility: .visible
        ) {
            Button(loc.localized("settings.theme.applyAndRestart")) {
                applyRequest += 1
            }
            Button(loc.localized("settings.theme.discardChanges"), role: .destructive) {
                revertRequest += 1
                if let target = pendingPageChange {
                    selectedPage = target
                    updateStorage()
                }
                pendingPageChange = nil
            }
            Button(loc.localized("settings.theme.cancelNavigation"), role: .cancel) {
                pendingPageChange = nil
            }
        } message: {
            Text(loc.localized("settings.theme.applyChangesMessage"))
        }
        .sheet(item: $coreManager.pendingDownload) { pending in
            CoreDownloadSheet(pending: pending)
        }
        .background(WindowCloseInterceptor(
            hasPendingChanges: hasPendingThemeChanges,
            onRevert: { revertRequest += 1 },
        pendingTheme: activePendingTheme,
        pendingCustomColor: activePendingCustomColor,
        pendingToolbarAccent: activePendingToolbarAccent,
        pendingTintedSurfaces: activePendingTintedSurfaces,
        pendingAppearanceMode: activePendingAppearanceMode
        ))
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
        let isSelected = selectedPage == page

        return Button {
            if coreManager.isDownloadingCore && page != .cores {
                selectedPage = .cores
                return
            }
            if page != .general && hasPendingThemeChanges {
                pendingPageChange = page
                showThemeChangeConfirmation = true
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedPage = page
            }
            updateStorage()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: page.icon)
                    .font(.system(size: 14, weight: .medium))
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(width: 20)
                    .fixedSize()
                    .foregroundColor(isSelected ? AppColors.brandAccent : AppColors.textSecondary(colorScheme))
                Text(page.label)
                    .font(AppTypography.callout)
                    .foregroundColor(isSelected ? AppColors.textPrimary(colorScheme) : AppColors.textSecondary(colorScheme))
                    .fontWeight(isSelected ? .medium : .regular)

                if coreManager.isDownloadingCore && page == .cores {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? AppColors.accentBackground(colorScheme) : .clear)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.brandAccentSecondary)
                        .frame(width: 3, height: 20)
                        .padding(.leading, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            case .general: GeneralSettingsView(
                searchText: $searchText,
                hasPendingChanges: $hasPendingThemeChanges,
                revertRequest: $revertRequest,
                applyRequest: $applyRequest,
                activePendingTheme: $activePendingTheme,
                activePendingCustomColor: $activePendingCustomColor,
                activePendingToolbarAccent: $activePendingToolbarAccent,
                activePendingTintedSurfaces: $activePendingTintedSurfaces,
                activePendingAppearanceMode: $activePendingAppearanceMode
            )
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

// MARK: - Window Close Interceptor
private struct WindowCloseInterceptor: NSViewRepresentable {
    let hasPendingChanges: Bool
    let onRevert: () -> Void
    let pendingTheme: AccentColorTheme
    let pendingCustomColor: Color
    let pendingToolbarAccent: Bool
    let pendingTintedSurfaces: Bool
    let pendingAppearanceMode: AppearanceMode

    func makeNSView(context: Context) -> NSView {
        let view = CloseInterceptorView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.delegate = context.coordinator
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hasPendingChanges = hasPendingChanges
        context.coordinator.onRevert = onRevert
        context.coordinator.pendingTheme = pendingTheme
        context.coordinator.pendingCustomColor = pendingCustomColor
        context.coordinator.pendingToolbarAccent = pendingToolbarAccent
        context.coordinator.pendingTintedSurfaces = pendingTintedSurfaces
        context.coordinator.pendingAppearanceMode = pendingAppearanceMode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            hasPendingChanges: hasPendingChanges,
            onRevert: onRevert,
            pendingTheme: pendingTheme,
            pendingCustomColor: pendingCustomColor,
            pendingToolbarAccent: pendingToolbarAccent,
            pendingTintedSurfaces: pendingTintedSurfaces,
            pendingAppearanceMode: pendingAppearanceMode
        )
    }

    class Coordinator: NSObject, NSWindowDelegate {
        var hasPendingChanges: Bool
        var onRevert: () -> Void
        var pendingTheme: AccentColorTheme
        var pendingCustomColor: Color
        var pendingToolbarAccent: Bool
        var pendingTintedSurfaces: Bool
        var pendingAppearanceMode: AppearanceMode

        init(hasPendingChanges: Bool, onRevert: @escaping () -> Void, pendingTheme: AccentColorTheme, pendingCustomColor: Color, pendingToolbarAccent: Bool, pendingTintedSurfaces: Bool, pendingAppearanceMode: AppearanceMode) {
            self.hasPendingChanges = hasPendingChanges
            self.onRevert = onRevert
            self.pendingTheme = pendingTheme
            self.pendingCustomColor = pendingCustomColor
            self.pendingToolbarAccent = pendingToolbarAccent
            self.pendingTintedSurfaces = pendingTintedSurfaces
            self.pendingAppearanceMode = pendingAppearanceMode
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard hasPendingChanges else { return true }
            let alert = NSAlert()
            alert.messageText = LocalizationManager.shared.localized("settings.theme.applyChangesTitle")
            alert.informativeText = LocalizationManager.shared.localized("settings.theme.applyChangesMessage")
            alert.addButton(withTitle: LocalizationManager.shared.localized("settings.theme.applyAndRestart"))
            alert.addButton(withTitle: LocalizationManager.shared.localized("settings.theme.discardChanges"))
            alert.addButton(withTitle: LocalizationManager.shared.localized("settings.theme.cancelNavigation"))
            alert.alertStyle = .warning
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                let tm = ThemeManager.shared
                tm.applyTheme(pendingTheme, customColor: pendingTheme == .custom ? pendingCustomColor : nil)
                tm.setToolbarAccent(pendingToolbarAccent)
                tm.setTintedSurfaces(pendingTintedSurfaces)
                tm.applyAppearanceMode(pendingAppearanceMode)
                ThemeManager.relaunchApp()
                return false
            case .alertSecondButtonReturn:
                onRevert()
                return true
            default:
                return false
            }
        }
    }
}

private class CloseInterceptorView: NSView {}
