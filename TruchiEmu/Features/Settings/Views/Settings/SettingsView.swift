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
        case general, saves, library, cores, controllers, analogMouse, boxArt, display, cheats, bezels, retroAchievements, genre, logging, moveList, hotkeys, help, about
        
        var rawValue: String {
            switch self {
            case .general: return "general"
            case .saves: return "saves"
            case .library: return "library"
            case .cores: return "cores"
        case .controllers: return "controllers"
        case .analogMouse: return "analogMouse"
        case .boxArt: return "boxArt"
            case .display: return "display"
            case .cheats: return "cheats"
            case .bezels: return "bezels"
            case .retroAchievements: return "retroAchievements"
            case .genre: return "genre"
            case .logging: return "logging"
        case .moveList: return "moveList"
        case .hotkeys: return "hotkeys"
        case .help: return "help"
    case .about: return "about"
            }
        }
        
        init?(rawValue: String) {
            switch rawValue {
            case "general": self = .general
            case "saves": self = .saves
            case "library": self = .library
            case "cores": self = .cores
        case "controllers": self = .controllers
        case "analogMouse": self = .analogMouse
        case "boxArt": self = .boxArt
            case "display": self = .display
            case "cheats": self = .cheats
            case "bezels": self = .bezels
            case "retroAchievements": self = .retroAchievements
            case "genre": self = .genre
            case "logging": self = .logging
        case "moveList": self = .moveList
        case "hotkeys": self = .hotkeys
        case "help": self = .help
    case "about": self = .about
            default: return nil
            }
        }
        
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .saves: return "externaldrive.fill"
            case .library: return "book.fill"
            case .cores: return "cpu.fill"
        case .controllers: return "gamecontroller.fill"
        case .analogMouse: return "computermouse.fill"
        case .boxArt: return "photo.stack.fill"
            case .display: return "tv.fill"
            case .cheats: return "wand.and.stars"
            case .bezels: return "rectangle.on.rectangle"
            case .retroAchievements: return "trophy.fill"
            case .genre: return "tag.fill"
            case .logging: return "doc.text.fill"
        case .moveList: return "figure.martial.arts"
        case .hotkeys: return "keyboard"
        case .help: return "questionmark.circle.fill"
    case .about: return "info.circle.fill"
            }
        }
        
        var label: String {
            switch self {
            case .general: return LocalizationManager.shared.localized("settings.general")
            case .saves: return LocalizationManager.shared.localized("settings.saves")
            case .library: return LocalizationManager.shared.localized("settings.library")
            case .cores: return LocalizationManager.shared.localized("settings.cores")
        case .controllers: return LocalizationManager.shared.localized("settings.controllers")
        case .analogMouse: return LocalizationManager.shared.localized("settings.analogMouse")
        case .boxArt: return LocalizationManager.shared.localized("settings.boxArt")
            case .display: return LocalizationManager.shared.localized("settings.display")
            case .cheats: return LocalizationManager.shared.localized("settings.cheats")
            case .bezels: return LocalizationManager.shared.localized("settings.bezels")
            case .retroAchievements: return LocalizationManager.shared.localized("settings.retroAchievements")
            case .genre: return LocalizationManager.shared.localized("settings.genre")
            case .logging: return LocalizationManager.shared.localized("settings.logging")
        case .moveList: return LocalizationManager.shared.localized("settings.moveList")
        case .hotkeys: return LocalizationManager.shared.localized("settings.hotkeys")
        case .help: return LocalizationManager.shared.localized("settings.help")
    case .about: return LocalizationManager.shared.localized("settings.about")
            }
        }
        
        var searchKeywords: String {
            switch self {
            case .general:
                return "general app application version build notifications settings preferences"
            case .saves:
                return "saves save states files auto progressive slots manager"
            case .library:
                return "library folders roms games scan rescan hidden bios"
            case .cores:
                return "cores emulator download update system"
        case .controllers:
            return "controllers gamepad keyboard mapping player buttons input"
        case .analogMouse:
            return "analog mouse stick controller sensitivity deadzone dos scummvm pointer cursor"
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
        case .moveList:
            return "move list moves fighting combo frame data timing input"
        case .hotkeys:
            return "hotkeys keyboard shortcuts save load slot undo training input capture key binding"
        case .help:
      return "help keyboard shortcuts faq documentation troubleshooting resources"
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
        .analogMouse, .boxArt, .cheats, .controllers, .cores, .bezels, .display,
        .general, .hotkeys, .saves, .genre, .help, .library, .logging, .moveList, .retroAchievements, .about
    ]

    private static let pageGroups: [PageGroup] = [
        PageGroup(id: "general", label: LocalizationManager.shared.localized("settingsGroup.general"), pages: [.general, .library]),
        PageGroup(id: "systems", label: LocalizationManager.shared.localized("settingsGroup.systems"), pages: [.cores, .saves, .controllers, .analogMouse, .hotkeys]),
        PageGroup(id: "visuals", label: LocalizationManager.shared.localized("settingsGroup.visuals"), pages: [.boxArt, .display, .bezels, .cheats]),
        PageGroup(id: "advanced", label: LocalizationManager.shared.localized("settingsGroup.advanced"), pages: [.retroAchievements, .genre, .logging, .moveList, .help, .about]),
    ]
    
    @State private var selectedPage: Page = .general
    @State private var searchText: String = ""
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
        if let pendingPage = AppSettings.getString("pending_settings_page"),
           let page = Page(rawValue: pendingPage) {
            selectedPage = page
            AppSettings.remove("pending_settings_page")
        } else if let page = Page(rawValue: AppSettings.getString("settings_selectedTab", defaultValue: "general") ?? "general") {
            selectedPage = page
        }
    }
    
    private var effectiveSystemID: String? {
        if let sid = system?.id { return sid }
        if let pending = AppSettings.getString("pending_settings_system_id") {
            AppSettings.remove("pending_settings_system_id")
            return pending
        }
        return nil
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
        HStack(spacing: 0) {
            // Sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Search field (replaces .searchable)
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                        TextField(loc.localized("settings.search"), text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                    Divider()
                        .padding(.horizontal, 8)

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
            .frame(width: 220)

            // Divider between sidebar and detail
            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(width: 1)

            // Detail
            detailContent
                .id(selectedPage)
                .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .openAppSettings)) { _ in
            syncWithStorage()
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
            case .saves:       SavesSettingsView(searchText: $searchText)
            case .library:     LibrarySettingsView(searchText: $searchText)
            case .cores:       CoreSettingsView(searchText: $searchText)
            case .controllers: ControllerSettingsView(systemID: effectiveSystemID, searchText: $searchText)
            case .analogMouse: AnalogMouseSettingsView(searchText: $searchText)
            case .boxArt: BoxArtSettingsView(searchText: $searchText)
            case .display:     DisplaySettingsView(searchText: $searchText)
            case .cheats:      CheatSettingsView(system: system, searchText: $searchText)
            case .bezels:     BezelSettingsView(system: system, searchText: $searchText)
            case .retroAchievements: RetroAchievementsSettingsView(searchText: $searchText, system: system)
            case .genre:       GenreSettingsView(searchText: $searchText)
            case .logging: LoggingSettingsView(searchText: $searchText)
        case .moveList: MoveListSettingsView(searchText: $searchText)
        case .hotkeys: HotkeyConfigSettingsView(searchText: $searchText)
        case .help: HelpSettingsView()
    case .about: AboutView()
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
