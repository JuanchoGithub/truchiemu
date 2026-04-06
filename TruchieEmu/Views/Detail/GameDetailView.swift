import SwiftUI

// MARK: - Light/Dark Theme Color Tokens

/// Centralized color tokens for GameDetailView — works in both light and dark mode.
/// Prevents hardcoded `.white.opacity(x)` colors that break in light mode.
private struct ThemeColors {
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textMuted: Color
    let divider: Color
    let cardBackground: Color
    let cardBackgroundSubtle: Color
    let cardBorder: Color
    let iconPrimary: Color
    let iconSecondary: Color
    let iconMuted: Color
    let sidebarBackground: Color
    let headerBackground: Color
    let buttonBackground: Color
    let pillBackground: Color
    let pillBackgroundSubtle: Color
    let slotBackground: Color
    let slotBackgroundActive: Color
    let statusBackground: Color
    
    init(colorScheme: ColorScheme) {
        let isDark = colorScheme == .dark
        textPrimary = isDark ? .white.opacity(0.85) : .primary
        textSecondary = isDark ? .white.opacity(0.5) : .secondary
        textTertiary = isDark ? .white.opacity(0.4) : .secondary.opacity(0.7)
        textMuted = isDark ? .white.opacity(0.3) : .secondary.opacity(0.5)
        divider = isDark ? .white.opacity(0.08) : .secondary.opacity(0.15)
        cardBackground = isDark ? .white.opacity(0.06) : .secondary.opacity(0.05)
        cardBackgroundSubtle = isDark ? .white.opacity(0.03) : .secondary.opacity(0.03)
        cardBorder = isDark ? .white.opacity(0.1) : .secondary.opacity(0.12)
        iconPrimary = isDark ? .white.opacity(0.7) : .secondary
        iconSecondary = isDark ? .white.opacity(0.5) : .secondary
        iconMuted = isDark ? .white.opacity(0.3) : .secondary.opacity(0.5)
        sidebarBackground = isDark ? .white.opacity(0.03) : .secondary.opacity(0.03)
        headerBackground = isDark ? .black.opacity(0.5) : .secondary.opacity(0.08)
        buttonBackground = isDark ? .white.opacity(0.1) : .secondary.opacity(0.12)
        pillBackground = isDark ? .white.opacity(0.1) : .secondary.opacity(0.1)
        pillBackgroundSubtle = isDark ? .white.opacity(0.06) : .secondary.opacity(0.06)
        slotBackground = isDark ? .white.opacity(0.05) : .secondary.opacity(0.04)
        slotBackgroundActive = isDark ? .blue.opacity(0.2) : .blue.opacity(0.1)
        statusBackground = isDark ? .black.opacity(0.5) : .secondary.opacity(0.08)
    }
    
    static func `for`(_ colorScheme: ColorScheme) -> ThemeColors {
        ThemeColors(colorScheme: colorScheme)
    }
}

// MARK: - Manual Status Tone

private enum ManualStatusTone: Equatable {
    case success, info, warning, error

    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

private enum ManualActionStatus: Equatable {
    case hidden
    case working(String)
    case result(String, tone: ManualStatusTone)

    var isVisible: Bool {
        switch self {
        case .hidden: return false
        default: return true
        }
    }
}

// MARK: - Detail Sections

enum DetailSection: String, CaseIterable {
    case gameInfo = "Game Info"
    case shader = "Shader"
    case bezels = "Bezels"
    case controls = "Controls"
    case savedStates = "Saved States"
    case cheats = "Cheats"
    case core = "Core"
    case achievements = "Achievements"
    
    /// Plain-language description of what each section does, shown as tooltip
    var helpText: String {
        switch self {
        case .gameInfo:
            return "View game details, metadata, and metadata identification tools"
        case .shader:
            return "Customize visual effects like CRT filters and screen smoothing"
        case .bezels:
            return "Browse and apply decorative bezel artwork around the game screen"
        case .controls:
            return "View and customize keyboard and controller button mappings"
        case .savedStates:
            return "Manage save states created during gameplay — load or delete saves"
        case .cheats:
            return "Download, enable, and manage cheat codes for this game"
        case .core:
            return "Choose which emulation engine to use for this game or system"
        case .achievements:
            return "View RetroAchievements — earn points by completing in-game challenges"
        }
    }
    
    /// SF Symbol icon for the section header (larger)
    var headerIcon: String {
        return sectionIcon
    }
    
    /// SF Symbol icon used in sidebar navigation
    var sectionIcon: String {
        switch self {
        case .gameInfo: return "info.circle"
        case .shader: return "display"
        case .bezels: return "photo.on.rectangle.angled"
        case .controls: return "gamecontroller"
        case .savedStates: return "externaldrive"
        case .cheats: return "wand.and.stars"
        case .core: return "cpu"
        case .achievements: return "trophy"
        }
    }
}

// MARK: - Modern Section Card Component (Non-collapsible)

struct ModernSectionCard<Content: View>: View {
    let title: String?
    let icon: String?
    var badge: String? = nil
    var showHeader: Bool = true
    @ViewBuilder let content: Content
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        title: String? = nil,
        icon: String? = nil,
        badge: String? = nil,
        showHeader: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.showHeader = showHeader
        self.content = content()
    }
    
    private var sectionTitleColor: Color {
        colorScheme == .dark ? .white.opacity(0.6) : .primary.opacity(0.6)
    }
    
    private var sectionIconColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .secondary
    }
    
    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.secondary.opacity(0.2)
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : .secondary.opacity(0.05)
    }
    
    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : .secondary.opacity(0.15)
    }
    
    /// Accent badge color — adapts for light mode readability
    private var badgeBackground: Color {
        colorScheme == .dark ? Color.blue.opacity(0.3) : .blue.opacity(0.15)
    }
    private var badgeForeground: Color {
        colorScheme == .dark ? .white : .blue
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader, let title = title {
                HStack(spacing: 10) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundColor(sectionIconColor)
                            .font(.body)
                    }
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(sectionTitleColor)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    if let badge = badge {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badgeBackground)
                            .foregroundColor(badgeForeground)
                            .cornerRadius(6)
                    }
                    Spacer()
                }
                
                Divider()
                    .padding(.vertical, 10)
                    .overlay(dividerColor)
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Metadata Row Component

struct MetadataRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false
    var copyAction: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var labelColor: Color {
        colorScheme == .dark ? .white.opacity(0.4) : .secondary
    }
    
    private var valueColor: Color {
        colorScheme == .dark ? .white.opacity(0.85) : .primary
    }
    
    private var copyButtonColor: Color {
        colorScheme == .dark ? .white.opacity(0.4) : .secondary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(labelColor)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.body)
                .foregroundColor(valueColor)
                .lineLimit(2)
                .truncationMode(.middle)
                .font(isMonospaced ? .body.monospaced() : .body)
            
            Spacer()
            
            if copyAction != nil {
                Button(action: copyAction!) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(copyButtonColor)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Copy")
            }
        }
    }
}

// MARK: - Game Detail View

struct GameDetailView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @ObservedObject var sysPrefs = SystemPreferences.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var rom: ROM
    
    /// Theme-aware color tokens for this view
    private var t: ThemeColors { ThemeColors.for(colorScheme) }
    
    /// Text color that adapts for light/dark mode
    private var textColor: Color { colorScheme == .dark ? .white : .primary }
    private var secondaryTextColor: Color { colorScheme == .dark ? .white.opacity(0.7) : .secondary }
    private var tertiaryTextColor: Color { colorScheme == .dark ? .white.opacity(0.5) : .secondary }
    private var mutedTextColor: Color { colorScheme == .dark ? .white.opacity(0.4) : .secondary.opacity(0.7) }
    private var subtleColor: Color { colorScheme == .dark ? .white.opacity(0.3) : .secondary.opacity(0.5) }
    private var iconColor: Color { colorScheme == .dark ? .white.opacity(0.5) : .secondary }
    private var mutedIconColor: Color { colorScheme == .dark ? .white.opacity(0.3) : .secondary.opacity(0.5) }
    private var dividerColor: Color { colorScheme == .dark ? .white.opacity(0.08) : .secondary.opacity(0.15) }
    private var cardBgColor: Color { colorScheme == .dark ? .white.opacity(0.06) : .secondary.opacity(0.05) }
    private var subtleBgColor: Color { colorScheme == .dark ? .white.opacity(0.03) : .secondary.opacity(0.03) }
    private var buttonBgColor: Color { colorScheme == .dark ? .white.opacity(0.1) : .secondary.opacity(0.12) }
    private var subtleButtonBgColor: Color { colorScheme == .dark ? .white.opacity(0.06) : .secondary.opacity(0.06) }
    private var pillBgColor: Color { colorScheme == .dark ? .white.opacity(0.1) : .secondary.opacity(0.1) }

    // Section state
    @StateObject private var saveStateManager = SaveStateManager()
    @StateObject private var achievementsService = RetroAchievementsService.shared
    @State private var showBoxArtPicker = false
    @State private var showControlsPicker = false
    @StateObject private var gameLauncher = GameLauncher.shared
    @State private var boxArtImage: NSImage? = nil
    @State private var screenshotImages: [NSImage] = []
    @State private var crcHash: String? = nil
    @State private var fileSize: String? = nil
    @State private var slotInfoList: [SlotInfo] = []
    @State private var gameAchievements: [Achievement] = []
    @State private var isAchievementsLoading = false
    @State private var showCheatManager = false
    @State private var showImportCheatFile = false
    @State private var gbColorizationEnabled: Bool = true
    @State private var gbColorizationMode: String = "auto"
    @State private var gbInternalPalette: String = "GB - DMG"
    @State private var gbSGBBordersEnabled: Bool = true
    @State private var gbColorCorrectionMode: String = "gbc_only"

    @State private var useCustomCore: Bool = false
    @State private var selectedCoreID: String? = nil
    @State private var applyCoreToSystem: Bool = false
    @State private var infoCoreID: String? = nil
    @State private var infoApplyCoreToSystem: Bool = false
    @State private var manualActionStatus: ManualActionStatus = .hidden
    @State private var manualStatusAutoDismiss: Task<Void, Never>?
    
    @State private var shaderWindowSettings: ShaderWindowSettings?
    @State private var selectedSection: DetailSection = .gameInfo
    @State private var bezelSelectorWindowController: BezelSelectorWindowController?

    private var currentROM: ROM {
        library.roms.first { $0.id == rom.id } ?? rom
    }

    private var system: SystemInfo? {
        SystemDatabase.displaySystem(forInternalID: currentROM.systemID ?? "")
    }

    /// The effective core ID used to launch this ROM. Used by GB colorization UI.
    private var activeCoreID: String? {
        guard let sysID = currentROM.systemID, let sys = SystemDatabase.system(forID: sysID) else { return system?.defaultCoreID }
        if currentROM.useCustomCore, let sel = currentROM.selectedCoreID { return sel }
        return sysPrefs.preferredCoreID(for: sysID) ?? sys.defaultCoreID
    }
    
    /// Returns true when the active core for this ROM is Gambatte (which supports named internal palettes and color correction).
    private var isGambatteCore: Bool {
        (activeCoreID ?? "").lowercased().contains("gambatte")
    }

    private var installedCores: [LibretroCore] {
        guard let sysID = currentROM.systemID else { return [] }
        return coreManager.installedCores.filter { $0.systemIDs.contains(sysID) }
    }

    private var isIdentifyWorking: Bool {
        if case .working = manualActionStatus { return true }
        return false
    }

    // Shader helpers
    private var shaderManager: ShaderManager { ShaderManager.shared }

    // Achievements helpers
    private var unlockedAchievementCount: Int { gameAchievements.filter { $0.isUnlocked }.count }
    private var totalAchievementPoints: Int { gameAchievements.reduce(0) { $0 + $1.points } }
    private var earnedPoints: Int { gameAchievements.filter { $0.isUnlocked }.reduce(0) { $0 + $1.points } }

    // System default shader
    private var systemDefaultShaderID: String { "builtin-crt-classic" }
    private var isShaderCustomized: Bool {
        currentROM.settings.shaderPresetID != systemDefaultShaderID
    }

    var body: some View {
        ZStack {
            // Immersive Background - Blurred box art
            immersiveBackground
            
            // Main content overlay
            VStack(spacing: 0) {
                // Header always visible
                compactHeaderSection
                
                Divider()
                    .overlay(dividerColor)

                // Sidebar + Content layout
                HStack(spacing: 0) {
                    // Sidebar with glassmorphism
                    sidebarNavigation

                    Divider()
                        .overlay(dividerColor)

                    // Main content area - fill remaining space
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            switch selectedSection {
                            case .gameInfo:
                                gameInfoSection
                            case .shader:
                                shaderSection
                            case .bezels:
                                bezelsSection
                            case .controls:
                                controlsSection
                            case .savedStates:
                                savedStatesSection
                            case .cheats:
                                cheatsSection
                            case .core:
                                coreSection
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
        }
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
        .onChange(of: currentROM.boxArtPath) { _, _ in loadBoxArt() }
        .onChange(of: currentROM.screenshotPaths) { _, _ in loadScreenshots() }
        .onChange(of: library.bezelUpdateToken) { _, _ in
            Task { await loadCurrentBezelImage() }
        }
        .sheet(isPresented: $showBoxArtPicker) {
            BoxArtPickerView(rom: currentROM)
        }
        .sheet(isPresented: $showControlsPicker) {
            SystemControlsMappingView(
                systemID: currentROM.systemID ?? "",
                systemName: system?.name ?? "Unknown"
            )
            .environmentObject(controllerService)
        }
        .sheet(isPresented: $showCheatManager) {
            CheatManagerView(rom: currentROM)
                .frame(minWidth: 500, minHeight: 600)
        }
    }

    // MARK: - Immersive Background

    private var immersiveBackground: some View {
        GeometryReader { geo in
            ZStack {
                // Deep charcoal base
                Color(red: 0.12, green: 0.13, blue: 0.16)
                
                // Blurred box art overlay
                if let img = boxArtImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 60, opaque: false)
                        .scaleEffect(1.1)
                        .opacity(0.25)
                }
            }
        }
    }

    // MARK: - Sidebar Navigation (Glassmorphism)

    private var sidebarNavigation: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DetailSection.allCases, id: \.self) { section in
                sidebarItem(for: section)
            }

            Spacer()
        }
        .frame(width: 180)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(t.sidebarBackground)
    }

    private func sidebarItem(for section: DetailSection) -> some View {
        let isSelected = selectedSection == section
        let showAchievements = achievementsService.isEnabled

        // Skip achievements if disabled
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
                        .foregroundColor(isSelected ? .blue : t.iconPrimary)
                    Text(section.rawValue)
                        .lineLimit(1)
                        .foregroundColor(isSelected ? t.textPrimary : t.textSecondary)
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
                    .fill(isSelected ? Color.blue.opacity(0.2) : .clear)
            )
        )
    }

    // MARK: - Data Loading

    private func loadSlotInfo() {
        let gameName = currentROM.displayName
        let systemID = currentROM.systemID ?? ""
        slotInfoList = saveStateManager.allSlotInfo(gameName: gameName, systemID: systemID)
    }

    @MainActor
    private func loadAchievements() {
        guard achievementsService.isEnabled else { return }
        guard achievementsService.isLoggedIn else { return }
        
        isAchievementsLoading = true
        gameAchievements = []
        
        // Compute CRC hash for the ROM
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

    private func loadBoxArt() {
        // Lazy-resolve local boxart on-demand if not already set
        if let resolvedPath = BoxArtService.shared.resolveLocalBoxArtIfNeeded(for: currentROM, library: library) {
            boxArtImage = NSImage(contentsOf: resolvedPath)
        } else if let path = currentROM.boxArtPath {
            boxArtImage = NSImage(contentsOf: path)
        } else {
            boxArtImage = nil
        }
    }

    private func loadScreenshots() {
        screenshotImages = currentROM.screenshotPaths.compactMap { NSImage(contentsOf: $0) }
    }

    // MARK: - Manual Action Status

    private var manualActionStatusBar: some View {
        HStack(alignment: .top, spacing: 10) {
            switch manualActionStatus {
            case .hidden:
                EmptyView()
            case .working(let title):
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.85))
            case .result(let message, let tone):
                Image(systemName: tone.iconName)
                    .font(.title3)
                    .foregroundStyle(tone.foregroundColor)
                    .frame(width: 22, alignment: .center)
                Text(message)
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if case .result = manualActionStatus {
                Button {
                    clearManualStatus()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.5))
        .overlay(alignment: .top) {
            Divider()
                .overlay(dividerColor)
        }
    }

    private func clearManualStatus() {
        manualStatusAutoDismiss?.cancel()
        manualStatusAutoDismiss = nil
        manualActionStatus = .hidden
    }

    private func showManualResult(_ message: String, tone: ManualStatusTone) {
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

    // MARK: - Top Header Panel (160px fixed height)

    private var compactHeaderSection: some View {
        HStack(alignment: .center, spacing: 20) {
            // Left side: Launch button + Game info
            VStack(alignment: .leading, spacing: 12) {
                // Game title with year
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("Game Title", text: Binding(
                        get: { currentROM.customName ?? currentROM.metadata?.title ?? currentROM.name },
                        set: { newName in
                            var updated = currentROM
                            updated.customName = newName.isEmpty ? nil : newName
                            library.updateROM(updated)
                        }
                    ))
                    .font(.title.bold())
                    .foregroundColor(t.textPrimary)
                    .textFieldStyle(.plain)
                    
                    if let year = currentROM.metadata?.year {
                        Text("(\(year))")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(t.textSecondary)
                    }
                    
                    Spacer()
                }
                
                // System badge
                if let sys = system {
                    HStack(spacing: 8) {
                        if let emuImg = sys.emuImage(size: 132) {
                            Image(nsImage: emuImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                        }
                        Text(sys.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(t.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(t.pillBackgroundSubtle)
                    .cornerRadius(6)
                }
                
                Spacer()
                
                // Launch button moved to left side
                launchButton
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right side: Box art images (clear + blurred)
            HStack(spacing: 12) {
                // Clear box art (main image) - now zoomable
                DetailBoxArtButton(
                    image: boxArtImage,
                    placeholder: { AnyView(placeholderArt) }
                )
                .frame(width: 110, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: Color.black.opacity(0.5), radius: 10, y: 4)
                .contextMenu {
                    Button {
                        showBoxArtPicker = true
                    } label: {
                        Label("Change Box Art", systemImage: "photo")
                    }
                }
                
                // Blurred version as decorative accent
                ZStack {
                    if let img = boxArtImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 8)
                            .opacity(0.6)
                    } else {
                        placeholderArt
                    }
                }
                .frame(width: 80, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(height: 160)
    }

    // MARK: - Section 1: Game Info

    private var gameInfoSection: some View {
        VStack(spacing: 16) {
            // Action buttons row
            HStack(spacing: 12) {
                identifyButton
                fetchBoxArtButton
                fetchMetadataButton
            }
            
            // Screenshots row
            if !screenshotImages.isEmpty {
                screenshotsRow
            }
            
            // Metadata card
            ModernSectionCard(showHeader: false) {
                VStack(alignment: .leading, spacing: 14) {
                    MetadataRow(label: "System", value: system?.name ?? currentROM.systemID ?? "Not identified")
                    
                    Divider().overlay(dividerColor)
                    
                    MetadataRow(label: "File Name", value: currentROM.path.lastPathComponent)
                    
                    Divider().overlay(dividerColor)
                    
                    MetadataRow(
                        label: "Path",
                        value: currentROM.path.deletingLastPathComponent().path,
                        copyAction: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(currentROM.path.path, forType: .string)
                        }
                    )
                    
                    if let size = fileSize {
                        Divider().overlay(dividerColor)
                        MetadataRow(label: "File Size", value: size)
                    }

                    if let crc = crcHash {
                        Divider().overlay(dividerColor)
                        MetadataRow(
                            label: "CRC32",
                            value: crc,
                            isMonospaced: true,
                            copyAction: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(crc, forType: .string)
                            }
                        )
                    }

                    // Additional metadata
                    if let meta = currentROM.metadata {
                        if let original = meta.title, currentROM.customName != nil {
                            Divider().overlay(dividerColor)
                            MetadataRow(label: "Original Name", value: original)
                        }
                        if let dev = meta.developer {
                            Divider().overlay(dividerColor)
                            MetadataRow(label: "Developer", value: dev)
                        }
                        if let pub = meta.publisher {
                            Divider().overlay(dividerColor)
                            MetadataRow(label: "Publisher", value: pub)
                        }
                        if let genre = meta.genre {
                            Divider().overlay(dividerColor)
                            MetadataRow(label: "Genre", value: genre)
                        }
                        Divider().overlay(dividerColor)
                        MetadataRow(label: "Players", value: String(meta.players))
                        Divider().overlay(dividerColor)
                        MetadataRow(label: "Co-op", value: meta.cooperative ? "Yes" : "No")
                        if let esrb = meta.esrbRating {
                            Divider().overlay(dividerColor)
                            HStack(alignment: .top, spacing: 16) {
                                Text("ESRB".uppercased())
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.4))
                                    .frame(width: 100, alignment: .leading)
                                Text(esrb)
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white.opacity(0.85))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(esrbBadgeColor(for: esrb))
                                    .cornerRadius(6)
                                Spacer()
                            }
                        }
                    }
                }
            }



            // Core selection (Game Info quick access)
            coreInfoSection
            
            // MAME dependency status (only for MAME games)
            if currentROM.systemID == "mame" || currentROM.systemID == "arcade" {
                MAMEDependencyStatusView(rom: currentROM, coreID: activeCoreID)
            }
            
            // Game Boy Colorization (only for GB system)
            if currentROM.systemID == "gb" || currentROM.systemID == "gbc" {
                gbColorizationSection
            }

            // Description card
            if let desc = currentROM.metadata?.description {
                ModernSectionCard(showHeader: false) {
                    Text(desc)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    // MARK: - Core Info Section (Game Info quick access)

    private var coreInfoSection: some View {
        ModernSectionCard(title: "Core", icon: "chip") {
            VStack(alignment: .leading, spacing: 12) {
                // Core picker row
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.white.opacity(0.5))
                    Text("Emulation Core")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.caption)
                    Spacer()
                    if installedCores.isEmpty {
                        Text("No cores installed")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.3))
                    } else {
                        Picker("Core", selection: $infoCoreID) {
                            ForEach(installedCores) { core in
                                Text(core.metadata.displayName).tag(core.id as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220)
                        .onChange(of: infoCoreID) { _, _ in
                            // Update the label to show override vs system default
                        }
                    }
                }

                Divider().overlay(dividerColor)

                // Apply to system toggle
                Toggle(isOn: $infoApplyCoreToSystem) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.white.opacity(0.5))
                        Text("Apply to system default")
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                if infoApplyCoreToSystem {
                    Text("This will change the default core for all \(systemName) games. The current game will no longer use a custom core override.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .lineSpacing(2)
                } else {
                    Text("Only this game will use the selected core.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .lineSpacing(2)
                }

                Divider().overlay(dividerColor)

                // Apply button
                HStack {
                    Spacer()
                    Button {
                        applyCoreConfigurationFromInfo()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: infoApplyCoreToSystem ? "globe" : "gamecontroller")
                            Text(infoApplyCoreToSystem ? "Set System Default" : "Set for This Game")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(infoCoreID == nil || installedCores.isEmpty)
                }
            }
        }
    }

    private func applyCoreConfigurationFromInfo() {
        guard let sysID = currentROM.systemID,
              let coreID = infoCoreID,
              !coreID.isEmpty else { return }

        if infoApplyCoreToSystem {
            // Apply as system default: remove per-game override, set system preference
            sysPrefs.setPreferredCoreID(coreID, for: sysID)

            // Clear per-game custom core
            var updated = currentROM
            updated.useCustomCore = false
            updated.selectedCoreID = nil
            library.updateROM(updated)

            // Reset local state to reflect system default
            useCustomCore = false
            infoApplyCoreToSystem = true
        } else {
            // Apply as per-game override
            var updated = currentROM
            updated.useCustomCore = true
            updated.selectedCoreID = coreID
            library.updateROM(updated)

            useCustomCore = true
            infoApplyCoreToSystem = false
        }
    }

    // MARK: - Game Boy Colorization Section

    private var gbColorizationSection: some View {
        ModernSectionCard(title: "Game Boy Colorization", icon: "paintpalette") {
            VStack(alignment: .leading, spacing: 12) {
                // Enable/Disable Toggle
                Toggle(isOn: Binding(
                    get: { gbColorizationEnabled },
                    set: { newValue in
                        gbColorizationEnabled = newValue
                        applyGBColorizationSettings()
                    }
                )) {
                    HStack {
                        Image(systemName: "paintpalette.fill")
                            .foregroundColor(.purple)
                        Text("Enable Colorization")
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                if gbColorizationEnabled {
                    Divider().overlay(dividerColor)

                    // Palette Mode Picker
                    gbPaletteModeRow

                    // Internal Palette Selector (always shown, disabled for non-Gambatte cores)
                    if gbColorizationMode == "internal" {
                        Divider().overlay(dividerColor)
                        if isGambatteCore {
                            gbInternalPaletteRow
                        } else {
                            gbInternalPaletteRow
                                .opacity(0.4)
                                .disabled(true)
                                .help("Gambatte core only — switch to gambatte_libretro to use named palettes")
                        }
                    }

                    // SGB Borders toggle (works with mGBA)
                    Divider().overlay(dividerColor)
                    gbSGBBordersRow

                    // Color Correction (always shown, disabled for non-Gambatte cores)
                    Divider().overlay(dividerColor)
                    if isGambatteCore {
                        gbColorCorrectionRow
                    } else {
                        gbColorCorrectionRow
                            .opacity(0.4)
                            .disabled(true)
                            .help("Gambatte core only — switch to gambatte_libretro to use color correction")
                    }

                    Divider().overlay(dividerColor)

                    Text("Apply color palettes to original Game Boy (DMG) games. 'Auto' selects the best palette for each game. 'Internal' uses a classic Game Boy or Super Game Boy palette. Named palettes and color correction require the Gambatte core.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .lineSpacing(2)
                } else {
                    Divider().overlay(dividerColor)

                    Text("Games will display in classic Game Boy monochrome (green-tinted).")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .lineSpacing(2)
                }
            }
        }
    }

    // MARK: - GB Colorization Sub-Views

    private var gbPaletteModeRow: some View {
        HStack {
            Image(systemName: "eyedropper")
                .foregroundColor(.white.opacity(0.5))
            Text("Palette Mode")
                .foregroundColor(.white.opacity(0.5))
                .font(.caption)

            Spacer()

            Picker("Palette Mode", selection: Binding(
                get: { gbColorizationMode },
                set: { newValue in
                    gbColorizationMode = newValue
                    applyGBColorizationSettings()
                }
            )) {
                Text("Auto Select").tag("auto")
                Text("Game Boy Color").tag("gbc")
                Text("Super Game Boy").tag("sgb")
                Text("Internal Palette").tag("internal")
                Text("Custom Palettes").tag("custom")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
        }
    }

    private var gbInternalPaletteRow: some View {
        HStack {
            Image(systemName: "paintpalette")
                .foregroundColor(.white.opacity(0.5))
            Text("Internal Palette")
                .foregroundColor(.white.opacity(0.5))
                .font(.caption)

            Spacer()

            Picker("Internal Palette", selection: Binding(
                get: { gbInternalPalette },
                set: { newValue in
                    gbInternalPalette = newValue
                    applyGBColorizationSettings()
                }
            )) {
                // GB palettes
                Section(header: Text("Game Boy")) {
                    Text("GB - DMG (Green)").tag("GB - DMG")
                    Text("GB - Pocket").tag("GB - Pocket")
                    Text("GB - Light").tag("GB - Light")
                }
                // GBC palettes
                Section(header: Text("Game Boy Color")) {
                    Text("GBC - Blue").tag("GBC - Blue")
                    Text("GBC - Brown").tag("GBC - Brown")
                    Text("GBC - Dark Blue").tag("GBC - Dark Blue")
                    Text("GBC - Dark Brown").tag("GBC - Dark Brown")
                    Text("GBC - Dark Green").tag("GBC - Dark Green")
                    Text("GBC - Grayscale").tag("GBC - Grayscale")
                    Text("GBC - Green").tag("GBC - Green")
                    Text("GBC - Inverted").tag("GBC - Inverted")
                    Text("GBC - Orange").tag("GBC - Orange")
                    Text("GBC - Pastel Mix").tag("GBC - Pastel Mix")
                    Text("GBC - Red").tag("GBC - Red")
                    Text("GBC - Yellow").tag("GBC - Yellow")
                }
                // SGB palettes
                Section(header: Text("Super Game Boy")) {
                    Text("SGB - 1A").tag("SGB - 1A")
                    Text("SGB - 1B").tag("SGB - 1B")
                    Text("SGB - 2A").tag("SGB - 2A")
                    Text("SGB - 2B").tag("SGB - 2B")
                    Text("SGB - 3A").tag("SGB - 3A")
                    Text("SGB - 3B").tag("SGB - 3B")
                    Text("SGB - 4A").tag("SGB - 4A")
                    Text("SGB - 4B").tag("SGB - 4B")
                }
                // Special palettes
                Section(header: Text("Special")) {
                    Text("Special 1").tag("Special 1")
                    Text("Special 2").tag("Special 2")
                    Text("Special 3").tag("Special 3")
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
        }
    }

    private var gbSGBBordersRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundColor(.white.opacity(0.5))
                Text("Super Game Boy Borders")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.caption)
                Spacer()
                Text("mGBA core")
                    .foregroundColor(.white.opacity(0.3))
                    .font(.caption2)
            }
            Text("Show decorative borders on SGB-enhanced games.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.3))
                .padding(.leading, 24)
            Toggle("", isOn: Binding(
                get: { gbSGBBordersEnabled },
                set: { newValue in
                    gbSGBBordersEnabled = newValue
                    applyGBColorizationSettings()
                }
            ))
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
        }
    }

    private var gbColorCorrectionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "sun.max")
                    .foregroundColor(.white.opacity(0.5))
                Text("Color Correction")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.caption)

                Spacer()

                Picker("Color Correction", selection: Binding(
                    get: { gbColorCorrectionMode },
                    set: { newValue in
                        gbColorCorrectionMode = newValue
                        applyGBColorizationSettings()
                    }
                )) {
                    Text("GBC Games Only").tag("gbc_only")
                    Text("Always").tag("always")
                    Text("Disabled").tag("disabled")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)
            }
            Text("Match output colors to original Game Boy Color LCD.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.3))
                .padding(.leading, 24)
        }
    }

    /// Apply GB colorization settings to the ROM and save
    private func applyGBColorizationSettings() {
        guard currentROM.systemID == "gb" || currentROM.systemID == "gbc" else { return }
        var updated = currentROM
        updated.settings.gbColorizationEnabled = gbColorizationEnabled
        updated.settings.gbColorizationMode = gbColorizationMode
        updated.settings.gbInternalPalette = gbInternalPalette
        updated.settings.gbSGBBordersEnabled = gbSGBBordersEnabled
        updated.settings.gbColorCorrectionMode = gbColorCorrectionMode
        library.updateROM(updated)
    }

    private var identifyButton: some View {
        Button {
            Task {
                manualActionStatus = .working("Identifying from No-Intro database…")
                let result = await library.identifyROM(currentROM)
                switch result {
                case .identified(let info):
                    showManualResult("Found: \(info.name)", tone: .success)
                case .identifiedFromName(let info):
                    showManualResult(
                        "Found: \(info.name) (matched by filename)",
                        tone: .success
                    )
                case .crcNotInDatabase(let crc):
                    showManualResult(
                        "Couldn't identify this game. Try downloading metadata manually.",
                        tone: .warning
                    )
                    LoggerService.debug(category: "Identity", "Unknown game — CRC: \(crc)")
                case .identificationCleared:
                    showManualResult("Identification cleared — game will use ROM filename", tone: .success)
                case .databaseUnavailable:
                    showManualResult(
                        "Identification database unavailable. Check your internet connection.",
                        tone: .error
                    )
                case .romReadFailed(let reason):
                    showManualResult("Could not read this game: \(reason)", tone: .error)
                case .noSystem:
                    showManualResult("Cannot identify — system is not set for this file.", tone: .error)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if case .working = manualActionStatus {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "qrcode.viewfinder")
                }
                Text("Identify Game")
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(buttonBgColor)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
        .disabled(isIdentifyWorking)
    }
    
    // MARK: - Fetch Metadata Button
    
    @State private var fetchMetadataStatus: ManualActionStatus = .hidden
    @State private var fetchMetadataAutoDismiss: Task<Void, Never>?
    
    // MARK: - Fetch Box Art Status
    
    @State private var fetchBoxArtStatus: ManualActionStatus = .hidden
    @State private var fetchBoxArtAutoDismiss: Task<Void, Never>?
    
    private func clearFetchBoxArtStatus() {
        fetchBoxArtAutoDismiss?.cancel()
        fetchBoxArtAutoDismiss = nil
        fetchBoxArtStatus = .hidden
    }
    
    private func clearFetchMetadataStatus() {
        fetchMetadataAutoDismiss?.cancel()
        fetchMetadataAutoDismiss = nil
        fetchMetadataStatus = .hidden
    }
    
    private var fetchMetadataButton: some View {
        Group {
            switch fetchMetadataStatus {
            case .hidden:
                Button {
                    Task { await fetchMetadata() }
                } label: {
                    Label("Fetch Metadata", systemImage: "network")
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background(subtleButtonBgColor)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            case .working(_):
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(subtleButtonBgColor)
                    .cornerRadius(8)
            case .result(let msg, let tone):
                Button {
                    clearFetchMetadataStatus()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tone.iconName)
                            .font(.caption)
                            .foregroundColor(tone.foregroundColor)
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(tone.foregroundColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func fetchMetadata() async {
        await MainActor.run { fetchMetadataStatus = .working("Searching LaunchBox...") }
        
        let success = await LaunchBoxGamesDBService.shared.fetchAndApplyMetadata(
            for: currentROM,
            library: library
        )
        
        fetchMetadataAutoDismiss?.cancel()
        fetchMetadataAutoDismiss = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            if case .result = fetchMetadataStatus {
                fetchMetadataStatus = .hidden
            }
        }
        
        if success {
            await MainActor.run { fetchMetadataStatus = .result("Metadata updated", tone: .success) }
        } else {
            await MainActor.run { fetchMetadataStatus = .result("No metadata found in the database. Try identifying this game first.", tone: .warning) }
        }
    }

    private var fetchBoxArtButton: some View {
        Group {
            switch fetchBoxArtStatus {
            case .hidden:
                Button {
                    Task { await fetchBoxArt() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                        Text("Fetch Art")
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(buttonBgColor)
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
            case .working(let msg):
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(buttonBgColor)
                .cornerRadius(20)
            case .result(let msg, let tone):
                Button {
                    clearFetchBoxArtStatus()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tone.iconName)
                            .font(.caption)
                            .foregroundColor(tone.foregroundColor)
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(tone.foregroundColor.opacity(0.1))
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func fetchBoxArt() async {
        await MainActor.run { fetchBoxArtStatus = .working("Searching...") }
        
        if let url = await BoxArtService.shared.fetchBoxArt(for: currentROM) {
            var u = currentROM
            u.boxArtPath = url
            library.updateROM(u)
            loadBoxArt()
            
            fetchBoxArtAutoDismiss?.cancel()
            fetchBoxArtAutoDismiss = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                if case .result = fetchBoxArtStatus {
                    fetchBoxArtStatus = .hidden
                }
            }
            
            await MainActor.run { fetchBoxArtStatus = .result("Art found", tone: .success) }
        } else {
            await MainActor.run { fetchBoxArtStatus = .result("No cover art found for this game. You can manually search using the Box Art picker.", tone: .warning) }
        }
    }

    // MARK: - Screenshots Row

    private var screenshotsRow: some View {
        ModernSectionCard(title: "Screenshots", icon: "photo.on.rectangle", showHeader: true) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(screenshotImages.indices, id: \.self) { index in
                        Image(nsImage: screenshotImages[index])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 180, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Section 2: Shader

    private var shaderSection: some View {
        ModernSectionCard(
            title: "Shader",
            icon: "tv",
            badge: isShaderCustomized ? "Custom" : nil
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Current shader display
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Shader")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.85))
                        Text(ShaderManager.displayName(for: currentROM.settings.shaderPresetID))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Spacer()

                    Button("Customize") {
                        presentShaderWindow()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.6))
                    .cornerRadius(8)
                }

                Divider().overlay(dividerColor)

                // Quick preset buttons
                VStack(spacing: 6) {
                    let recommended = shaderManager.recommendedPresets(for: currentROM.systemID ?? "")
                    let presetsToShow = recommended.isEmpty
                        ? Array(ShaderPreset.allPresets.prefix(4))
                        : recommended

                    ForEach(presetsToShow.prefix(4), id: \.id) { preset in
                        Button {
                            updateSettings { $0.shaderPresetID = preset.id }
                        } label: {
                            HStack {
                                Image(systemName: shaderIcon(for: preset.shaderType))
                                    .foregroundColor(.blue)
                                    .frame(width: 20)
                                Text(preset.name)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.85))
                                Spacer()
                                if currentROM.settings.shaderPresetID == preset.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                                if let desc = preset.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.4))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                currentROM.settings.shaderPresetID == preset.id
                                    ? Color.blue.opacity(0.15)
                                    : Color.clear
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().overlay(dividerColor)

                // Reset to system default button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Default")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        Text("Reset to default shader for this system")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    Button("Use Default") {
                        updateSettings { $0.shaderPresetID = systemDefaultShaderID }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(buttonBgColor)
                    .cornerRadius(6)
                    .disabled(!isShaderCustomized)
                }
            }
        }
    }

    private func shaderIcon(for type: ShaderType) -> String {
        switch type {
        case .crt: return "tv"
        case .lcd: return "iphone"
        case .smoothing: return "sparkles"
        case .composite: return "waveform.path"
        case .custom: return "wrench"
        }
    }

    @MainActor
    private func presentShaderWindow() {
        if shaderWindowSettings == nil {
            shaderWindowSettings = ShaderWindowSettings(
                shaderPresetID: currentROM.settings.shaderPresetID,
                uniformValues: extractUniformValues(from: currentROM.settings)
            )
        } else {
            shaderWindowSettings?.shaderPresetID = currentROM.settings.shaderPresetID
        }

        let windowController = ShaderWindowController(
            settings: shaderWindowSettings!
        ) { [self] newPresetID, newUniformValues in
            // Update ROM settings with new preset and uniform values
            updateSettings { romSettings in
                romSettings.shaderPresetID = newPresetID
                // Apply uniform values to ROM settings
                applyUniformValues(newUniformValues, to: &romSettings)
            }
            if let preset = ShaderPreset.preset(id: newPresetID) {
                ShaderManager.shared.activatePreset(preset)
            }
        }

        ShaderWindowController.shared = windowController
        windowController.show()
    }
    
    /// Extract uniform values from ROM settings into a dictionary for ShaderWindowSettings
    private func extractUniformValues(from settings: ROMSettings) -> [String: Float] {
        var values: [String: Float] = [:]
        values["scanlineIntensity"] = settings.scanlineIntensity
        values["barrelAmount"] = settings.barrelAmount
        values["colorBoost"] = settings.colorBoost
        values["crtEnabled"] = settings.crtEnabled ? 1.0 : 0.0
        values["scanlinesEnabled"] = settings.scanlinesEnabled ? 1.0 : 0.0
        values["barrelEnabled"] = settings.barrelEnabled ? 1.0 : 0.0
        values["phosphorEnabled"] = settings.phosphorEnabled ? 1.0 : 0.0
        return values
    }
    
    /// Apply uniform values from dictionary to ROM settings
    private func applyUniformValues(_ values: [String: Float], to settings: inout ROMSettings) {
        if let v = values["scanlineIntensity"] { settings.scanlineIntensity = v }
        if let v = values["barrelAmount"] { settings.barrelAmount = v }
        if let v = values["colorBoost"] { settings.colorBoost = v }
        if let v = values["crtEnabled"] { settings.crtEnabled = v != 0.0 }
        if let v = values["scanlinesEnabled"] { settings.scanlinesEnabled = v != 0.0 }
        if let v = values["barrelEnabled"] { settings.barrelEnabled = v != 0.0 }
        if let v = values["phosphorEnabled"] { settings.phosphorEnabled = v != 0.0 }
    }

    // MARK: - Section 2.5: Bezels

    @State private var currentBezelImage: NSImage?
    
    private var bezelsSection: some View {
        ModernSectionCard(
            title: "Bezels",
            icon: "picture.inset.filled",
            badge: currentBezelStatusText.isEmpty ? nil : currentBezelStatusText
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Bezel preview image
                if let bezelImage = currentBezelImage {
                    Image(nsImage: bezelImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                } else {
                    // Placeholder when no bezel preview available
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.3))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentBezelDisplayName)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.5))
                            Text("No preview available")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(subtleBgColor)
                    .cornerRadius(8)
                }

                Divider().overlay(dividerColor)

                // Current bezel display and actions
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Bezel")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.85))
                        Text(currentBezelDisplayName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Spacer()

                    Button("Browse Bezels") {
                        presentBezelSelectorWindow()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.6))
                    .cornerRadius(8)
                }

                Divider().overlay(dividerColor)

                // Bezel options
                VStack(spacing: 8) {
                    // Auto-match button
                    Button {
                        autoMatchBezel()
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white)
                                .frame(width: 20)
                            Text("Auto-Match Bezel")
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(buttonBgColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // Clear bezel button
                    Button {
                        clearBezel()
                    } label: {
                        HStack {
                            Image(systemName: "nosign")
                                .foregroundColor(.white)
                                .frame(width: 20)
                            Text("Clear Bezel")
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(buttonBgColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(dividerColor)

                // Info text
                Text("Bezels are pre-downloaded before gameplay. Browse available bezels from The Bezel Project or import your own.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .task(id: currentROM.id) {
            await loadCurrentBezelImage()
        }
    }

    /// Get the current bezel display text — shown as a badge in the section header.
    private var currentBezelStatusText: String {
        let bezelFileName = currentROM.settings.bezelFileName
        if bezelFileName == "none" {
            return "Off"
        } else if bezelFileName.isEmpty {
            return "Auto"
        } else {
            return "Custom"
        }
    }

    /// Get the current bezel display name — shown under "Current Bezel" heading.
    private var currentBezelDisplayName: String {
        let bezelFileName = currentROM.settings.bezelFileName
        if bezelFileName == "none" {
            return "Bezels are disabled"
        } else if bezelFileName.isEmpty {
            return "Automatically matched by game name"
        } else {
            return bezelFileName.replacingOccurrences(of: ".png", with: "")
                .replacingOccurrences(of: "_", with: " ")
        }
    }

    /// Load the current bezel image for preview
    @MainActor
    private func loadCurrentBezelImage() async {
        let bezelFileName = currentROM.settings.bezelFileName
        
        guard bezelFileName != "none" else {
            currentBezelImage = nil
            return
        }
        
        guard let systemID = currentROM.systemID else {
            currentBezelImage = nil
            return
        }
        
        // Strategy 1: Try direct path with the bezelFileName
        let directURL = BezelStorageManager.shared.bezelFilePath(
            systemID: systemID,
            gameName: bezelFileName.isEmpty ? currentROM.displayName : bezelFileName
        )
        
        if let image = NSImage(contentsOf: directURL) {
            currentBezelImage = image
            LoggerService.debug(category: "Bezel", "Loaded preview from direct path: \(directURL.path)")
            return
        }
        LoggerService.debug(category: "Bezel", "Direct path not found: \(directURL.path)")
        
        // Strategy 2: Try with .png extension appended (in case bezelFileName is just the base name)
        let baseName = bezelFileName.isEmpty ? currentROM.displayName : bezelFileName
        let fileNameWithExt = baseName.hasSuffix(".png") ? baseName : baseName + ".png"
        let urlWithExt = BezelStorageManager.shared.bezelFilePath(
            systemID: systemID,
            gameName: fileNameWithExt
        )
        
        if let image = NSImage(contentsOf: urlWithExt) {
            currentBezelImage = image
            LoggerService.debug(category: "Bezel", "Loaded preview from path with extension: \(urlWithExt.path)")
            return
        }
        LoggerService.debug(category: "Bezel", "Path with extension not found: \(urlWithExt.path)")
        
        // Strategy 3: Try auto-match via BezelManager
        let result = BezelManager.shared.resolveBezel(systemID: systemID, rom: currentROM)
        if let entry = result.entry, let url = entry.localURL,
           FileManager.default.fileExists(atPath: url.path) {
            currentBezelImage = NSImage(contentsOf: url)
            LoggerService.debug(category: "Bezel", "Loaded preview from BezelManager resolve: \(url.path)")
            return
        }
        LoggerService.debug(category: "Bezel", "BezelManager resolve failed")
        
        // Strategy 4: Scan the bezel directory for a matching file
        let bezelDir = BezelStorageManager.shared.systemBezelsDirectory(for: systemID)
        if FileManager.default.fileExists(atPath: bezelDir.path) {
            let searchName = bezelFileName.isEmpty ? currentROM.displayName : bezelFileName
            let searchNameLower = searchName.lowercased()
            let fileManager = FileManager.default
            
            if let fileURLs = try? fileManager.contentsOfDirectory(at: bezelDir, includingPropertiesForKeys: nil) {
                for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "png" {
                    let fileBaseName = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                    if fileBaseName == searchNameLower {
                        if let image = NSImage(contentsOf: fileURL) {
                            currentBezelImage = image
                            LoggerService.debug(category: "Bezel", "Loaded preview from directory scan: \(fileURL.path)")
                            return
                        }
                    }
                }
            }
        }
        LoggerService.debug(category: "Bezel", "Directory scan found no match")
        
        currentBezelImage = nil
        LoggerService.debug(category: "Bezel", "No bezel image found for \(currentROM.displayName)")
    }

    /// Auto-match bezel for the current game.
    @MainActor
    private func autoMatchBezel() {
        guard let systemID = currentROM.systemID else { return }
        
        LoggerService.info(category: "Bezel", "Auto-matching bezel for \(currentROM.displayName) (system: \(systemID))")
        let result = BezelManager.shared.resolveBezel(systemID: systemID, rom: currentROM, preferAutoMatch: true)
        
        if let entry = result.entry {
            LoggerService.info(category: "Bezel", "Auto-matched bezel: \(entry.filename) (method: \(result.resolutionMethod))")
            var updated = currentROM
            updated.settings.bezelFileName = entry.filename
            library.updateROM(updated)
            
            // Refresh the bezel preview
            Task {
                await loadCurrentBezelImage()
            }
            
            showManualResult("Auto-matched bezel: \(entry.id)", tone: .success)
        } else {
            LoggerService.debug(category: "Bezel", "No bezel found for \(currentROM.displayName)")
            showManualResult("No bezel found for \(currentROM.displayName)", tone: .warning)
        }
    }

    /// Clear bezel for the current game.
    private func clearBezel() {
        var updated = currentROM
        updated.settings.bezelFileName = ""
        library.updateROM(updated)
    }

    @MainActor
    private func presentBezelSelectorWindow() {
        let controller = BezelSelectorWindowController(
            rom: currentROM,
            systemID: currentROM.systemID ?? "",
            library: library
        )
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Section 3: Controls

    private var controlsSection: some View {
        ModernSectionCard(
            title: "Controls",
            icon: "gamecontroller",
            badge: "System"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Controller display
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Controller Mapping")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.85))
                        Text("Uses standard \(system?.name ?? "this system") layout")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Spacer()

                    Button("Edit") {
                        showControlsPicker = true
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.6))
                    .cornerRadius(8)
                }

                // Controller icon display
                if let sys = system, let controllerIcon = controllerIconForSystem(sys) {
                    HStack(spacing: 16) {
                        Image(nsImage: controllerIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Mapping")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.85))
                            Text("Standard \(sys.name) controller")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(cardBgColor)
                    .cornerRadius(8)
                }

                Divider().overlay(dividerColor)

                // Reset to system defaults
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Default Controls")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        Text("Reset to default controls")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    Button("Reset") {
                        resetControlsToSystemDefault()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(buttonBgColor)
                    .cornerRadius(6)
                }
            }
        }
    }

    private func controllerIconForSystem(_ sys: SystemInfo) -> NSImage? {
        Bundle.main.url(
            forResource: sys.id,
            withExtension: "ico",
            subdirectory: "ControllerIcons"
        ).flatMap { NSImage(contentsOf: $0) }
    }

    private func resetControlsToSystemDefault() {
        let systemID = currentROM.systemID ?? ""
        controllerService.updateKeyboardMapping(
            KeyboardMapping.defaults(for: systemID),
            for: systemID
        )
    }

    // MARK: - Section 4: Saved States

    private var savedStatesSection: some View {
        ModernSectionCard(
            title: "Saved States",
            icon: "externaldrive",
            badge: slotInfoList.filter { $0.exists && $0.id >= 0 }.isEmpty ? nil : "\(slotInfoList.filter { $0.exists && $0.id >= 0 }.count)"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                let existingSlots = slotInfoList.filter { $0.exists }
                let emptySlots = slotInfoList.filter { !$0.exists && $0.id >= 0 }.prefix(10)
                let showSlots = existingSlots.isEmpty ? Array(emptySlots) : slotInfoList.filter { $0.id >= 0 }

                if showSlots.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive.slash")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No saved states")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                        Text("Save states created during gameplay")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    // Grid of save state slots
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                        spacing: 12
                    ) {
                        ForEach(showSlots.filter { $0.id >= 0 }, id: \.id) { slot in
                            ModernSaveStateSlotView(
                                slot: slot,
                                rom: currentROM,
                                saveStateManager: saveStateManager,
                                onDelete: { loadSlotInfo() },
                                onLaunchSlot: { slotId in
                                    launchGame(slotToLoad: slotId)
                                }
                            )
                        }
                    }
                }

                if !existingSlots.isEmpty {
                    Divider().overlay(dividerColor)

                    // Summary
                    HStack {
                        Text("\(existingSlots.count) save state(s)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        let totalSize = existingSlots.reduce(0) { $0 + ($1.fileSize ?? 0) }
                        if totalSize > 0 {
                            Text(Int64(totalSize).formattedByteSize)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section 5: Cheats

    @StateObject private var cheatManagerService = CheatManagerService.shared
    @StateObject private var cheatDownloadService = CheatDownloadService.shared
    @State private var cheatCount: Int = 0
    @State private var enabledCheatCount: Int = 0
    @State private var downloadMessage: String? = nil
    @State private var downloadMessageTone: ManualStatusTone = .info

    @State private var cheatsList: [Cheat] = []
    @State private var cheatSearchText: String = ""
    
    private var filteredCheatsList: [Cheat] {
        guard !cheatSearchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return cheatsList
        }
        let searchWords = cheatSearchText.lowercased().split(separator: " ").map { String($0) }
        return cheatsList.filter { cheat in
            let cheatText = cheat.displayName.lowercased()
            return searchWords.allSatisfy { word in cheatText.contains(word) }
        }
    }
    
    private var cheatsSection: some View {
        ModernSectionCard(
            title: "Cheats",
            icon: "wand.and.stars",
            badge: cheatCount > 0 ? "\(enabledCheatCount)/\(cheatCount)" : nil
        ) {
            VStack(spacing: 10) {
                // Download status message
                if let message = downloadMessage {
                    HStack(spacing: 8) {
                        if cheatDownloadService.isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: downloadMessageTone.iconName)
                                .foregroundColor(downloadMessageTone.foregroundColor)
                        }
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Button {
                            downloadMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(cardBgColor)
                    .cornerRadius(6)
                }

                // Download and manage buttons
                HStack(spacing: 6) {
                    Button {
                        Task {
                            LoggerService.info(category: "Cheats", "Download button tapped")
                            downloadMessage = "Starting download..."
                            downloadMessageTone = .info
                            
                            do {
                                let systemID = currentROM.systemID ?? ""
                                guard !systemID.isEmpty else {
                                    downloadMessage = "No system assigned to this game"
                                    downloadMessageTone = .warning
                                    return
                                }
                                
                                let cheatCountBefore = cheatManagerService.totalCount(for: currentROM)
                                let success = try await withTimeout(seconds: 120) {
                                    try await cheatDownloadService.downloadCheatForROM(currentROM, systemID: systemID)
                                }
                                
                                if success {
                                    cheatManagerService.loadCheatsForROM(currentROM)
                                    updateCheatCounts()
                                    loadCheatsList()
                                    let cheatsFound = cheatCount - cheatCountBefore
                                    if cheatsFound > 0 {
                                        downloadMessage = "Downloaded \(cheatsFound) cheat\(cheatsFound == 1 ? "" : "s")"
                                    } else {
                                        downloadMessage = "Downloaded cheat for \(currentROM.displayName)"
                                    }
                                    downloadMessageTone = .success
                                } else {
                                    downloadMessage = "No cheat file found for \(currentROM.displayName)"
                                    downloadMessageTone = .warning
                                }
                            } catch is TimeoutError {
                                downloadMessage = "Download timed out"
                                downloadMessageTone = .error
                            } catch {
                                downloadMessage = "Download failed: \(error.localizedDescription)"
                                downloadMessageTone = .error
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if cheatDownloadService.isDownloading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text(cheatDownloadService.isDownloading ? "Downloading..." : "Download")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(cheatDownloadService.isDownloading ? Color.green.opacity(0.4) : Color.green.opacity(0.6))
                        .cornerRadius(5)
                    }
                    .disabled(cheatDownloadService.isDownloading)
                    
                    Button {
                        showImportCheatFile = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.6))
                        .cornerRadius(5)
                    }
                    
                    Spacer()
                    
                    Button {
                        showCheatManager = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("Manage")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(5)
                    }
                }

                Divider().overlay(dividerColor)

                // Search field (when cheats are available)
                if !cheatsList.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.4))
                            .font(.caption)
                        TextField("Search cheats...", text: $cheatSearchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                        if !cheatSearchText.isEmpty {
                            Button {
                                cheatSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.3))
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(cardBgColor)
                    .cornerRadius(5)
                }

                // Cheat list display
                if cheatsList.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No cheats available")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        Text("Download or import a cheat file")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredCheatsList) { cheat in
                                CheatListRowView(
                                    cheat: cheat,
                                    isOn: cheat.enabled,
                                    onToggle: {
                                        var updated = cheat
                                        updated.enabled.toggle()
                                        cheatManagerService.updateCheat(updated, for: currentROM)
                                        loadCheatsList()
                                        updateCheatCounts()
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    
                    if !cheatSearchText.isEmpty && filteredCheatsList.isEmpty {
                        Text("No cheats match \"\(cheatSearchText)\"")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.vertical, 4)
                    }
                    
                    Divider().overlay(dividerColor)
                    
                    // Quick toggle all button
                    HStack {
                        Button {
                            if enabledCheatCount > 0 {
                                cheatManagerService.disableAllCheats(for: currentROM)
                            } else {
                                cheatManagerService.enableAllCheats(for: currentROM)
                            }
                            loadCheatsList()
                            updateCheatCounts()
                        } label: {
                            Label(enabledCheatCount > 0 ? "Disable All" : "Enable All", 
                                  systemImage: enabledCheatCount > 0 ? "stop.circle" : "play.circle")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Text("\(enabledCheatCount) of \(cheatCount) enabled")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                Divider().overlay(dividerColor)

                // Link to cheat settings
                Button {
                    openCheatSettings()
                } label: {
                    HStack {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white.opacity(0.5))
                        Text("Cheat Settings")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            updateCheatCounts()
            loadCheatsList()
            // Auto-load cheats for this ROM on appear if not already loaded
            if cheatsList.isEmpty {
                cheatManagerService.loadCheatsForROM(currentROM)
                cheatsList = cheatManagerService.cheats(for: currentROM)
                updateCheatCounts()
            }
        }
        .onChange(of: currentROM.id) { _, _ in
            updateCheatCounts()
            loadCheatsList()
            if cheatsList.isEmpty {
                cheatManagerService.loadCheatsForROM(currentROM)
                cheatsList = cheatManagerService.cheats(for: currentROM)
                updateCheatCounts()
            }
        }
        .fileImporter(
            isPresented: $showImportCheatFile,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        _ = await cheatManagerService.importChtFile(url, for: currentROM)
                        updateCheatCounts()
                        loadCheatsList()
                    }
                }
            case .failure(let error):
                LoggerService.debug(category: "Cheats", "File import error: \(error)")
            }
        }
    }
    
    private func loadCheatsList() {
        cheatsList = cheatManagerService.cheats(for: currentROM)
    }
    
    private func updateCheatCounts() {
        cheatCount = cheatManagerService.totalCount(for: currentROM)
        enabledCheatCount = cheatManagerService.enabledCount(for: currentROM)
    }
    
    private func openCheatSettings() {
        // Open the app's settings window
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        // Also try the standard preferences approach
        if NSApp.mainWindow == nil {
            NSApp.activate(ignoringOtherApps: true)
        }
    }


    // MARK: - Section: Core

    private var coreSection: some View {
        ModernSectionCard(title: "Core", icon: "chip") {
            VStack(alignment: .leading, spacing: 12) {
                // Core picker row
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.white.opacity(0.5))
                    Text("Emulation Core")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.caption)
                    Spacer()
                    if installedCores.isEmpty {
                        Text("No cores installed")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.3))
                    } else {
                        Picker("Core", selection: $selectedCoreID) {
                            ForEach(installedCores) { core in
                                Text(core.metadata.displayName).tag(core.id as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                Divider().overlay(dividerColor)

                // Apply to system toggle
                Toggle(isOn: $applyCoreToSystem) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.white.opacity(0.5))
                        Text("Apply to system default")
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                if applyCoreToSystem {
                    Text("This will change the default core for all \(systemName) games. The current game will no longer use a custom core override.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .lineSpacing(2)
                } else {
                    Text("Only this game will use the selected core.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .lineSpacing(2)
                }

                Divider().overlay(dividerColor)

                // Apply button
                HStack {
                    Spacer()
                    Button {
                        applyCoreConfiguration()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: applyCoreToSystem ? "globe" : "gamecontroller")
                            Text(applyCoreToSystem ? "Set System Default" : "Set for This Game")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCoreID == nil || installedCores.isEmpty)
                }
            }
        }
        .onAppear {
            // Initialize applyToSystem based on whether this ROM has a custom core
            applyCoreToSystem = !currentROM.useCustomCore
        }
    }

    private func applyCoreConfiguration() {
        guard let sysID = currentROM.systemID,
              let coreID = selectedCoreID,
              !coreID.isEmpty else { return }

        if applyCoreToSystem {
            // Apply as system default: remove per-game override, set system preference
            sysPrefs.setPreferredCoreID(coreID, for: sysID)

            // Clear per-game custom core
            var updated = currentROM
            updated.useCustomCore = false
            updated.selectedCoreID = nil
            library.updateROM(updated)

            // Reset local state to reflect system default
            useCustomCore = false
        } else {
            // Apply as per-game override
            var updated = currentROM
            updated.useCustomCore = true
            updated.selectedCoreID = coreID
            library.updateROM(updated)

            useCustomCore = true
        }
    }

    private var systemName: String {
        system?.name ?? currentROM.systemID ?? "Unknown"
    }

    // MARK: - Section 6: Achievements

    private var achievementsSection: some View {
        ModernSectionCard(
            title: "Achievements",
            icon: "trophy",
            badge: gameAchievements.isEmpty ? nil : "\(unlockedAchievementCount)/\(gameAchievements.count)"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if isAchievementsLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading achievements...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else if gameAchievements.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.slash")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No achievements available")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                        Text("Game may not have RetroAchievements data")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    // Summary
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(unlockedAchievementCount)/\(gameAchievements.count)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Achievements")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(earnedPoints)/\(totalAchievementPoints)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Points")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }

                        Spacer()

                        // Progress bar
                        let progress = gameAchievements.isEmpty
                            ? 0.0
                            : Double(unlockedAchievementCount) / Double(gameAchievements.count)
                        ProgressView(value: progress)
                            .tint(.blue)
                            .frame(width: 100)
                    }

                    Divider().overlay(dividerColor)

                    // Achievement list (limited display)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(gameAchievements.prefix(6)) { achievement in
                                AchievementBadgeView(achievement: achievement)
                            }

                            if gameAchievements.count > 6 {
                                Text("+\(gameAchievements.count - 6) more")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.4))
                                    .frame(width: 60)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Launch Button (Pill Shape - Steam Style)

    private var launchButton: some View {
        Button {
            launchGame()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.title3)
                Text("Play")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.35, green: 0.75, blue: 0.35),
                        Color(red: 0.25, green: 0.60, blue: 0.25)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: .green.opacity(0.3), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Placeholder Art

    private var placeholderArt: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.22, blue: 0.25),
                    Color(red: 0.15, green: 0.16, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            if let img = system?.emuImage(size: 600) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
                    .opacity(0.6)
            } else {
                Image(systemName: system?.iconName ?? "gamecontroller")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    /// Color-coded ESRB badge matching rating severity.
    private func esrbBadgeColor(for rating: String) -> Color {
        switch rating.lowercased() {
        case "ec", "e": return Color.green.opacity(0.3)
        case "e10+": return Color.blue.opacity(0.3)
        case "t": return Color.yellow.opacity(0.3)
        case "m", "ao": return Color.red.opacity(0.3)
        default: return Color.white.opacity(0.1)
        }
    }

    // MARK: - Helpers

    private func updateSettings(_ action: (inout ROMSettings) -> Void) {
        var updated = currentROM
        action(&updated.settings)
        library.updateROM(updated)
    }

    @State private var isLaunchingGame = false
    
    /// Unified game launch - uses GameLauncher for consistent behavior across all launch points
    /// (double-click, launch button, save state click)
    private func launchGame(slotToLoad: Int? = nil) {
        guard !isLaunchingGame else { return }
        
        guard let sysID = currentROM.systemID,
              let system = SystemDatabase.system(forID: sysID) else { 
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
        
        // Use unified GameLauncher for consistent launch behavior
        gameLauncher.launchGame(
            rom: currentROM,
            coreID: cid,
            slotToLoad: slotToLoad,
            library: library
        ) { _ in
            self.isLaunchingGame = false
        }
    }
}

// MARK: - Modern Save State Slot View

struct ModernSaveStateSlotView: View {
    let slot: SlotInfo
    let rom: ROM
    @ObservedObject var saveStateManager: SaveStateManager
    var onDelete: () -> Void
    var onLaunchSlot: (Int) -> Void = { _ in }
    @State private var thumbnail: NSImage?
    @State private var showPlayButton = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var slotBgColor: Color {
        colorScheme == .dark ? .white.opacity(0.05) : .secondary.opacity(0.04)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Thumbnail or placeholder
                ZStack {
                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(slotBgColor)
                            .overlay(
                                Image(systemName: slot.exists ? "externaldrive.fill" : "externaldrive")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.3))
                            )
                    }
                }
                .frame(width: 70, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Play button overlay (appears on single-click for saved slots)
                if slot.exists && showPlayButton {
                    Button {
                        onLaunchSlot(slot.id)
                    } label: {
                        ZStack {
                            Color.black.opacity(0.6)
                            VStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                Text("Play")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(slot.exists ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )

            // Slot number
            Text(slot.displayName)
                .font(.caption)
                .fontWeight(slot.exists ? .semibold : .regular)
                .foregroundColor(slot.exists ? .white.opacity(0.85) : .white.opacity(0.4))

            // Date and size info
            if let date = slot.formattedDate {
                Text(date)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            } else if let fileSize = slot.fileSize {
                Text(fileSize.formattedByteSize)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(width: 74)
        // Single tap: show play button
        .onTapGesture(count: 1) {
            if slot.exists {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showPlayButton = true
                }
            }
        }
        // Double tap: launch game and load this slot directly
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    if slot.exists {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showPlayButton = false
                        }
                        onLaunchSlot(slot.id)
                    }
                }
        )
        // Dismiss play button when tapping elsewhere
        .onChange(of: showPlayButton) { _, _ in
            if showPlayButton {
                // Auto-dismiss after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showPlayButton = false
                    }
                }
            }
        }
        .contextMenu {
            if slot.exists {
                Button(action: {
                    if slot.id >= 0 {
                        try? saveStateManager.deleteState(
                            gameName: rom.displayName,
                            systemID: rom.systemID ?? "",
                            slot: slot.id
                        )
                        onDelete()
                    }
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .task {
            if slot.exists {
                thumbnail = saveStateManager.loadThumbnail(
                    gameName: rom.displayName,
                    systemID: rom.systemID ?? "",
                    slot: slot.id
                )
            }
        }
    }
}

// MARK: - Achievement Badge View

struct AchievementBadgeView: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 4) {
            // Badge image
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(achievement.isUnlocked
                        ? Color.blue.opacity(0.2)
                        : Color.white.opacity(0.05))
                    .frame(width: 50, height: 50)

                Image(systemName: achievement.isUnlocked ? "trophy.fill" : "trophy")
                    .font(.system(size: 22))
                    .foregroundColor(achievement.isUnlocked ? .blue : .white.opacity(0.3))
            }

            // Points
            Text("\(achievement.points)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(achievement.isUnlocked ? .blue : .white.opacity(0.4))

            // Title
            Text(achievement.isUnlocked ? achievement.title : "???")
                .font(.system(size: 9))
                .lineLimit(1)
                .frame(width: 60)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - Cheat List Row View (for GameDetailView)

struct CheatListRowView: View {
    let cheat: Cheat
    let isOn: Bool
    var onToggle: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var cheatButtonBg: Color { colorScheme == .dark ? .white.opacity(0.1) : .secondary.opacity(0.12) }
    private var cheatRowBg: Color { colorScheme == .dark ? .white.opacity(0.03) : .secondary.opacity(0.03) }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { _ in onToggle() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cheat.displayName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                    if !cheat.code.isEmpty {
                        Text(cheat.codePreview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .toggleStyle(CheatToggleStyle())
            
            Spacer()
            
            // Format badge
            Text(cheat.format.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(cheatButtonBg)
                .foregroundColor(.white.opacity(0.6))
                .cornerRadius(4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(cheatRowBg)
        .cornerRadius(6)
    }
}

// MARK: - Cheat Toggle Style

struct CheatToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .foregroundColor(configuration.isOn ? .green : .white.opacity(0.3))
                .font(.body)
            
            configuration.label
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            configuration.isOn.toggle()
        }
    }
}

// MARK: - Core Version Picker

// MARK: - Detail Box Art Button

struct DetailBoxArtButton: View {
    let image: NSImage?
    let placeholder: () -> AnyView
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Group {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    placeholder()
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            if let img = image {
                DetailZoomableFullScreenView(image: img)
            }
        }
    }
}

// MARK: - Detail Zoomable Full Screen View

struct DetailZoomableFullScreenView: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(1.0, lastScale * value), 5.0)
                        }
                        .onEnded { _ in
                            if scale < 1.1 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    scale = 1.0
                                    offset = .zero
                                    lastScale = 1.0
                                    lastOffset = .zero
                                }
                            } else {
                                lastScale = scale
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.0 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                            lastScale = 1.0
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .opacity(showControls ? 1 : 0)
                }
                Spacer()
                Text("Pinch to zoom")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 20)
                    .opacity(showControls ? 1 : 0)
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
        }
    }
}

struct CoreVersionPickerView: View {
    @EnvironmentObject var coreManager: CoreManager
    let core: LibretroCore
    @State private var selectedTag: String?

    var body: some View {
        HStack {
            Text("Version")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            Picker("Version", selection: $selectedTag) {
                if selectedTag == nil {
                    Text("Select Version...").tag(nil as String?)
                }
                ForEach(core.installedVersions.reversed()) { v in
                    Text(v.tag).tag(v.tag as String?)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedTag) { _, tag in
                guard let tag else { return }
                coreManager.setActiveVersion(coreID: core.id, tag: tag)
            }
        }
        .onAppear { selectedTag = core.activeVersionTag }
    }
}
