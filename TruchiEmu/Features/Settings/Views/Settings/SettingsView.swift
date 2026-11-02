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
        case general, saves, library, controllers, analogMouse, dosJoystick, boxArt, holo, gameToolbar, cheats, bezels, retroAchievements, genre, logging, moveList, hotkeys, timeMachine, perSystem, streaming, tvMode, help, about, reset

        var rawValue: String {
            switch self {
            case .general: return "general"
            case .saves: return "saves"
            case .library: return "library"
            case .controllers: return "controllers"
            case .analogMouse: return "analogMouse"
            case .dosJoystick: return "dosJoystick"
            case .boxArt: return "boxArt"
            case .holo: return "holo"
            case .gameToolbar: return "gameToolbar"
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
            case "holo": self = .holo
            case "gameToolbar": self = .gameToolbar
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
            case .general, .saves, .boxArt, .holo, .gameToolbar, .bezels, .perSystem, .tvMode:
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
            case .holo: return "sparkles"
            case .gameToolbar: return "menubar.rectangle"
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
            case .holo: return LocalizationManager.shared.localized("settings.holo")
            case .gameToolbar: return LocalizationManager.shared.localized("settings.gameToolbar")
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
            case .holo:
                return "holo holographic foil sparkles effect mask masks vision layer character sky background freeze reveal folder"
            case .gameToolbar:
                return "toolbar overlay game controls buttons items show hide pause save load record rewind screenshot slot fullscreen training guide shader bezel auto hide pin"
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
        .general, .saves, .boxArt, .holo, .gameToolbar, .bezels, .perSystem, .tvMode,
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

    // Per-System navigation state. `selectedSystemID` and `selectedPerSystemCategory`
    // are remembered for the session and persisted, so the tree restores its position.
    @State private var selectedSystemID: String? = nil
    @State private var selectedPerSystemCategory: PerSystemCategory? = nil
    /// The page list is a rail only after the user picks a system, so the slide
    /// itself is the feedback for that click.
    @State private var mainSidebarCollapsed: Bool = true
    @State private var systemsColumnCollapsed: Bool = true
    @State private var perSystemForceActive: Bool = false
    @State private var pendingSystemIDForPage: String? = nil

    @State private var settingsGamepadContext: GamepadNavContext?
    @State private var hasPendingThemeChanges: Bool = false
    @State private var revertRequest: Int = 0
    @State private var applyRequest: Int = 0
    @State private var showThemeChangeConfirmation: Bool = false
    @State private var pendingPageChange: Page?
    @State private var activePending = PendingThemeSettings()

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

        // Restore the remembered Per-System position, whatever page is shown.
        if selectedSystemID == nil,
           let stored = AppSettings.getString("settings_perSystem_system") {
            selectedSystemID = stored
        }
        if let storedCategory = AppSettings.getString("settings_perSystem_category"),
           let category = PerSystemCategory(rawValue: storedCategory) {
            selectedPerSystemCategory = category
        }

        if let pending = AppSettings.getString("pending_settings_system_id") {
            AppSettings.remove("pending_settings_system_id")
            pendingSystemIDForPage = pending
            if selectedPage == .perSystem {
                selectedSystemID = pending
                perSystemForceActive = false
            }
        }

        if selectedPage == .perSystem {
            // Resume with the page list and the system list fully expanded, so
            // the tree is visible on open. Each click then collapses the column
            // the user drills past, as it does during a normal session.
            mainSidebarCollapsed = false
            systemsColumnCollapsed = false
        }
    }

    private var effectiveSystemID: String? {
        if let sid = system?.id { return sid }
        return pendingSystemIDForPage
    }

    // Update storage when selection changes
    private func updateStorage() {
        AppSettings.set("settings_selectedTab", value: selectedPage.rawValue)
        if let sid = selectedSystemID {
            AppSettings.set("settings_perSystem_system", value: sid)
        }
        if let category = selectedPerSystemCategory {
            AppSettings.set("settings_perSystem_category", value: category.rawValue)
        }
    }

    init(system: SystemInfo? = nil, initialPage: SettingsView.Page? = nil) {
        self.system = system

        if let initial = initialPage {
            _selectedPage = State(initialValue: initial)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            navigationStack

            // Divider between navigation stack and detail
            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(width: 1)

            // Detail
            // The page keeps a readable minimum width. When the navigation
            // columns leave less room than that, the page extends past the right
            // edge and is clipped there — it never squeezes the navigation
            // columns. The outer frame can shrink to zero, so the HStack gives
            // the sidebars their fixed widths first.
            detailContent
                .id("\(selectedPage.rawValue)-\(deepLinkID)")
                .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
                .frame(minWidth: 630, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(minWidth: 0, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
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
        pending: activePending
        ))
    }

    // MARK: - Sliding Navigation Stack

    private let navColumnFullWidth: CGFloat = 220
    private let navRailWidth: CGFloat = 44

    private var isPerSystemPage: Bool { selectedPage == .perSystem }

    /// The page list is a rail only in the Per-System tree, and only after the
    /// user picks a system.
    private var isMainSidebarCompact: Bool {
        isPerSystemPage && mainSidebarCollapsed
    }

    private var mainSidebarWidth: CGFloat {
        isMainSidebarCompact ? navRailWidth : navColumnFullWidth
    }

    /// The options column waits for the system click that collapses the page list.
    private var showsOptionsColumn: Bool {
        isMainSidebarCompact && systemForSelectedID != nil
    }

    private var systemsColumnWidth: CGFloat {
        systemsColumnCollapsed ? navRailWidth : navColumnFullWidth
    }

    private var activeSystemIDs: Set<String> {
        let systemIDsWithGames = Set(library.roms.compactMap { $0.systemID })
        let systemIDsWithCores = Set(coreManager.installedCores.flatMap { core in
            core.systemIDs.map { SystemDatabase.normalizeSystemID($0) }
        })
        let db = SystemDatabaseWrapper.shared
        var result = Set<String>()
        for system in db.systemsForDisplay {
            let internalIDs = db.allInternalIDs(forDisplayID: system.id)
            if internalIDs.contains(where: { systemIDsWithGames.contains($0) || systemIDsWithCores.contains($0) }) {
                result.insert(system.id)
            }
        }
        return result
    }

    private var systemForSelectedID: SystemInfo? {
        guard let id = selectedSystemID else { return nil }
        return SystemDatabaseWrapper.shared.system(forID: id)
    }

    /// `nil` means the inactive-system "Setup" placeholder.
    private var effectivePerSystemCategory: PerSystemCategory? {
        guard let system = systemForSelectedID else { return nil }
        if activeSystemIDs.contains(system.id) || perSystemForceActive {
            return selectedPerSystemCategory ?? .shader
        }
        return nil
    }

    private var navigationStack: some View {
        HStack(spacing: 0) {
            mainSidebar(compact: isMainSidebarCompact)
                .frame(width: mainSidebarWidth)
                .clipped()

            if isPerSystemPage {
                Rectangle()
                    .fill(AppColors.divider(colorScheme))
                    .frame(width: 1)

                PerSystemSystemsColumn(
                    activeSystemIDs: activeSystemIDs,
                    selectedSystemID: selectedSystemID,
                    isCompact: systemsColumnCollapsed,
                    searchText: $searchText,
                    onSelect: handleSystemSelection
                )
                .frame(width: systemsColumnWidth)
                .clipped()
                .transition(.opacity)

                if showsOptionsColumn, let system = systemForSelectedID {
                    Rectangle()
                        .fill(AppColors.divider(colorScheme))
                        .frame(width: 1)

                    PerSystemOptionsColumn(
                        system: system,
                        isActive: activeSystemIDs.contains(system.id) || perSystemForceActive,
                        selectedCategory: effectivePerSystemCategory,
                        onSelect: handleCategorySelection
                    )
                    .frame(width: navColumnFullWidth)
                    .clipped()
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isPerSystemPage)
        .animation(.easeInOut(duration: 0.22), value: isMainSidebarCompact)
        .animation(.easeInOut(duration: 0.22), value: systemsColumnCollapsed)
        .animation(.easeInOut(duration: 0.22), value: showsOptionsColumn)
    }

    private func mainSidebar(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                // The search field and the section headers stay in the layout when
                // the sidebar is a rail. They are invisible, so the row positions
                // do not move and the width change reads as a horizontal slide.
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
                .opacity(compact ? 0 : 1)
                .allowsHitTesting(!compact)
                .disabled(compact)

                Divider()
                    .padding(.horizontal, 8)
                    .opacity(compact ? 0 : 1)

                if compact || searchText.isEmpty {
                    ForEach(SidebarSection.allCases) { section in
                        let pages = sidebarPages[section] ?? []
                        if !pages.isEmpty {
                            Text(section.label.uppercased())
                                .font(AppTypography.sectionHeader)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .lineLimit(1)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                                .opacity(compact ? 0 : 1)

                            ForEach(pages) { page in
                                sidebarItem(for: page, compact: compact)
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
            .padding(.horizontal, compact ? 4 : 8)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
    }

    private func handleSystemSelection(_ system: SystemInfo) {
        // Works from both the full list and the collapsed rail. Picking a system
        // is what slides the page list into a rail, and it opens the options
        // column beside the full system list.
        selectedSystemID = system.id
        mainSidebarCollapsed = true
        systemsColumnCollapsed = false
        perSystemForceActive = false
        updateStorage()
    }

    private func handleCategorySelection(_ category: PerSystemCategory?) {
        guard let category else { return }
        selectedPerSystemCategory = category
        // Picking an option gives the detail the space of the system list.
        systemsColumnCollapsed = true
        updateStorage()
    }

    private func browseCoresForSelectedSystem() {
        perSystemForceActive = true
        selectedPerSystemCategory = .core
        systemsColumnCollapsed = true
        updateStorage()
    }

    /// Opens the Per-System tree at the level implied by a search hit.
    private func openPerSystemHit(sectionID: String, label: String? = nil) {
        if let matched = tryMatchSystem(searchText) {
            selectedSystemID = matched
        }
        mainSidebarCollapsed = true
        systemsColumnCollapsed = true

        if let category = Self.perSystemCategory(label: label) {
            selectedPerSystemCategory = category
        }

        if tryMatchSystem(searchText) == nil && (sectionID == "systems" || sectionID == "systemList") {
            // The hit is the system list itself: show the page list and the
            // system list in full.
            mainSidebarCollapsed = false
            systemsColumnCollapsed = false
        }
        updateStorage()
    }

    private static func perSystemCategory(label: String?) -> PerSystemCategory? {
        // Match the option title only: section IDs such as "tabBoxes" would
        // otherwise match unrelated keywords.
        guard let haystack = label?.lowercased(), !haystack.isEmpty else { return nil }
        if haystack.contains("shader") { return .shader }
        if haystack.contains("control") { return .controls }
        if haystack.contains("cheat") { return .cheats }
        if haystack.contains("box") { return .boxArt }
        // "hardcore" contains "core", so test it first.
        if haystack.contains("hardcore") || haystack.contains("achievement") { return .achievements }
        if haystack.contains("core") { return .core }
        if haystack.contains("bezel") { return .bezel }
        return nil
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

    private func sidebarItem(for page: Page, compact: Bool = false) -> some View {
        let isSelected = selectedPage == page
        let isHovered = hoveredPage == page
        return Button {
            if coreManager.isDownloadingCore && page != .perSystem {
                // Show the download progress on the Per-System row, so the page
                // list must be open.
                selectedPage = .perSystem
                mainSidebarCollapsed = false
                systemsColumnCollapsed = false
                return
            }
            if page != .general && hasPendingThemeChanges {
                pendingPageChange = page
                showThemeChangeConfirmation = true
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                // Any page click opens the page list. Per-System also opens the
                // full system list, instead of jumping into a detail.
                mainSidebarCollapsed = false
                if page == .perSystem {
                    systemsColumnCollapsed = false
                }
                selectedPage = page
            }
            // A system scope requested from the library context menu applies only
            // to the page it landed on.
            pendingSystemIDForPage = nil
            updateStorage()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: page.icon)
                    .font(.system(size: 14, weight: .medium))
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(width: 20)
                    .fixedSize()
                    .foregroundColor(isSelected ? AppColors.brandAccent : (isHovered ? AppColors.brandAccent : AppColors.textSecondary(colorScheme)))
                if !compact {
                    Text(page.label)
                        .font(AppTypography.callout)
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                        .fontWeight(isSelected ? .medium : .regular)
                }

                if !compact && coreManager.isDownloadingCore && page == .perSystem {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                }
            }
            // Fixed height keeps the row pitch identical in both widths, so the
            // collapse reads as a horizontal slide with no vertical drift.
            .frame(height: 18)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .padding(.vertical, 7)
            .padding(.horizontal, compact ? 4 : 10)
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
        .help(page.label)
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
                if page == .perSystem {
                    openPerSystemHit(sectionID: sectionID)
                }
                DispatchQueue.main.async {
                    focusedSectionID = sectionID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if focusedSectionID == sectionID { focusedSectionID = nil }
                    }
                }
            case .option(let page, let parentSection, let label, let subID), .description(let page, let parentSection, let label, let subID):
                let targetID = subID ?? parentSection
                selectedPage = page
                scopedSectionID = page == .perSystem ? nil : targetID
                deepLinkID = UUID()
                if page == .perSystem {
                    openPerSystemHit(sectionID: targetID, label: label)
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
                activePending: $activePending
            )
            case .saves:       SavesSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .library:     LibrarySettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .controllers: ControllerSettingsView(systemID: effectiveSystemID, searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .analogMouse: AnalogMouseSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .dosJoystick: DOSJoystickSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .boxArt: BoxArtSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .holo: HoloSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .gameToolbar: ToolbarSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .cheats:      CheatSettingsView(systemID: effectiveSystemID, searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .bezels:     BezelSettingsView(systemID: effectiveSystemID, searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .retroAchievements: RetroAchievementsSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID, system: system)
            case .genre:       GenreSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .logging: LoggingSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .moveList: MoveListSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .hotkeys: HotkeyConfigSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID)
            case .timeMachine: TimeMachineSettingsView(searchText: $searchText, focusedSectionID: $focusedSectionID, scopedSectionID: $scopedSectionID, selectedPage: selectedPageBinding)
            case .perSystem:
                if let system = systemForSelectedID, showsOptionsColumn {
                    PerSystemDetailView(
                        system: system,
                        category: effectivePerSystemCategory,
                        isActive: activeSystemIDs.contains(system.id) || perSystemForceActive,
                        onBrowseCores: browseCoresForSelectedSystem,
                        searchText: $searchText
                    )
                    .id(system.id)
                } else {
                    AppEmptyState(
                        icon: "square.grid.2x2",
                        title: loc.localized("perSystem.selectSystem"),
                        description: loc.localized("perSystem.selectSystemDescription")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
    let pending: PendingThemeSettings

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
        context.coordinator.pending = pending
        if let window = nsView.window, !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            hasPendingChanges: hasPendingChanges,
            onRevert: onRevert,
            pending: pending
        )
    }

    class Coordinator: NSObject, NSWindowDelegate {
        var hasPendingChanges: Bool
        var onRevert: () -> Void
        var pending: PendingThemeSettings

        init(hasPendingChanges: Bool, onRevert: @escaping () -> Void, pending: PendingThemeSettings) {
            self.hasPendingChanges = hasPendingChanges
            self.onRevert = onRevert
            self.pending = pending
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
                tm.applyTheme(pending.theme, customColor: pending.theme == .custom ? pending.customColor : nil)
                tm.setToolbarAccent(pending.toolbarAccent)
                tm.setTintedSurfaces(pending.tintedSurfaces)
                tm.applyAppearanceMode(pending.appearanceMode)
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
