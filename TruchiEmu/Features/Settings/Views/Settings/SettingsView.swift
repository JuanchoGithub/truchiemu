import SwiftUI
import Combine
import Foundation

// MARK: - Main Settings View
struct SettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var hoveredPage: Page? = nil

    enum SidebarSection: String, CaseIterable, Identifiable {
        case general, library, gameplay, systems, advanced

        var id: String { rawValue }

        var localizationKey: String {
            switch self {
            case .general: return "settingsGroup.general"
            case .library: return "settingsGroup.library"
            case .gameplay: return "settingsGroup.gameplay"
            case .systems: return "settingsGroup.systems"
            case .advanced: return "settingsGroup.advanced"
            }
        }

        var label: String {
            LocalizationManager.shared.localized(localizationKey)
        }
    }

    enum Page: Hashable, Codable, RawRepresentable, Identifiable {

        var id: String { rawValue }
        case general, saves, library, controllers, analogMouse, dosJoystick, boxArt, cheats, bezels, retroAchievements, genre, logging, moveList, hotkeys, timeMachine, perSystem, streaming, tvMode, help, about, reset

        var rawValue: String {
            switch self {
            case .general: return "general"
            case .saves: return "saves"
            case .library: return "library"
            case .controllers: return "controllers"
            case .analogMouse: return "analogMouse"
            case .dosJoystick: return "dosJoystick"
            case .boxArt: return "boxArt"
            case .cheats: return "cheats"
            case .bezels: return "bezels"
            case .retroAchievements: return "retroAchievements"
            case .genre: return "genre"
            case .logging: return "logging"
            case .moveList: return "moveList"
            case .hotkeys: return "hotkeys"
            case .timeMachine: return "timeMachine"
            case .perSystem: return "perSystem"
            case .streaming: return "streaming"
            case .tvMode: return "tvMode"
            case .help: return "help"
            case .about: return "about"
            case .reset: return "reset"
            }
        }

        init?(rawValue: String) {
            switch rawValue {
            case "general": self = .general
            case "saves": self = .saves
            case "library": self = .library
            case "controllers": self = .controllers
            case "analogMouse": self = .analogMouse
            case "dosJoystick": self = .dosJoystick
            case "boxArt": self = .boxArt
            case "cheats": self = .cheats
            case "bezels": self = .bezels
            case "retroAchievements": self = .retroAchievements
            case "genre": self = .genre
            case "logging": self = .logging
            case "moveList": self = .moveList
            case "hotkeys", "hotkeysGlobal", "hotkeysGameplay", "gamepadNav": self = .hotkeys
            case "timeMachine": self = .timeMachine
            case "perSystem": self = .perSystem
            case "streaming": self = .streaming
            case "tvMode": self = .tvMode
            case "help": self = .help
            case "about": self = .about
            case "reset": self = .reset
            default: return nil
            }
        }

        var sidebarSection: SidebarSection {
            switch self {
            case .general, .saves, .boxArt, .bezels, .perSystem, .tvMode:
                return .general
            case .library, .controllers, .analogMouse, .dosJoystick, .hotkeys:
                return .library
            case .cheats, .streaming, .retroAchievements, .moveList, .genre, .timeMachine:
                return .gameplay
            case .logging, .help, .about, .reset:
                return .advanced
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .saves: return "externaldrive.fill"
            case .library: return "book.fill"
            case .controllers: return "gamecontroller.fill"
            case .analogMouse: return "computermouse.fill"
            case .dosJoystick: return "gamecontroller.fill"
            case .boxArt: return "photo.stack.fill"
            case .cheats: return "wand.and.stars"
            case .bezels: return "rectangle.on.rectangle"
            case .retroAchievements: return "trophy.fill"
            case .genre: return "tag.fill"
            case .logging: return "doc.text.fill"
            case .moveList: return "figure.martial.arts"
            case .hotkeys: return "keyboard"
            case .timeMachine: return "clock.arrow.circlepath"
            case .perSystem: return "square.grid.2x2"
            case .streaming: return "video.fill"
            case .tvMode: return "tv"
            case .help: return "questionmark.circle.fill"
            case .about: return "info.circle"
            case .reset: return "arrow.uturn.backward"
            }
        }

        var label: String {
            switch self {
            case .general: return LocalizationManager.shared.localized("settings.general")
            case .saves: return LocalizationManager.shared.localized("settings.saves")
            case .library: return LocalizationManager.shared.localized("settings.library")
            case .controllers: return LocalizationManager.shared.localized("settings.controllers")
            case .analogMouse: return LocalizationManager.shared.localized("settings.analogMouse")
            case .dosJoystick: return LocalizationManager.shared.localized("settings.dosJoystick")
            case .boxArt: return LocalizationManager.shared.localized("settings.boxArt")
            case .cheats: return LocalizationManager.shared.localized("settings.cheats")
            case .bezels: return LocalizationManager.shared.localized("settings.bezels")
            case .retroAchievements: return LocalizationManager.shared.localized("settings.retroAchievements")
            case .genre: return LocalizationManager.shared.localized("settings.genre")
            case .logging: return LocalizationManager.shared.localized("settings.logging")
            case .moveList: return LocalizationManager.shared.localized("settings.moveList")
            case .hotkeys: return LocalizationManager.shared.localized("settings.hotkeys")
            case .timeMachine: return LocalizationManager.shared.localized("settings.timeMachine")
            case .perSystem: return LocalizationManager.shared.localized("settings.perSystem")
             case .streaming: return LocalizationManager.shared.localized("settings.streamingAndMedia")
            case .tvMode: return LocalizationManager.shared.localized("settings.tvMode")
            case .help: return LocalizationManager.shared.localized("settings.help")
            case .about: return LocalizationManager.shared.localized("settings.about")
            case .reset: return LocalizationManager.shared.localized("settings.reset.title")
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
            case .controllers:
                return "controllers gamepad keyboard mapping player buttons input"
            case .analogMouse:
                return "analog mouse stick controller sensitivity deadzone dos scummvm pointer cursor"
            case .dosJoystick:
                return "dos joystick gamepad game controller gravis dosbox pure thrustmaster flight stick hat buttons plugged"
            case .boxArt:
                return "box art thumbnail images pictures cover"
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
                return "hotkeys keyboard shortcuts save load slot undo training recording input capture global gameplay key binding gamepad navigation controller overlay toolbar d-pad a b start select l3 r3 combo show game"
            case .timeMachine:
                return "time machine rewind fast forward slow motion speed scrub timeline buffer memory"
            case .perSystem:
                return "system per-system bezels cheats controllers core boxart shader preferences per console platform"
             case .streaming:
                return "streaming recording twitch youtube stream key credentials quality bitrate screenshot share button clip buffer badge rec indicator"
            case .tvMode:
                return "tv mode 10-foot launcher living room couch screen display external monitor multi theme bold muted boxart gamepad buttons controller mapping d-pad pick default"
            case .help:
                return "help keyboard shortcuts faq documentation troubleshooting resources"
            case .about:
                return "about info version truchie emu emulator"
            case .reset:
                return "reset restore defaults factory clear wipe"
            }
        }
    }

    private var sidebarPages: [SidebarSection: [Page]] {
        var bucket: [SidebarSection: [Page]] = [:]
        for section in SidebarSection.allCases {
            bucket[section] = []
        }
        for page in Self.allPages {
            bucket[page.sidebarSection, default: []].append(page)
        }
        return bucket
    }

    static let allPages: [Page] = [
        .general, .saves, .boxArt, .bezels, .perSystem, .tvMode,
        .library, .controllers, .analogMouse, .dosJoystick, .hotkeys,
        .cheats, .retroAchievements, .moveList, .streaming, .genre, .timeMachine,
        .logging, .reset, .help, .about
    ]

    @State private var selectedPage: Page = .general
    var selectedPageBinding: Binding<Page> {
        Binding(
            get: { self.selectedPage },
            set: { self.selectedPage = $0 }
        )
    }
    @State private var deepLinkID = UUID()
    @State private var searchText: String = ""
    @State private var focusedSectionID: String? = nil
    @State private var scopedSectionID: String? = nil
    @State private var pendingSystemSelection: String? = nil
    @State private var settingsGamepadContext: GamepadNavContext?
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
            deepLinkID = UUID()
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
                    // Search field
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
                        ForEach(SidebarSection.allCases) { section in
                            let pages = sidebarPages[section] ?? []
                            if !pages.isEmpty {
                                Text(section.label.uppercased())
                                    .font(AppTypography.sectionHeader)
                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)

                                ForEach(pages) { page in
                                    sidebarItem(for: page)
                                }
                            }
                        }
                    } else {
                        let hits = searchResults
                        if hits.isEmpty {
                            ForEach(filteredPages) { page in
                                sidebarItem(for: page)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loc.localized("settings.searchMatches"))
                                    .font(AppTypography.sectionHeader)
                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                                ForEach(hits.prefix(60)) { hit in
                                    searchHitItem(for: hit)
                                }
                            }
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
                .id("\(selectedPage.rawValue)-\(deepLinkID)")
                .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(SystemDatabaseWrapper.shared)
        .frame(minWidth: 940, minHeight: 552)
        .navigationTitle(loc.localized("app.settings"))
        .onAppear {
            if settingsGamepadContext == nil {
                let ctx = GamepadSheetContext(itemCount: 0)
                ctx.isDismissable = false
                ctx.ownedWindow = NSApp.keyWindow
                settingsGamepadContext = ctx
                GamepadNavContextStack.shared.push(ctx)
            }
            if system != nil {
                if selectedPage == .general && AppSettings.getString("settings_selectedTab", defaultValue: "general") == "general" {
                }
            } else {
                syncWithStorage()
            }
        }
        .onDisappear {
            if let ctx = settingsGamepadContext {
                GamepadNavContextStack.shared.remove(ctx)
                settingsGamepadContext = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAppSettings)) { _ in
            syncWithStorage()
        }
        .onChange(of: selectedPage) { _, _ in
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
                .gamepadDismissable { coreManager.pendingDownload = nil }
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
            SettingsIndex.matches(haystack: page.label, query: searchText) ||
            SettingsIndex.matches(haystack: page.searchKeywords, query: searchText)
        }
    }

    private var searchResults: [SettingsSearchHit] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        SettingsCatalog.bootstrap()
        return SettingsIndex.shared.search(searchText)
    }

    private func tryMatchSystem(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        // Exact ID match (e.g., "NES" -> system with id "nes", "SNES" -> "snes")
        if let exact = SystemDatabaseWrapper.shared.systemsForDisplay.first(where: { $0.id.lowercased() == lower }) {
            return exact.id
        }

        // Name token match (e.g., "NES" -> "Nintendo Entertainment System" via acronym pattern token)
        // Prefer systems whose tokenized name contains the query as a token,
        // before falling back to substring/fuzzy matches (which can be ambiguous).
        var tokenMatch: SystemInfo?
        var substringMatch: SystemInfo?
        var fuzzyMatch: SystemInfo?
        for system in SystemDatabaseWrapper.shared.systemsForDisplay {
            let sysName = system.name.lowercased()
            let queryTokens = lower.split(whereSeparator: { !$0.isLetter }).map { String($0) }
            let nameTokens = sysName.split(whereSeparator: { !$0.isLetter }).map { String($0) }
            if queryTokens.contains(where: { nameTokens.contains($0) }) {
                if tokenMatch == nil { tokenMatch = system }
                continue
            }
            if sysName.contains(lower) || lower.contains(sysName) {
                if substringMatch == nil { substringMatch = system }
                continue
            }
            if sysName.fuzzyMatch(lower) || system.id.lowercased().fuzzyMatch(lower) {
                if fuzzyMatch == nil { fuzzyMatch = system }
            }
        }
        return (tokenMatch ?? substringMatch ?? fuzzyMatch)?.id
    }

    private func sidebarItem(for page: Page) -> some View {
        let isSelected = selectedPage == page
        let isHovered = hoveredPage == page
        return Button {
            if coreManager.isDownloadingCore && page != .perSystem {
                selectedPage = .perSystem
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

                if coreManager.isDownloadingCore && page == .perSystem {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(isSelected ? AppColors.accentBackground(colorScheme) :
                          (isHovered ? AppColors.cardBackgroundSubtle(colorScheme) : .clear))
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
        .onHover { hoveredPage = $0 ? page : nil }
    }

    private func searchHitItem(for hit: SettingsSearchHit) -> some View {
        Button {
            switch hit.kind {
            case .page(let page):
                selectedPage = page
                scopedSectionID = nil
                deepLinkID = UUID()
            case .section(let page, let sectionID):
                selectedPage = page
                scopedSectionID = nil
                deepLinkID = UUID()
                pendingSystemSelection = tryMatchSystem(searchText)
                DispatchQueue.main.async {
                    focusedSectionID = sectionID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if focusedSectionID == sectionID { focusedSectionID = nil }
                    }
                }
            case .option(let page, let parentSection, _, let subID), .description(let page, let parentSection, _, let subID):
                let targetID = subID ?? parentSection
                selectedPage = page
                scopedSectionID = targetID
                deepLinkID = UUID()
                if page == .perSystem {
                    pendingSystemSelection = tryMatchSystem(searchText)
                }
                DispatchQueue.main.async {
                    focusedSectionID = targetID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if focusedSectionID == targetID { focusedSectionID = nil }
                    }
                }
            }
            updateStorage()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: hit.icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18, alignment: .center)
                    .foregroundColor(AppColors.brandAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.title)
                        .font(AppTypography.callout)
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                        .lineLimit(1)
                    Text(hit.breadcrumbs.dropLast().joined(separator: " › "))
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                        .lineLimit(1)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
            )
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
                focusedSectionID: $focusedSectionID,
                scopedSectionID: $scopedSectionID,
                hasPendingChanges: $hasPendingThemeChanges,
                revertRequest: $revertRequest,
                applyRequest: $applyRequest,
                activePendingTheme: $activePendingTheme,
                activePendingCustomColor: $activePendingCustomColor,
                activePendingToolbarAccent: $activePendingToolbarAccent,
                activePendingTintedSurfaces: $activePendingTintedSurfaces,
                activePendingAppearanceMode: $activePendingAppearanceMode
            )
            case .saves:       SavesSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .library:     LibrarySettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .controllers: ControllerSettingsView(systemID: effectiveSystemID, searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .analogMouse: AnalogMouseSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .dosJoystick: DOSJoystickSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .boxArt: BoxArtSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .cheats:      CheatSettingsView(systemID: effectiveSystemID, searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .bezels:     BezelSettingsView(systemID: effectiveSystemID, searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .retroAchievements: RetroAchievementsSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID, system: system)
            case .genre:       GenreSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .logging: LoggingSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .moveList: MoveListSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .hotkeys: HotkeyConfigSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .timeMachine: TimeMachineSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID, selectedPage: selectedPageBinding)
            case .perSystem: PerSystemSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID, pendingSystemID: $pendingSystemSelection)
            case .streaming: StreamingMediaSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .tvMode: TVModeMainSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .help: HelpSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .about: AboutView(focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .reset: ResetSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            }
        }
        .frame(minWidth: 450, minHeight: 350)
        .overlay(alignment: .topTrailing) {
            if scopedSectionID != nil {
                scopeBackChip
            }
        }

        if coreManager.isDownloadingCore {
            CoreDownloadStatusBar(coreManager: coreManager)
        }
    }
    }

    private var scopeBackChip: some View {
        Button {
            scopedSectionID = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(loc.localized("settings.backToSection"))
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule().fill(AppColors.accentBackground(colorScheme))
            )
            .overlay(
                Capsule().stroke(AppColors.brandAccent.opacity(0.4), lineWidth: 1)
            )
            .foregroundStyle(AppColors.brandAccent)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.trailing, 14)
        .help(loc.localized("settings.backToSectionHelp"))
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
                if !window.styleMask.contains(.resizable) {
                    window.styleMask.insert(.resizable)
                }
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
        if let window = nsView.window, !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
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
