import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var library: ROMLibrary
    @ObservedObject private var gamepadNav = GamepadNavigationManager.shared
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @ObservedObject var sysPrefs = SystemPreferences.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openWindow) var openWindow
	var rom: ROM
	var initialSection: DetailSection?

	@StateObject var saveStateManager = SaveStateManager()
	@StateObject var achievementsService = RetroAchievementsService.shared
	@State var showBoxArtPicker = false
    @StateObject var gameLauncher = GameLauncher.shared
    @State var boxArtImage: NSImage? = nil
    @State var boxArtImageURL: URL? = nil
    @State var screenshotImages: [NSImage] = []
    @State var crcHash: String? = nil
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
    @State var manualActionStatus: ManualActionStatus = .hidden
    @State var manualStatusAutoDismiss: Task<Void, Never>?

    @State var shaderWindowSettings: ShaderWindowSettings?
    @State var selectedSection: DetailSection = .gameInfo
    @State var hoveredSection: DetailSection? = nil
    @State var bezelSelectorWindowController: BezelSelectorWindowController?
    @State var localTitle: String = ""
    @State var gameDescription: String? = nil
    @State var mostRecentSaveSlot: SlotInfo? = nil
    @State var titleScreenImage: NSImage? = nil

    @ObservedObject var loc = LocalizationManager.shared

    @State var fetchMetadataStatus: ManualActionStatus = .hidden
    @State var fetchMetadataAutoDismiss: Task<Void, Never>?
    @State var fetchBoxArtStatus: ManualActionStatus = .hidden
    @State var fetchBoxArtAutoDismiss: Task<Void, Never>?
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
@State var raVerificationStatus: ManualActionStatus = .hidden
@State var raVerificationAutoDismiss: Task<Void, Never>?
@State var raComparisonShowDownloadOption = false

    var currentROM: ROM {
        library.roms.first { $0.id == rom.id } ?? rom
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
        if case .working = manualActionStatus { return true }
        return false
    }

    var shaderManager: ShaderManager { ShaderManager.shared }
    var unlockedAchievementCount: Int { gameAchievements.filter { $0.isUnlocked }.count }
    var totalAchievementPoints: Int { gameAchievements.reduce(0) { $0 + $1.points } }
    var earnedPoints: Int { gameAchievements.filter { $0.isUnlocked }.reduce(0) { $0 + $1.points } }
    var systemDefaultShaderID: String {
        SystemDatabase.system(forID: currentROM.systemID ?? "")?.defaultShaderPresetID ?? ""
    }
    var isShaderCustomized: Bool { currentROM.settings.shaderPresetID != systemDefaultShaderID }

    @ViewBuilder
    var mainContentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AnyView(sectionContent)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(gamepadNav.isGamepadActive && gamepadTwoZoneContext?.activeZone == .content ? AppColors.brandAccent.opacity(0.4) : Color.clear, lineWidth: 2)
                .padding(2)
        )
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .gameInfo: overviewSection
        case .technical: technicalSection
        case .shader: shaderSection
        case .bezels: bezelsSection
        case .controls: controlsSection
        case .analogMouse: analogMouseSection
        case .coreOptions: coreOptionsSection
        case .savedStates: savedStatesSection
        case .cheats: cheatsSection
        case .core: coreSection
        case .achievements:
            if achievementsService.isEnabled {
                achievementsSection
            }
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
            nameMatches: raComparisonNameMatches,
            showDownloadOption: raComparisonShowDownloadOption,
            onDownload: {
                Task {
                    showRAHashComparison = false
                    try? await achievementsService.fetchAndCacheAllGames()
                    // Short delay to let the sheet dismiss before re-triggering
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    findInRA()
                }
            }
        )
    }

    var body: some View {
        GeometryReader { geo in
            let headerHeight = min(max(geo.size.height * 0.25, 150), 210)
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

                if manualActionStatus.isVisible {
                    manualActionStatusBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
            .animation(.easeInOut(duration: 0.2), value: manualActionStatus.isVisible)
        }
	.onAppear {
		if let initial = initialSection {
			selectedSection = initial
		}
		loadBoxArt()
            loadSlotInfo()
            loadMostRecentSaveState()
            loadTitleScreen()
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
    .onChange(of: currentROM.id) { _, _ in
        clearManualStatus()
        loadSlotInfo()
        loadMostRecentSaveState()
        loadTitleScreen()
        if achievementsService.isLoggedIn && achievementsService.isEnabled {
          loadAchievements()
        }
        loadAchievementViewMode()
      }
  .onChange(of: currentROM.lastPlayed) { _, _ in
            // Refresh slot info when user returns from playing the game
            loadSlotInfo()
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
        }
        .onChange(of: currentROM.hasBoxArt) { _, _ in loadBoxArt() }
.onChange(of: currentROM.hasTitleScreen) { _, _ in loadTitleScreen() }
.onChange(of: currentROM.screenshotPaths) { _, _ in loadScreenshots() }
.onChange(of: library.bezelUpdateToken) { _, _ in Task { await loadCurrentBezelImage() } }
.onChange(of: achievementViewMode) { _, newValue in
    AppSettings.setString(newValue.rawValue, value: newValue.rawValue)
    AppSettings.setString("achievementViewMode_\(currentROM.id.uuidString)", value: newValue.rawValue)
}
        .onChange(of: achievementsService.isLoggedIn) { _, _ in
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
        .sheet(isPresented: $showRAHashComparison) { raHashComparisonSheet
            .gamepadDismissable { showRAHashComparison = false }
        }
        .sheet(isPresented: $showSystemPicker) {
            SystemPickerView(roms: [currentROM], library: library) {
                showSystemPicker = false
            }
            .gamepadDismissable { showSystemPicker = false }
        }
    }

    var primarySections: [DetailSection] {
        var sections: [DetailSection] = [.gameInfo]
        sections.append(.savedStates)
        if achievementsService.isEnabled {
            sections.append(.achievements)
        }
        sections.append(contentsOf: [.cheats, .shader, .bezels, .controls])
        if let sysID = currentROM.systemID, sysID == "dos" || sysID == "scummvm" {
            sections.append(.analogMouse)
        }
        if currentROM.systemID == "gb" || currentROM.systemID == "gbc" {
            sections.append(.coreOptions)
        }
        return sections
    }

    var advancedSections: [DetailSection] {
        [.core, .technical]
    }

    var allSections: [DetailSection] {
        primarySections + advancedSections
    }

    var sidebarNavigation: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(primarySections, id: \.self) { section in
                sidebarItem(for: section)
            }

            Divider()
                .overlay(AppColors.divider(colorScheme))
                .padding(.vertical, 4)
                .padding(.horizontal, 6)

            ForEach(advancedSections, id: \.self) { section in
                sidebarItem(for: section)
            }

            Spacer()
        }
        .frame(width: 160)
        .padding(.vertical, 12)
        .padding(.leading, 8)
        .padding(.trailing, 4)
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

        return AnyView(
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedSection = section
                }
            } label: {
            HStack(spacing: 10) {
                Image(systemName: section.sectionIcon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20, height: 20)
                    .foregroundColor(isSelected ? AppColors.brandAccent : AppColors.textSecondary(colorScheme))
                Text(section.localizedTitle)
                    .font(AppTypography.subheadline)
                    .foregroundColor(isSelected ? AppColors.textPrimary(colorScheme) : AppColors.textSecondary(colorScheme))
                    .fontWeight(isSelected ? .medium : .regular)
                Spacer()
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(section.helpText)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? AppColors.accentBackground(colorScheme) : 
                          (isHovered ? AppColors.cardBackgroundSubtle(colorScheme) : .clear))
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.brandAccent)
                        .frame(width: 3, height: 20)
                        .padding(.leading, 2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isGamepadFocused ? AppColors.brandAccent : Color.clear, lineWidth: 2)
            )
            .onHover { hoveredSection = $0 ? section : nil }
        )
    }

    func loadSlotInfo() {
        let gameName = "\(currentROM.displayName)__\(currentROM.id.uuidString.prefix(8))"
        let systemID = currentROM.systemID ?? ""
        slotInfoList = saveStateManager.allSlotInfo(gameName: gameName, systemID: systemID)
        progressiveSlots = saveStateManager.allProgressiveSlots(gameName: gameName, systemID: systemID)
    }

    func loadMostRecentSaveState() {
        let gameName = "\(currentROM.displayName)__\(currentROM.id.uuidString.prefix(8))"
        let systemID = currentROM.systemID ?? ""
        mostRecentSaveSlot = saveStateManager.mostRecentSaveState(gameName: gameName, systemID: systemID)
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
        if let raGameId = currentROM.raGameId, raGameId > 0 {
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
        raComparisonShowDownloadOption = false
        raVerificationStatus = .working(loc.localized("achievement.loadingAchievements"))

        let raConsoleID = achievementsService.mapSystemIDToRAConsoleID(systemID)
        let sysName = systemName

        guard raConsoleID > 0 else {
            raComparisonError = "This system is not supported by RetroAchievements"
            isFindingRAGame = false
            showRAHashComparison = true
            raVerificationStatus = .hidden
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
                    raVerificationStatus = .hidden
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
                        raVerificationStatus = .result(loc.localized("achievement.romVerified"), tone: .success)
                        raVerificationAutoDismiss?.cancel()
                        raVerificationAutoDismiss = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            guard !Task.isCancelled else { return }
                            raVerificationStatus = .hidden
                        }
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
                        raVerificationStatus = .result(loc.localized("achievement.romMatchedNoAchievements"), tone: .info)
                        raVerificationAutoDismiss?.cancel()
                        raVerificationAutoDismiss = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 6_000_000_000)
                            guard !Task.isCancelled else { return }
                            raVerificationStatus = .hidden
                        }
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
                // Check if the real problem is missing hash data
                let needsDownload = achievementsService.needsHashDownload()
                if needsDownload {
                    await MainActor.run {
                        raComparisonShowDownloadOption = true
                        isFindingRAGame = false
                        raVerificationStatus = .hidden
                        showRAHashComparison = true
                    }
                    return
                }

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
                    raVerificationStatus = .hidden
                    raComparisonShowDownloadOption = false
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
        Task {
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
            switch manualActionStatus {
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
            if case .result = manualActionStatus {
                Button {
                    clearManualStatus()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppColors.textMuted(colorScheme))
                }
                .buttonStyle(.plain)
                .help("Dismiss")
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

    func clearManualStatus() {
        manualStatusAutoDismiss?.cancel()
        manualStatusAutoDismiss = nil
        manualActionStatus = .hidden
    }

    func showManualResult(_ message: String, tone: ManualStatusTone) {
        manualStatusAutoDismiss?.cancel()
        manualActionStatus = .result(message, tone: tone)
        manualStatusAutoDismiss = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            if case .result = manualActionStatus {
                manualActionStatus = .hidden
            }
        }
    }

    func updateSettings(_ action: (inout ROMSettings) -> Void) {
        var updated = currentROM
        action(&updated.settings)
        #if LOG_DEBUG
        LoggerService.debug(category: "ShaderPicker", "updateSettings: about to call library.updateROM for ROM: \(updated.id), shaderPresetID: \(updated.settings.shaderPresetID)")
        #endif
        library.updateROM(updated)
    }

    func launchGame(slotToLoad: Int? = nil, progressiveVersion: Int? = nil) {
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
            await gameLauncher.launchGame(rom: freshROM, coreID: cid, slotToLoad: slotToLoad, progressiveVersion: progressiveVersion, library: library, shaderUniformOverrides: currentShaderUniforms) { _ in
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
        ctx.ownedWindow = NSApp.keyWindow
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