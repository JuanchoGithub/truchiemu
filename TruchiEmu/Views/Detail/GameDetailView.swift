import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var library: ROMLibrary
    @ObservedObject private var gamepadNav = GamepadNavigationManager.shared
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var categoryManager: CategoryManager
    @ObservedObject var sysPrefs = SystemPreferences.shared
    @ObservedObject private var boxArtService = BoxArtService.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) var openSettings
	var rom: ROM
	var initialSection: DetailSection?

	@StateObject var saveStateManager = SaveStateManager()
	@StateObject var achievementsService = RetroAchievementsService.shared
	@State var showBoxArtPicker = false
    @State var showManualMatch = false
    @StateObject var gameLauncher = GameLauncher.shared
    @State var boxArtImage: NSImage? = nil
    @State var boxArtImageURL: URL? = nil
    @State var screenshotImages: [NSImage] = []
    @State var crcHash: String? = nil
    @State var raHash: String? = nil
    @State var fileSize: String? = nil
    @State var slotInfoList: [SlotInfo] = []
    @State var progressiveSlots: [Int: [SlotInfo]] = [:]
@State var gameAchievements:[Achievement] = []
@State var isAchievementsLoading = false
@State var expandedAchievementID: Int? = nil
@State var expandedProgressiveSlotID: Int? = nil
@State var achievementViewMode: AchievementViewMode = .grid
@State var achievementGridWidth: CGFloat = 700
    @State var showImportCheatFile = false
    @State var gbColorizationEnabled: Bool = true
    @State var gbColorizationMode: String = "auto"
    @State var gbInternalPalette: String = "GB - DMG"
    @State var gbSGBBordersEnabled: Bool = true
    @State var gbColorCorrectionMode: String = "gbc_only"

    @State var useCustomCore: Bool = false
    @State var selectedCoreID: String? = nil
    @State var applyCoreToSystem: Bool = false
    @StateObject var manualAction = ManualStatusController()

    @State var shaderWindowSettings: ShaderWindowSettings?
    @State var selectedSection: DetailSection = .gameInfo
    @State var hoveredSection: DetailSection? = nil
    @State var bezelSelectorWindowController: BezelSelectorWindowController?
    @State var localTitle: String = ""
    @State var isEditingTitle: Bool = false
    @FocusState var titleFieldFocused: Bool
    @State var gameDescription: String? = nil
    @State var mostRecentSaveSlot: SlotInfo? = nil
    @State var titleScreenImage: NSImage? = nil

    @ObservedObject var loc = LocalizationManager.shared

    @StateObject var fetchMetadata = ManualStatusController()
    @StateObject var fetchBoxArt = ManualStatusController()
    @State var currentBezelImage: NSImage? = nil
    @StateObject var cheatManagerService = CheatManagerService.shared
    @State var isLaunchingGame = false
    @State var showSystemPicker: Bool = false
    @State var gamepadTwoZoneContext: GamepadTwoZoneContext?

// MARK: - RA Hash Comparison State
@State var showRAHashComparison = false
@State var raComparisonTitle: String = ""
@State var raComparisonHashes: [String] = []
@State var raComparisonCurrentHash: String = ""
@State var raComparisonMatchedHash: String?
@State var raComparisonRAGameId: Int?
@State var isFindingRAGame = false
@State var raComparisonError: String?
@State var raComparisonNameMatches: [RAHashComparisonContent.NameMatchItem] = []
    @StateObject var raVerification = ManualStatusController()

    @State var openCriticFetching: Bool = false
    @State var openCriticErrorMessage: String? = nil

    var currentROM: ROM {
        library.rom(withID: rom.id) ?? rom
    }

    /// The RetroAchievements match state of the current game.
    ///
    /// The value changes when the "Vincular biblioteca" operation finds the
    /// game. The view loads the achievements when the value changes. The
    /// value holds the status and the game ID in one string, so the view
    /// loads the achievements only once when both values change.
    var raMatchKey: String {
        "\(currentROM.raMatchStatus ?? "none")|\(currentROM.raGameId ?? 0)"
    }

    var system: SystemInfo? {
        SystemDatabase.displaySystem(forInternalID: currentROM.systemID ?? "")
    }

    var activeCoreID: String? {
        guard let sysID = currentROM.systemID, let sys = SystemDatabase.system(forID: sysID) else { return system?.defaultCoreID }
        if currentROM.useCustomCore, let sel = currentROM.selectedCoreID { return sel }
        return sysPrefs.preferredCoreID(for: sysID) ?? sys.defaultCoreID
    }

    var systemName: String {
        SystemDatabase.systemName(forInternalID: currentROM.systemID ?? "")
    }

    var isGambatteCore: Bool {
        (activeCoreID ?? "").lowercased().contains("gambatte")
    }

    var installedCores:[LibretroCore] {
        guard let sysID = currentROM.systemID else { return[] }
        return coreManager.installedCores.filter { $0.systemIDs.contains(sysID) }
    }

    var isIdentifyWorking: Bool {
        if manualAction.isWorking { return true }
        return false
    }

    var shaderManager: ShaderManager { ShaderManager.shared }
    var unlockedAchievementCount: Int { gameAchievements.filter { $0.isUnlocked }.count }
    var totalAchievementPoints: Int { gameAchievements.reduce(0) { $0 + $1.points } }
    var earnedPoints: Int { gameAchievements.filter { $0.isUnlocked }.reduce(0) { $0 + $1.points } }
    var systemDefaultShaderID: String {
        SystemDatabase.system(forID: currentROM.systemID ?? "")?.defaultShaderPresetID ?? ""
    }
    var isShaderCustomized: Bool {
        !currentROM.settings.shaderPresetID.isEmpty && currentROM.settings.shaderPresetID != systemDefaultShaderID
    }

    @ViewBuilder
    var mainContentArea: some View {
        HStack(spacing: 0) {
            Group {
                if selectedSection == .gameInfo {
                    gameInfoMainScroll
                } else {
                    VStack(spacing: 0) {
                        detailSectionHero
                        sectionScroll
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if selectedSection == .gameInfo {
                gameInfoInspector
            }
        }
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(gamepadNav.isGamepadActive && gamepadTwoZoneContext?.activeZone == .content ? AppColors.brandAccent.opacity(0.4) : Color.clear, lineWidth: 2)
                .padding(2)
        )
    }

    /// Game info keeps its fact sheet in a fixed inspector rail so the
    /// metadata stays visible while the narrative column scrolls.
    private var gameInfoMainScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                overviewMainColumn
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
    }

    private var gameInfoInspector: some View {
        ScrollView {
            overviewRail
                .padding(16)
        }
        .scrollContentBackground(.hidden)
        .frame(width: 292)
        .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .overlay(alignment: .leading) {
            Divider().overlay(AppColors.divider(colorScheme))
        }
    }

    // MARK: - Section Hero

    /// Live facts for the section header. Each section shows only the counts it
    /// owns, then falls back to play history so the band is never empty.
    private var detailSectionHeroStats: [DeckStatItem] {
        var items: [DeckStatItem] = []

        switch selectedSection {
        case .shader:
            items.append(DeckStatItem(
                id: "shader",
                icon: "display",
                value: ShaderManager.displayName(for: ShaderManager.effectivePresetID(for: currentROM)),
                unit: loc.localized("gameDetail.shader"),
                tint: isShaderCustomized ? AppColors.warning(colorScheme) : AppColors.brandAccent
            ))
        case .savedStates:
            let saves = slotInfoList.filter { $0.exists }.count
            if saves > 0 {
                items.append(DeckStatItem(
                    id: "saves",
                    icon: "externaldrive.fill",
                    value: saves.formatted(),
                    unit: loc.localized("gameDetail.savedStates")
                ))
            }
        case .achievements:
            if !gameAchievements.isEmpty {
                items.append(DeckStatItem(
                    id: "achievements",
                    icon: "trophy.fill",
                    value: "\(unlockedAchievementCount)/\(gameAchievements.count)",
                    unit: loc.localized("gameDetail.achievements"),
                    tint: AppColors.warning(colorScheme)
                ))
                items.append(DeckStatItem(
                    id: "points",
                    icon: "star.fill",
                    value: "\(earnedPoints)/\(totalAchievementPoints)",
                    unit: loc.localized("achievement.pointsLabel"),
                    tint: AppColors.warning(colorScheme)
                ))
            }
        case .technical:
            if let fileSize {
                items.append(DeckStatItem(
                    id: "size",
                    icon: "externaldrive",
                    value: fileSize,
                    unit: loc.localized("gameInfo.fileSize")
                ))
            }
            if let crcHash {
                items.append(DeckStatItem(
                    id: "crc",
                    icon: "number",
                    value: String(crcHash.prefix(8)),
                    unit: loc.localized("gameInfo.crc32")
                ))
            }
        case .controls:
            items.append(DeckStatItem(
                id: "controllers",
                icon: "gamecontroller.fill",
                value: controllerService.connectedControllers.count.formatted(),
                unit: loc.localized("settings.unit.controllers")
            ))
        case .openCritic:
            if let score = currentROM.metadata?.openCriticScore, score > 0 {
                items.append(DeckStatItem(
                    id: "score",
                    icon: "star.fill",
                    value: "\(score)",
                    unit: loc.localized("gameDetail.openCritic"),
                    tint: AppColors.warning(colorScheme)
                ))
            }
        default:
            break
        }

        if items.isEmpty {
            if currentROM.totalPlaytimeSeconds > 0 {
                items.append(DeckStatItem(
                    id: "playtime",
                    icon: "hourglass",
                    value: Self.compactPlaytime(currentROM.totalPlaytimeSeconds),
                    unit: loc.localized("gameDetail.playtime")
                ))
            } else if currentROM.timesPlayed > 0 {
                items.append(DeckStatItem(
                    id: "sessions",
                    icon: "gamecontroller.fill",
                    value: "\(currentROM.timesPlayed)",
                    unit: loc.localized("gameDetail.sessions")
                ))
            }
        }

        return Array(items.prefix(3))
    }

    private var detailSectionHero: some View {
        DeckHeroBand(
            icon: selectedSection.sectionIcon,
            eyebrow: systemName.isEmpty ? loc.localized("gameInfo.system") : systemName,
            title: selectedSection.localizedTitle,
            stats: detailSectionHeroStats
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(height: 1)
        }
    }

    private var sectionScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AnyView(sectionContent)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .gameInfo: overviewMainColumn
        case .technical: technicalSection
        case .shader: shaderSection
        case .bezels: bezelsSection
        case .controls: controlsSection
        case .analogMouse: analogMouseSection
        case .dosJoystick: dosJoystickSection
        case .coreOptions: coreOptionsSection
        case .savedStates: savedStatesSection
        case .cheats: cheatsSection
        case .core: coreSection
        case .achievements:
            if achievementsService.isEnabled {
                achievementsSection
            }
        case .openCritic:
            openCriticSection
        }
    }

    @ViewBuilder
    var raHashComparisonSheet: some View {
        RAHashComparisonContent(
            gameTitle: raComparisonTitle,
            systemName: systemName,
            hashes: raComparisonHashes,
            currentHash: raComparisonCurrentHash,
            matchedHash: raComparisonMatchedHash,
            raGameId: raComparisonRAGameId,
            error: raComparisonError,
            isLoading: isFindingRAGame,
            nameMatches: raComparisonNameMatches
        )
    }

    var body: some View {
        GeometryReader { geo in
            let headerHeight = min(max(geo.size.height * 0.38, 250), 300)
            VStack(spacing: 0) {
                compactHeaderSection
                    .frame(height: headerHeight)

                Divider()
                    .overlay(AppColors.divider(colorScheme))

                HStack(spacing: 0) {
                    sidebarNavigation

                    Divider()
                        .overlay(AppColors.divider(colorScheme))

                    mainContentArea
                }
                .frame(maxHeight: .infinity)

                if manualAction.isVisible {
                    manualActionStatusBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
            .animation(.easeInOut(duration: 0.2), value: manualAction.isVisible)
        }
	.onAppear {
		if let initial = initialSection {
			selectedSection = initial
		}
		loadBoxArt()
            loadSlotInfo()
            loadTitleScreen()
            loadScreenshots()
            // Only load achievements if we're logged in and RA is enabled
            if achievementsService.isLoggedIn && achievementsService.isEnabled {
                loadAchievements()
            }
            useCustomCore = currentROM.useCustomCore
            selectedCoreID = currentROM.selectedCoreID ?? sysPrefs.preferredCoreID(for: currentROM.systemID ?? "") ?? system?.defaultCoreID
    loadGBColorizationSettings()
    loadAchievementViewMode()
    setupGamepadNavContext()
  }
  .onDisappear {
      teardownGamepadNavContext()
  }
  // Own this window from the window that hosts the view. `NSApp.keyWindow`
  // in `onAppear` can still be the library window, because SwiftUI shows the
  // game-info window before it becomes key. A context owned by the wrong
  // window is skipped by `topActive()`, and the library then receives A/B
  // presses meant for the detail window.
  .gamepadNavWindowOwner(gamepadTwoZoneContext)
    .onChange(of: currentROM.id) { _, _ in
        manualAction.clear()
        loadSlotInfo()
        loadTitleScreen()
        loadScreenshots()
        isEditingTitle = false
        if achievementsService.isLoggedIn && achievementsService.isEnabled {
          loadAchievements()
        }
        loadAchievementViewMode()
      }
  .onChange(of: currentROM.lastPlayed) { _, _ in
            // Refresh slot info when user returns from playing the game
            loadSlotInfo()
        }
        .onChange(of: raMatchKey) { _, _ in
            // The "Vincular biblioteca" operation found this game. Load the
            // achievements now, so the user sees the result of the work.
            loadAchievements()
        }
        .task(id: currentROM.id) {
            if currentROM.systemID == "mame" || currentROM.systemID == "arcade" {
                await MAMEUnifiedService.shared.ensureLoaded()
                let shortName = currentROM.shortNameForMAME
                if let unifiedEntry = MAMEUnifiedService.shared.lookup(shortName: shortName) {
                    gameDescription = unifiedEntry.description
                }
            }

            if gameDescription == nil {
                if let desc = currentROM.metadata?.description, !desc.isEmpty {
                    gameDescription = desc
                } else if let info = currentROM.metadata?.title, let year = currentROM.metadata?.year {
                    gameDescription = "\(info) (\(year))"
                } else {
                    gameDescription = nil
                }
            }

            if let attrs = try? FileManager.default.attributesOfItem(atPath: currentROM.path.path),
               let size = attrs[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                fileSize = formatter.string(fromByteCount: size)
            }
            crcHash = currentROM.crc32
            if achievementsService.isEnabled {
                Task { @MainActor in
                    let hash = await Task.detached(priority: .background) {
                        await RomHasher.hashRom(at: currentROM.path.path, systemID: currentROM.systemID ?? "")
                    }.value
                    raHash = hash
                }
            }
        }
        .onChange(of: currentROM.hasBoxArt) { _, _ in loadBoxArt() }
        .onChange(of: boxArtService.boxArtUpdated) { _, _ in loadBoxArt() }
.onChange(of: currentROM.hasTitleScreen) { _, _ in loadTitleScreen() }
.onChange(of: currentROM.screenshotPaths) { _, _ in loadScreenshots() }
.onChange(of: library.bezelUpdateToken) { _, _ in Task { await loadCurrentBezelImage() } }
.onChange(of: achievementViewMode) { _, newValue in
    AppSettings.setString(newValue.rawValue, value: newValue.rawValue)
    AppSettings.setString("achievementViewMode_\(currentROM.id.uuidString)", value: newValue.rawValue)
}
        .onChange(of: achievementsService.authState) { _, _ in
            if achievementsService.isLoggedIn && achievementsService.isEnabled {
                loadAchievements()
            } else {
                gameAchievements = []
                isAchievementsLoading = false
            }
        }
        .onChange(of: achievementsService.isEnabled) { _, _ in
            if achievementsService.isLoggedIn && achievementsService.isEnabled {
                loadAchievements()
            } else {
                gameAchievements = []
                isAchievementsLoading = false
            }
        }
        .sheet(isPresented: $showBoxArtPicker) { BoxArtPickerView(rom: currentROM)
            .gamepadDismissable { showBoxArtPicker = false }
        }
        .sheet(isPresented: $showManualMatch) {
            ManualGameMatchSheet(rom: currentROM) { message in
                let refreshed = library.rom(withID: rom.id)
                if let description = refreshed?.metadata?.description, !description.isEmpty {
                    gameDescription = description
                } else if let title = refreshed?.metadata?.title, !title.isEmpty {
                    gameDescription = refreshed?.metadata?.year.map { "\(title) (\($0))" } ?? title
                } else {
                    gameDescription = nil
                }
                showManualResult(message, tone: .success)
                loadBoxArt()
                loadTitleScreen()
                loadScreenshots()
            }
            .gamepadDismissable { showManualMatch = false }
        }
        .sheet(isPresented: $showRAHashComparison) { raHashComparisonSheet
            .gamepadDismissable { showRAHashComparison = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenCriticDataFetched"))) { note in
            guard let romID = note.userInfo?["romID"] as? UUID, romID == currentROM.id else { return }
            guard let score = note.userInfo?["score"] as? Double,
                  let tier = note.userInfo?["tier"] as? String,
                  let pct = note.userInfo?["percentRecommended"] as? Double,
                  let gameID = note.userInfo?["gameID"] as? Int else { return }
            var updated = currentROM
            if updated.metadata == nil { updated.metadata = ROMMetadata() }
            updated.metadata?.openCriticScore = Int(score.rounded())
            updated.metadata?.openCriticTier = tier
            updated.metadata?.openCriticPercentRecommended = Int(pct.rounded())
            updated.metadata?.openCriticID = gameID
            updated.metadata?.openCriticFetchAttempted = true
            if let numReviews = note.userInfo?["numReviews"] as? Int {
                updated.metadata?.openCriticReviewCount = numReviews
            }
            library.updateROM(updated)
        }
        .sheet(isPresented: $showSystemPicker) {
            SystemPickerView(roms: [currentROM], library: library) {
                showSystemPicker = false
            }
            .gamepadDismissable { showSystemPicker = false }
        }
    }

    private struct DetailNavGroup {
        let title: String
        let sections: [DetailSection]
    }

    /// Sidebar groups. Flattening them keeps the gamepad navigation index in
    /// sync with the visible row order.
    private var navGroups: [DetailNavGroup] {
        var game: [DetailSection] = [.gameInfo, .savedStates]
        if achievementsService.isEnabled {
            game.append(.achievements)
        }
        game.append(.cheats)
        if let key = OpenCriticService.shared.apiKey, !key.isEmpty {
            game.append(.openCritic)
        }

        var setup: [DetailSection] = [.shader, .bezels, .controls]
        if let sysID = currentROM.systemID, sysID == "dos" || sysID == "scummvm" {
            setup.append(.analogMouse)
        }
        if currentROM.systemID == "dos" {
            setup.append(.dosJoystick)
        }
        if currentROM.systemID == "gb" || currentROM.systemID == "gbc" {
            setup.append(.coreOptions)
        }

        return [
            DetailNavGroup(title: loc.localized("gameDetail.groupGame"), sections: game),
            DetailNavGroup(title: loc.localized("gameDetail.groupSetup"), sections: setup),
            DetailNavGroup(title: loc.localized("gameDetail.groupAdvanced"), sections: [.core, .technical])
        ]
    }

    var allSections: [DetailSection] {
        navGroups.flatMap(\.sections)
    }

    var sidebarNavigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(navGroups.enumerated()), id: \.offset) { index, group in
                VStack(alignment: .leading, spacing: 2) {
                    if index > 0 {
                        Divider()
                            .overlay(AppColors.divider(colorScheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                    }

                    Text(verbatim: group.title.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                        .padding(.horizontal, 10)
                        .padding(.bottom, 2)

                    ForEach(group.sections, id: \.self) { section in
                        sidebarItem(for: section)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 190)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .padding(.horizontal, 8)
        .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
    }

    func sidebarItem(for section: DetailSection) -> some View {
        let isSelected = selectedSection == section
        let isHovered = hoveredSection == section
        let allItems = allSections
        let sectionIndex = allItems.firstIndex(of: section) ?? 0
        let isGamepadFocused = gamepadNav.isGamepadActive
            && gamepadTwoZoneContext?.activeZone == .sidebar
            && gamepadTwoZoneContext?.sidebarIndex == sectionIndex
        let badge = sidebarBadge(for: section)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.sectionIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.textOnAccent(colorScheme) : AppColors.textTertiary(colorScheme))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected
                                  ? AppColors.brandAccent
                                  : AppColors.cardBackgroundSubtle(colorScheme).opacity(0.8))
                    )

                Text(section.localizedTitle)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? AppColors.textPrimary(colorScheme) : AppColors.textSecondary(colorScheme))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let badge {
                    Text(verbatim: badge)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? AppColors.brandAccent : AppColors.textTertiary(colorScheme))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected
                                      ? AppColors.brandAccent.opacity(0.14)
                                      : AppColors.cardBackgroundSubtle(colorScheme))
                        )
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.helpText)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected
                      ? AppColors.accentBackground(colorScheme)
                      : (isHovered ? AppColors.cardBackgroundSubtle(colorScheme) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? AppColors.brandAccent.opacity(0.25) : .clear, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(AppColors.brandAccent)
                .frame(width: 3, height: 16)
                .padding(.leading, 3)
                .opacity(isSelected ? 1 : 0)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isGamepadFocused ? AppColors.brandAccent : Color.clear, lineWidth: 2)
        )
        .animation(AppMotion.stateChange, value: isSelected)
        .onHover { hoveredSection = $0 ? section : nil }
    }

    /// Live counts make the nav rows useful without opening them.
    func sidebarBadge(for section: DetailSection) -> String? {
        switch section {
        case .savedStates:
            let count = slotInfoList.filter { $0.exists }.count
            return count > 0 ? "\(count)" : nil
        case .achievements:
            guard !gameAchievements.isEmpty else { return nil }
            return "\(unlockedAchievementCount)/\(gameAchievements.count)"
        default:
            return nil
        }
    }

    func loadSlotInfo() {
        // File-system scan stays off the main thread; the view assigns on Main.
        // The id guard drops stale results when the user flips games quickly.
        let id = rom.id
        let candidates = currentROM.stateKeyCandidates
        let systemID = currentROM.systemID ?? ""
        let manager = saveStateManager
        Task.detached(priority: .userInitiated) {
            let set = manager.mergedSaveSet(primaryKey: candidates.primary, fallbackKeys: candidates.fallbacks, systemID: systemID)
            await MainActor.run {
                guard self.rom.id == id else { return }
                self.slotInfoList = set.slotList
                self.progressiveSlots = set.progressiveSlotList
                self.mostRecentSaveSlot = set.mostRecentSlot
            }
        }
    }

    func loadMostRecentSaveState() {
        let id = rom.id
        let candidates = currentROM.stateKeyCandidates
        let systemID = currentROM.systemID ?? ""
        let manager = saveStateManager
        Task.detached(priority: .userInitiated) {
            let slot = manager.mergedMostRecentSaveState(primaryKey: candidates.primary, fallbackKeys: candidates.fallbacks, systemID: systemID)
            await MainActor.run {
                guard self.rom.id == id else { return }
                self.mostRecentSaveSlot = slot
            }
        }
    }

    func loadTitleScreen() {
        Task {
            // Already on disk — just load it.
            if currentROM.hasTitleScreen, !currentROM.titleScreenLocalPath.path.isEmpty,
               let img = await ImageCache.shared.image(for: currentROM.titleScreenLocalPath) {
                titleScreenImage = img
                return
            }
            titleScreenImage = nil

            // Fallback: if the scan-time pass missed the title screen (network
            // failure, already-cataloged game, etc.), fetch it lazily now.
            guard !currentROM.hasTitleScreen else { return }
            let rom = currentROM
            await BoxArtService.shared.downloadTitleAndScreenshots(for: rom, library: library)
            if currentROM.hasTitleScreen, !currentROM.titleScreenLocalPath.path.isEmpty,
               let img = await ImageCache.shared.image(for: currentROM.titleScreenLocalPath) {
                titleScreenImage = img
            }
        }
    }

    @MainActor
    func loadAchievements() {
        if let raGameId = currentROM.raGameId, raGameId > 0, currentROM.raMatchStatus == "matched" {
            loadAchievements(raGameId: raGameId)
        } else {
            gameAchievements = []
            isAchievementsLoading = false
        }
    }

    @MainActor
    func loadAchievements(raGameId: Int) {
        guard achievementsService.isEnabled else {
            LoggerService.info(category: "GameDetailView", "loadAchievements: RA not enabled, bailing")
            return
        }
        guard achievementsService.isLoggedIn else {
            LoggerService.info(category: "GameDetailView", "loadAchievements: not logged in, bailing")
            return
        }
        isAchievementsLoading = true
        gameAchievements = []
        LoggerService.info(category: "GameDetailView", "loadAchievements: fetching for raGameId=\(raGameId)")

        Task {
            do {
                let gameInfo = try await achievementsService.fetchGameInfo(gameID: raGameId, username: achievementsService.username ?? "", isUserInitiated: false)
                await MainActor.run {
                    LoggerService.info(category: "GameDetailView", "loadAchievements: got \(gameInfo.achievements.count) achievements for '\(gameInfo.title)' (consoleID: \(gameInfo.consoleID))")
                    achievementsService.currentGame = gameInfo
                    gameAchievements = gameInfo.achievements
                    isAchievementsLoading = false
                }
            } catch {
                let errorMsg = "\(error)"
                LoggerService.error(category: "GameDetailView", "loadAchievements: fetch failed: \(errorMsg)")
                await MainActor.run {
                    gameAchievements = []
                    isAchievementsLoading = false
                    NotificationService.shared.sendNotification(
                        title: loc.localized("achievement.fetchErrorTitle"),
                        body: loc.localized("achievement.fetchErrorBody")
                    )
                }
            }
        }
    }

    @MainActor
    func loadAchievementsAndReturnCount(raGameId: Int, force: Bool = false) async -> Int {
        guard achievementsService.isEnabled, achievementsService.isLoggedIn else { return 0 }
        isAchievementsLoading = true
        gameAchievements = []
        LoggerService.info(category: "GameDetailView", "loadAchievementsAndReturnCount: fetching for raGameId=\(raGameId) (force=\(force))")
        do {
            let gameInfo = try await achievementsService.fetchGameInfo(gameID: raGameId, username: achievementsService.username ?? "", isUserInitiated: true, force: force)
            achievementsService.currentGame = gameInfo
            gameAchievements = gameInfo.achievements
            isAchievementsLoading = false
            LoggerService.info(category: "GameDetailView", "loadAchievementsAndReturnCount: got \(gameInfo.achievements.count) achievements for '\(gameInfo.title)'")
            return gameInfo.achievements.count
        } catch {
            LoggerService.error(category: "GameDetailView", "loadAchievementsAndReturnCount: fetch failed: \(error)")
            gameAchievements = []
            isAchievementsLoading = false
            return 0
        }
    }

    @MainActor
    func findInRA() {
        guard achievementsService.isEnabled else { return }
        guard achievementsService.isLoggedIn else { return }
        guard let systemID = currentROM.systemID else { return }

        isFindingRAGame = true
        raComparisonError = nil
        raComparisonTitle = currentROM.displayName
        raVerification.showWorking(loc.localized("achievement.loadingAchievements"))

        let raConsoleID = achievementsService.mapSystemIDToRAConsoleID(systemID)
        let sysName = systemName

        guard raConsoleID > 0 else {
            raComparisonError = "This system is not supported by RetroAchievements"
            isFindingRAGame = false
            showRAHashComparison = true
            raVerification.clear()
            return
        }

        Task {
            let computedHash = RomHasher.hashRom(at: currentROM.path.path, systemID: systemID)

            guard let hash = computedHash else {
                await MainActor.run {
                    raComparisonCurrentHash = "Could not compute RA hash"
                    raComparisonError = "Could not compute hash for this ROM file"
                    raComparisonHashes = []
                    raComparisonMatchedHash = nil
                    isFindingRAGame = false
                    showRAHashComparison = true
                    raVerification.clear()
                    NotificationHistoryManager.shared.post(
                        icon: "xmark.octagon",
                        title: loc.localized("raHash.title"),
                        subtitle: loc.localized("raHash.pillHashErrorSubtitle"),
                        )
                    NotificationService.shared.sendNotification(
                        title: loc.localized("raHash.title"),
                        body: loc.localized("raHash.notificationHashError")
                            .replacingOccurrences(of: "{title}", with: currentROM.displayName)
                    )
                }
                return
            }

            await MainActor.run {
                raComparisonCurrentHash = hash
            }

            // The hash list for this console may never have been downloaded.
            // Fetch it now so the ROM can be identified. Cached lists are
            // reused, so this only hits the network when data is missing.
            await achievementsService.ensureGameListForConsole(consoleID: raConsoleID)

            if let cachedGame = await achievementsService.findGameByHashLocally(consoleID: raConsoleID, hash: hash, isUserInitiated: true) {
                // Hash matched a cached RA game. Persist the match so the trophy
                // badge shows in the library, and fetch the game's full achievement
                // data. The achievements section will display a "0 achievements"
                // state if the server has none for this game.
                let achievementCount = await loadAchievementsAndReturnCount(raGameId: cachedGame.id)

                var updatedROM = currentROM
                updatedROM.raGameId = cachedGame.id
                updatedROM.raMatchStatus = "matched"
                library.updateROM(updatedROM)
                #if LOG_DEBUG
                LoggerService.debug(category: "GameDetailView", "Persisted RA match: raGameId=\(cachedGame.id), title='\(cachedGame.title)', achievements=\(achievementCount)")
                #endif

                await MainActor.run {
                    raComparisonRAGameId = cachedGame.id
                    raComparisonTitle = cachedGame.title
                    raComparisonHashes = cachedGame.hashes
                    raComparisonMatchedHash = hash
                    isFindingRAGame = false
                    let raURL = "https://retroachievements.org/game/\(cachedGame.id)"
                    if achievementCount > 0 {
                        raVerification.showResult(loc.localized("achievement.romVerified"), tone: .success, autoDismissAfter: 5_000_000_000)
                        NotificationHistoryManager.shared.post(
                            icon: "trophy.fill",
                            title: loc.localized("raHash.notificationMatchTitle"),
                            subtitle: loc.localized("raHash.pillMatchSubtitle")
                                .replacingOccurrences(of: "{title}", with: cachedGame.title)
                                .replacingOccurrences(of: "{n}", with: "\(achievementCount)"),
                            actionLabel: loc.localized("raHash.viewOnRetroAchievements"),
                            actionType: "openURL",
                            actionPayload: OpenURLActionPayload(url: raURL)
                        )
                    } else {
                        raVerification.showResult(loc.localized("achievement.romMatchedNoAchievements"), tone: .info, autoDismissAfter: 6_000_000_000)
                        NotificationHistoryManager.shared.post(
                            icon: "trophy",
                            title: loc.localized("raHash.pillZeroAchievementsTitle"),
                            subtitle: loc.localized("raHash.pillZeroAchievementsSubtitle")
                                .replacingOccurrences(of: "{title}", with: cachedGame.title),
                            actionLabel: loc.localized("raHash.viewOnRetroAchievements"),
                            actionType: "openURL",
                            actionPayload: OpenURLActionPayload(url: raURL)
                        )
                    }
                    NotificationService.shared.sendNotification(
                        title: loc.localized("raHash.notificationMatchTitle"),
                        body: loc.localized("raHash.notificationMatchBody")
                            .replacingOccurrences(of: "{title}", with: cachedGame.title)
                            .replacingOccurrences(of: "{system}", with: sysName)
                    )
                }
            } else {
                let nameMatches = await achievementsService.findAllRAGamesByName(title: currentROM.displayName, consoleID: raConsoleID)
                await MainActor.run {
                    if let firstMatch = nameMatches.first {
                        raComparisonRAGameId = firstMatch.id
                        raComparisonTitle = firstMatch.title
                        raComparisonHashes = firstMatch.hashes
                        raComparisonMatchedHash = nil
                    }
                    raComparisonNameMatches = nameMatches.map { RAHashComparisonContent.NameMatchItem(id: $0.id, title: $0.title, hashes: $0.hashes) }
                    isFindingRAGame = false
                    raVerification.clear()
                    showRAHashComparison = true

                    if nameMatches.isEmpty {
                        NotificationHistoryManager.shared.post(
                            icon: "magnifyingglass",
                            title: loc.localized("raHash.notificationNoMatchTitle"),
                            subtitle: loc.localized("raHash.pillNotFoundSubtitle")
                                .replacingOccurrences(of: "{title}", with: currentROM.displayName)
                                .replacingOccurrences(of: "{system}", with: sysName),
                            actionLabel: loc.localized("raHash.requestOnRA"),
                            actionType: "openURL",
                            actionPayload: OpenURLActionPayload(url: "https://retroachievements.org/viewtopic.php?t=15027")
                        )
                        NotificationService.shared.sendNotification(
                            title: loc.localized("raHash.notificationNoMatchTitle"),
                            body: loc.localized("raHash.notificationNoMatchBody")
                                .replacingOccurrences(of: "{title}", with: currentROM.displayName)
                                .replacingOccurrences(of: "{system}", with: sysName)
                        )
                    } else {
                        let firstMatch = nameMatches.first
                        let mismatchURL = firstMatch.map { "https://retroachievements.org/game/\($0.id)" } ?? ""
                        NotificationHistoryManager.shared.post(
                            icon: "exclamationmark.triangle",
                            title: loc.localized("raHash.notificationMismatchTitle"),
                            subtitle: loc.localized("raHash.pillMismatchSubtitle")
                                .replacingOccurrences(of: "{title}", with: firstMatch?.title ?? currentROM.displayName)
                                .replacingOccurrences(of: "{system}", with: sysName),
                            actionLabel: loc.localized("raHash.viewOnRetroAchievements"),
                            actionType: "openURL",
                            actionPayload: OpenURLActionPayload(url: mismatchURL)
                        )
                        NotificationService.shared.sendNotification(
                            title: loc.localized("raHash.notificationMismatchTitle"),
                            body: loc.localized("raHash.notificationMismatchBody")
                                .replacingOccurrences(of: "{title}", with: firstMatch?.title ?? currentROM.displayName)
                                .replacingOccurrences(of: "{system}", with: sysName)
                        )
                    }
                }
            }
        }
    }

    func loadBoxArt() {
        Task { @MainActor in
            if let resolvedPath = BoxArtService.shared.resolveLocalBoxArtIfNeeded(for: currentROM, library: library) {
                boxArtImageURL = resolvedPath
                boxArtImage = await ImageCache.shared.thumbnail(for: resolvedPath, preferredSize: .large)
            } else if currentROM.hasBoxArt {
                boxArtImageURL = currentROM.boxArtLocalPath
                boxArtImage = await ImageCache.shared.thumbnail(for: currentROM.boxArtLocalPath, preferredSize: .large)
            } else {
                boxArtImageURL = nil
                boxArtImage = nil
            }
        }
    }

    func loadScreenshots() {
        Task {
            var images: [NSImage] = []
            for path in currentROM.screenshotPaths {
                if let img = await ImageCache.shared.image(for: path) {
                    images.append(img)
                }
            }
            screenshotImages = images
        }
    }

    var manualActionStatusBar: some View {
        HStack(alignment: .top, spacing: 10) {
            switch manualAction.status {
            case .hidden:
                EmptyView()
            case .working(let title):
                ProgressView().controlSize(.small)
                Text(title).font(.callout).foregroundColor(AppColors.textPrimary(colorScheme))
            case .result(let message, let tone):
                Image(systemName: tone.iconName)
                    .font(.title3)
                    .foregroundStyle(tone.foregroundColor)
                    .frame(width: 22, alignment: .center)
                Text(message)
                    .font(.callout)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if case .result = manualAction.status {
                AppIconButton(icon: "xmark.circle.fill", help: "Dismiss") {
                    manualAction.clear()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .overlay(alignment: .top) {
            Divider().overlay(AppColors.divider(colorScheme))
        }
    }

    func showManualResult(_ message: String, tone: ManualStatusTone) {
        manualAction.showResult(message, tone: tone, autoDismissAfter: 12_000_000_000)
    }

    func updateSettings(_ action: (inout ROMSettings) -> Void) {
        var updated = currentROM
        action(&updated.settings)
        #if LOG_DEBUG
        LoggerService.debug(category: "ShaderPicker", "updateSettings: about to call library.updateROM for ROM: \(updated.id), shaderPresetID: \(updated.settings.shaderPresetID)")
        #endif
        library.updateROM(updated)
    }

    func launchGame(slotToLoad: Int? = nil, progressiveVersion: Int? = nil, disableAutoLoadOnStart: Bool = false) {
        guard !isLaunchingGame else { return }
        guard let sysID = currentROM.systemID, let system = SystemDatabase.system(forID: sysID) else {
            isLaunchingGame = false
            return
        }

        // Use centralized helper to resolve core ID (handles synthetic fallback)
        let cid = coreManager.resolveCoreID(for: currentROM, system: system)
        
        // DEBUG: Log the resolved coreID
        #if LOG_DEBUG
        LoggerService.debug(category: "GameDetailView", "[LAUNCH]Helper resolved coreID: \(cid) for ROM: \(currentROM.displayName)")
        #endif
        
        if !coreManager.isInstalled(coreID: cid) {
            // DEBUG: Log that core is not installed and download is being requested
            #if LOG_DEBUG
            LoggerService.debug(category: "GameDetailView", "[LAUNCH] Core NOT installed: \(cid), initiating requestCoreDownload for ROM: \(currentROM.displayName)")
            #endif
            coreManager.requestCoreDownload(for: cid, systemID: sysID, romID: currentROM.id, slotToLoad: slotToLoad)
            // DEBUG: Log after requestCoreDownload call
            #if LOG_DEBUG
            LoggerService.debug(category: "GameDetailView", "[LAUNCH] requestCoreDownload completed, returning (isLaunchingGame=false)")
            #endif
            isLaunchingGame = false
            return
        }

        isLaunchingGame = true
        let freshROM = library.roms.first { $0.id == currentROM.id } ?? currentROM
        let currentShaderUniforms = freshROM.settings.shaderUniformOverrides
        Task {
            await gameLauncher.launchGame(rom: freshROM, coreID: cid, slotToLoad: slotToLoad, progressiveVersion: progressiveVersion, disableAutoLoadOnStart: disableAutoLoadOnStart, library: library, shaderUniformOverrides: currentShaderUniforms) { _ in
                self.isLaunchingGame = false
            }
        }
    }

    private func setupGamepadNavContext() {
        let sections = allSections
        let ctx = GamepadTwoZoneContext()
        ctx.sidebarItemCount = sections.count
        ctx.contentItemCount = 1
        let initialIndex = sections.firstIndex(of: selectedSection) ?? 0
        ctx.sidebarIndex = initialIndex
        ctx.onSelectSidebar = { [self] index in
            guard index >= 0, index < sections.count else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSection = sections[index]
            }
        }
        ctx.onDismiss = { NSApp.keyWindow?.close() }
        gamepadTwoZoneContext = ctx
        GamepadNavContextStack.shared.push(ctx)
    }

    private func teardownGamepadNavContext() {
        if let ctx = gamepadTwoZoneContext {
            GamepadNavContextStack.shared.remove(ctx)
            gamepadTwoZoneContext = nil
        }
    }
}