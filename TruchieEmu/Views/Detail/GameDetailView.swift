import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @ObservedObject var sysPrefs = SystemPreferences.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var rom: ROM

    @StateObject var saveStateManager = SaveStateManager()
    @StateObject var achievementsService = RetroAchievementsService.shared
    @State var showBoxArtPicker = false
    @State var showControlsPicker = false
    @StateObject var gameLauncher = GameLauncher.shared
    @State var boxArtImage: NSImage? = nil
    @State var screenshotImages: [NSImage] = []
    @State var crcHash: String? = nil
    @State var fileSize: String? = nil
    @State var slotInfoList: [SlotInfo] = []
    @State var gameAchievements:[Achievement] = []
    @State var isAchievementsLoading = false
    @State var showImportCheatFile = false
    @State var gbColorizationEnabled: Bool = true
    @State var gbColorizationMode: String = "auto"
    @State var gbInternalPalette: String = "GB - DMG"
    @State var gbSGBBordersEnabled: Bool = true
    @State var gbColorCorrectionMode: String = "gbc_only"

    @State var useCustomCore: Bool = false
    @State var selectedCoreID: String? = nil
    @State var applyCoreToSystem: Bool = false
    @State var infoCoreID: String? = nil
    @State var infoApplyCoreToSystem: Bool = false
    @State var manualActionStatus: ManualActionStatus = .hidden
    @State var manualStatusAutoDismiss: Task<Void, Never>?

    @State var shaderWindowSettings: ShaderWindowSettings?
    @State var selectedSection: DetailSection = .gameInfo
    @State var bezelSelectorWindowController: BezelSelectorWindowController?
    @State var localTitle: String = ""
    @State var gameDescription: String? = nil

    @State var fetchMetadataStatus: ManualActionStatus = .hidden
    @State var fetchMetadataAutoDismiss: Task<Void, Never>?
    @State var fetchBoxArtStatus: ManualActionStatus = .hidden
    @State var fetchBoxArtAutoDismiss: Task<Void, Never>?
    @State var currentBezelImage: NSImage? = nil
    @StateObject var cheatManagerService = CheatManagerService.shared
    @StateObject var cheatDownloadService = CheatDownloadService.shared
    @State var cheatCount: Int = 0
    @State var enabledCheatCount: Int = 0
    @State var downloadMessage: String? = nil
    @State var downloadMessageTone: ManualStatusTone = .info
    @State var cheatsList: [Cheat] = []
    @State var cheatSearchText: String = ""
    @State var isLaunchingGame = false

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
    var systemDefaultShaderID: String { "" }
    var isShaderCustomized: Bool { currentROM.settings.shaderPresetID != systemDefaultShaderID }

    var body: some View {
        VStack(spacing: 0) {
            compactHeaderSection

            Divider()
                .overlay(AppColors.divider(colorScheme))

            HStack(spacing: 0) {
                sidebarNavigation

                Divider()
                    .overlay(AppColors.divider(colorScheme))

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedSection {
                        case .gameInfo: gameInfoSection
                        case .shader: shaderSection
                        case .bezels: bezelsSection
                        case .controls: controlsSection
                        case .savedStates: savedStatesSection
                        case .cheats: cheatsSection
                        case .core: coreSection
                        case .achievements:
                            if achievementsService.isEnabled {
                                achievementsSection
                            }
                        }
                    }
                    .padding(24)
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .frame(maxHeight: .infinity)

            if manualActionStatus.isVisible {
                manualActionStatusBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(AppColors.windowBackground(colorScheme))
        .animation(.easeInOut(duration: 0.2), value: manualActionStatus.isVisible)
        .onAppear {
            loadBoxArt()
            loadSlotInfo()
            loadAchievements()
            useCustomCore = currentROM.useCustomCore
            selectedCoreID = currentROM.selectedCoreID ?? sysPrefs.preferredCoreID(for: currentROM.systemID ?? "") ?? system?.defaultCoreID
            infoCoreID = currentROM.selectedCoreID ?? sysPrefs.preferredCoreID(for: currentROM.systemID ?? "") ?? system?.defaultCoreID
            infoApplyCoreToSystem = !currentROM.useCustomCore
            gbColorizationEnabled = currentROM.settings.gbColorizationEnabled
            gbColorizationMode = currentROM.settings.gbColorizationMode
            gbInternalPalette = currentROM.settings.gbInternalPalette
            gbSGBBordersEnabled = currentROM.settings.gbSGBBordersEnabled
            gbColorCorrectionMode = currentROM.settings.gbColorCorrectionMode
        }
        .onChange(of: currentROM.id) { _, _ in
            clearManualStatus()
            loadSlotInfo()
            loadAchievements()
        }
        .task(id: currentROM.id) {
            if currentROM.systemID == "mame" || currentROM.systemID == "arcade" {
                await MAMEUnifiedService.shared.ensureLoaded()
                let shortName = currentROM.shortNameForMAME
                if let unifiedEntry = await MAMEUnifiedService.shared.lookup(shortName: shortName) {
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
            if let crc = ROMIdentifierService.shared.computeCRC(for: currentROM.path, systemID: currentROM.systemID ?? "") {
                crcHash = crc
            }
        }
        .onChange(of: currentROM.hasBoxArt) { _, _ in loadBoxArt() }
        .onChange(of: currentROM.screenshotPaths) { _, _ in loadScreenshots() }
        .onChange(of: library.bezelUpdateToken) { _, _ in Task { await loadCurrentBezelImage() } }
        .onChange(of: achievementsService.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                loadAchievements()
            } else {
                gameAchievements = []
                isAchievementsLoading = false
            }
        }
        .onChange(of: achievementsService.isEnabled) { _, isEnabled in
            if isEnabled {
                loadAchievements()
            } else {
                gameAchievements = []
                isAchievementsLoading = false
            }
        }
        .onChange(of: achievementsService.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                loadAchievements()
            }
        }
        .onChange(of: achievementsService.isEnabled) { _, isEnabled in
            if isEnabled {
                loadAchievements()
            }
        }
        .sheet(isPresented: $showBoxArtPicker) { BoxArtPickerView(rom: currentROM) }
        .sheet(isPresented: $showControlsPicker) {
            SystemControlsMappingView(systemID: currentROM.systemID ?? "", systemName: system?.name ?? "Unknown")
                .environmentObject(controllerService)
        }
    }

    var sidebarNavigation: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DetailSection.allCases, id: \.self) { section in
                sidebarItem(for: section)
            }
            Spacer()
        }
        .frame(width: 180)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(AppColors.sidebarBackground)
    }

    func sidebarItem(for section: DetailSection) -> some View {
        let isSelected = selectedSection == section
        let showAchievements = achievementsService.isEnabled

        if section == .achievements && !showAchievements {
            return AnyView(EmptyView())
        }

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
                        .foregroundColor(isSelected ? .accentColor : AppColors.textSecondary(colorScheme))
                    Text(section.rawValue)
                        .lineLimit(1)
                        .foregroundColor(isSelected ? AppColors.textPrimary(colorScheme) : AppColors.textSecondary(colorScheme))
                        .fontWeight(isSelected ? .medium : .regular)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(section.helpText)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? AppColors.accentBackground(colorScheme) : .clear)
            )
        )
    }

    func loadSlotInfo() {
        let gameName = currentROM.displayName
        let systemID = currentROM.systemID ?? ""
        slotInfoList = saveStateManager.allSlotInfo(gameName: gameName, systemID: systemID)
    }

    @MainActor
    func loadAchievements() {
        guard achievementsService.isEnabled else { return }
        guard achievementsService.isLoggedIn else { return }
        isAchievementsLoading = true
        gameAchievements = []
        let hash = ROMIdentifierService.shared.computeCRC(for: currentROM.path, systemID: currentROM.systemID ?? "")
        if let hash = hash {
            Task {
                do {
                    let gameInfo = try await achievementsService.identifyGame(hash: hash)
                    await MainActor.run {
                        if let gameInfo = gameInfo {
                            achievementsService.currentGame = gameInfo
                            gameAchievements = gameInfo.achievements
                        } else {
                            gameAchievements = []
                        }
                        isAchievementsLoading = false
                    }
                } catch {
                    await MainActor.run {
                        LoggerService.debug(category: "Achievements", "Failed to load achievements: \(error.localizedDescription)")
                        gameAchievements = []
                        isAchievementsLoading = false
                    }
                }
            }
        } else {
            isAchievementsLoading = false
        }
    }

    func loadBoxArt() {
        if let resolvedPath = BoxArtService.shared.resolveLocalBoxArtIfNeeded(for: currentROM, library: library) {
            boxArtImage = NSImage(contentsOf: resolvedPath)
        } else if currentROM.hasBoxArt {
            boxArtImage = NSImage(contentsOf: currentROM.boxArtLocalPath)
        } else {
            boxArtImage = nil
        }
    }

    func loadScreenshots() {
        screenshotImages = currentROM.screenshotPaths.compactMap { NSImage(contentsOf: $0) }
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
        .background(AppColors.surface(colorScheme))
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
        library.updateROM(updated)
    }

    func launchGame(slotToLoad: Int? = nil) {
        guard !isLaunchingGame else { return }
        guard let sysID = currentROM.systemID, let system = SystemDatabase.system(forID: sysID) else {
            isLaunchingGame = false
            return
        }

        let sysPrefs = SystemPreferences.shared
        let coreID = currentROM.useCustomCore
            ? (currentROM.selectedCoreID ?? sysPrefs.preferredCoreID(for: sysID) ?? system.defaultCoreID)
            : (sysPrefs.preferredCoreID(for: sysID) ?? system.defaultCoreID)

        guard let cid = coreID else {
            isLaunchingGame = false
            return
        }

        if !coreManager.isInstalled(coreID: cid) {
            coreManager.requestCoreDownload(for: cid, systemID: sysID, romID: currentROM.id, slotToLoad: slotToLoad)
            isLaunchingGame = false
            return
        }

        isLaunchingGame = true
        gameLauncher.launchGame(rom: currentROM, coreID: cid, slotToLoad: slotToLoad, library: library) { _ in
            self.isLaunchingGame = false
        }
    }
}