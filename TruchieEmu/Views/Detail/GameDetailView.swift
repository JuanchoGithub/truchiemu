import SwiftUI

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
    case achievements = "Achievements"
}

// MARK: - Modern Section Card Component (Non-collapsible)

struct ModernSectionCard<Content: View>: View {
    let title: String?
    let icon: String?
    var badge: String? = nil
    var showHeader: Bool = true
    @ViewBuilder let content: Content

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

    var body: some View {
        VStack(spacing: 0) {
            if showHeader, let title = title {
                HStack(spacing: 10) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundColor(.white.opacity(0.7))
                            .font(.body)
                    }
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    if let badge = badge {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    Spacer()
                }
                
                Divider()
                    .padding(.vertical, 10)
                    .overlay(Color.white.opacity(0.1))
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
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

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.body)
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.middle)
                .font(isMonospaced ? .body.monospaced() : .body)
            
            Spacer()
            
            if copyAction != nil {
                Button(action: copyAction!) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.white.opacity(0.4))
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
    var rom: ROM

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

    @State private var useCustomCore: Bool = false
    @State private var selectedCoreID: String? = nil
    @State private var manualActionStatus: ManualActionStatus = .hidden
    @State private var manualStatusAutoDismiss: Task<Void, Never>?
    
    @State private var shaderWindowSettings: ShaderWindowSettings?
    @State private var selectedSection: DetailSection = .gameInfo
    @State private var bezelSelectorWindowController: BezelSelectorWindowController?

    private var currentROM: ROM {
        library.roms.first { $0.id == rom.id } ?? rom
    }

    private var system: SystemInfo? {
        SystemDatabase.system(forID: currentROM.systemID ?? "")
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
                    .overlay(Color.white.opacity(0.1))

                // Sidebar + Content layout
                HStack(spacing: 0) {
                    // Sidebar with glassmorphism
                    sidebarNavigation

                    Divider()
                        .overlay(Color.white.opacity(0.1))

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
        }
        .onChange(of: currentROM.id) { _ in
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
        .onChange(of: currentROM.boxArtPath) { _ in loadBoxArt() }
        .onChange(of: currentROM.screenshotPaths) { _ in loadScreenshots() }
        .onChange(of: library.bezelUpdateToken) { _ in
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
        .background(
            Color.white.opacity(0.03)
        )
    }

    private func sidebarItem(for section: DetailSection) -> some View {
        let isSelected = selectedSection == section
        let icon = sectionIcon(for: section)
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
                    Image(systemName: icon)
                        .frame(width: 18)
                        .font(.body)
                        .foregroundColor(isSelected ? .blue : .white.opacity(0.5))
                    Text(section.rawValue)
                        .lineLimit(1)
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                        .fontWeight(isSelected ? .medium : .regular)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(
                isSelected ? 
                    AnyView(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.2))
                    ) : 
                    AnyView(Color.clear)
            )
        )
    }

    private func sectionIcon(for section: DetailSection) -> String {
        switch section {
        case .gameInfo: return "info.circle"
        case .shader: return "display"
        case .bezels: return "rectangle.on.rectangle"
        case .controls: return "gamecontroller"
        case .savedStates: return "externaldrive"
        case .cheats: return "wand.and.stars"
        case .achievements: return "trophy"
        }
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
                        print("[Achievements] Failed to load achievements: \(error.localizedDescription)")
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
        if let path = currentROM.boxArtPath {
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
                .overlay(Color.white.opacity(0.1))
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
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    
                    if let year = currentROM.metadata?.year {
                        Text("(\(year))")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.5))
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
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
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
                // Clear box art (main image)
                ZStack {
                    if let img = boxArtImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        placeholderArt
                    }
                }
                .frame(width: 110, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                .onTapGesture { showBoxArtPicker = true }
                
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
            }
            
            // Screenshots row
            if !screenshotImages.isEmpty {
                screenshotsRow
            }
            
            // Metadata card
            ModernSectionCard(showHeader: false) {
                VStack(alignment: .leading, spacing: 14) {
                    MetadataRow(label: "System", value: system?.name ?? currentROM.systemID ?? "Unknown")
                    
                    Divider().overlay(Color.white.opacity(0.08))
                    
                    MetadataRow(label: "File Name", value: currentROM.path.lastPathComponent)
                    
                    Divider().overlay(Color.white.opacity(0.08))
                    
                    MetadataRow(
                        label: "Path",
                        value: currentROM.path.deletingLastPathComponent().path,
                        copyAction: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(currentROM.path.path, forType: .string)
                        }
                    )
                    
                    if let size = fileSize {
                        Divider().overlay(Color.white.opacity(0.08))
                        MetadataRow(label: "File Size", value: size)
                    }

                    if let crc = crcHash {
                        Divider().overlay(Color.white.opacity(0.08))
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
                            Divider().overlay(Color.white.opacity(0.08))
                            MetadataRow(label: "Original Name", value: original)
                        }
                        if let dev = meta.developer {
                            Divider().overlay(Color.white.opacity(0.08))
                            MetadataRow(label: "Developer", value: dev)
                        }
                        if let pub = meta.publisher {
                            Divider().overlay(Color.white.opacity(0.08))
                            MetadataRow(label: "Publisher", value: pub)
                        }
                        if let genre = meta.genre {
                            Divider().overlay(Color.white.opacity(0.08))
                            MetadataRow(label: "Genre", value: genre)
                        }
                        if let players = meta.players {
                            Divider().overlay(Color.white.opacity(0.08))
                            MetadataRow(label: "Players", value: String(players))
                        }
                    }
                }
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
    
    private var identifyButton: some View {
        Button {
            Task {
                manualActionStatus = .working("Identifying from No-Intro database…")
                let result = await library.identifyROM(currentROM)
                switch result {
                case .identified(let info):
                    showManualResult("Matched by CRC: \(info.name)", tone: .success)
                case .identifiedFromName(let info):
                    showManualResult(
                        "No CRC match — matched by filename using your UI language for region preference: \(info.name)",
                        tone: .success
                    )
                case .crcNotInDatabase(let crc):
                    showManualResult(
                        "No DAT entry for CRC \(crc), and no No-Intro title matched this filename.",
                        tone: .warning
                    )
                case .databaseUnavailable:
                    showManualResult(
                        "Could not load the No-Intro DAT. Go online once or add a .dat file.",
                        tone: .error
                    )
                case .romReadFailed(let reason):
                    showManualResult(reason, tone: .error)
                case .noSystem:
                    showManualResult("This ROM has no system assigned.", tone: .error)
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
            .background(Color.white.opacity(0.1))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
        .disabled(isIdentifyWorking)
    }
    
    private var fetchBoxArtButton: some View {
        Button {
            Task {
                if let url = await BoxArtService.shared.fetchBoxArt(for: currentROM) {
                    var u = currentROM
                    u.boxArtPath = url
                    library.updateROM(u)
                    loadBoxArt()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                Text("Fetch Art")
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
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

                Divider().overlay(Color.white.opacity(0.08))

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

                Divider().overlay(Color.white.opacity(0.08))

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
                    .background(Color.white.opacity(0.1))
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
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(8)
                }

                Divider().overlay(Color.white.opacity(0.08))

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

                Divider().overlay(Color.white.opacity(0.08))

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
                        .background(Color.white.opacity(0.1))
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
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(Color.white.opacity(0.08))

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

    /// Get the current bezel display text.
    private var currentBezelStatusText: String {
        let bezelFileName = currentROM.settings.bezelFileName
        if bezelFileName == "none" {
            return "Disabled"
        } else if bezelFileName.isEmpty {
            return "Auto"
        } else {
            return "Custom"
        }
    }

    /// Get the current bezel display name.
    private var currentBezelDisplayName: String {
        let bezelFileName = currentROM.settings.bezelFileName
        if bezelFileName == "none" {
            return "Bezels disabled"
        } else if bezelFileName.isEmpty {
            return "Auto-detected (if available)"
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
            print("[BezelPreview] Loaded from direct path: \(directURL.path)")
            return
        }
        print("[BezelPreview] Direct path not found: \(directURL.path)")
        
        // Strategy 2: Try with .png extension appended (in case bezelFileName is just the base name)
        let baseName = bezelFileName.isEmpty ? currentROM.displayName : bezelFileName
        let fileNameWithExt = baseName.hasSuffix(".png") ? baseName : baseName + ".png"
        let urlWithExt = BezelStorageManager.shared.bezelFilePath(
            systemID: systemID,
            gameName: fileNameWithExt
        )
        
        if let image = NSImage(contentsOf: urlWithExt) {
            currentBezelImage = image
            print("[BezelPreview] Loaded from path with extension: \(urlWithExt.path)")
            return
        }
        print("[BezelPreview] Path with extension not found: \(urlWithExt.path)")
        
        // Strategy 3: Try auto-match via BezelManager
        let result = BezelManager.shared.resolveBezel(systemID: systemID, rom: currentROM)
        if let entry = result.entry, let url = entry.localURL,
           FileManager.default.fileExists(atPath: url.path) {
            currentBezelImage = NSImage(contentsOf: url)
            print("[BezelPreview] Loaded from BezelManager resolve: \(url.path)")
            return
        }
        print("[BezelPreview] BezelManager resolve failed")
        
        // Strategy 4: Scan the bezel directory for a matching file
        let bezelDir = BezelStorageManager.shared.systemBezelsDirectory(for: systemID)
        if FileManager.default.fileExists(atPath: bezelDir.path) {
            let searchName = bezelFileName.isEmpty ? currentROM.displayName : bezelFileName
            let searchNameLower = searchName.lowercased()
            let fileManager = FileManager.default
            
            if let enumerator = fileManager.enumerator(at: bezelDir, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "png" {
                        let fileBaseName = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                        if fileBaseName == searchNameLower {
                            if let image = NSImage(contentsOf: fileURL) {
                                currentBezelImage = image
                                print("[BezelPreview] Loaded from directory scan: \(fileURL.path)")
                                return
                            }
                        }
                    }
                }
            }
        }
        print("[BezelPreview] Directory scan found no match")
        
        currentBezelImage = nil
        print("[BezelPreview] No bezel image found for \(currentROM.displayName)")
    }

    /// Auto-match bezel for the current game.
    @MainActor
    private func autoMatchBezel() {
        guard let systemID = currentROM.systemID else { return }
        
        print("[Bezel] Auto-matching bezel for \(currentROM.displayName) (system: \(systemID))")
        let result = BezelManager.shared.resolveBezel(systemID: systemID, rom: currentROM, preferAutoMatch: true)
        
        if let entry = result.entry {
            print("[Bezel] Auto-matched bezel: \(entry.filename) (method: \(result.resolutionMethod))")
            var updated = currentROM
            updated.settings.bezelFileName = entry.filename
            library.updateROM(updated)
            
            // Refresh the bezel preview
            Task {
                await loadCurrentBezelImage()
            }
            
            showManualResult("Auto-matched bezel: \(entry.id)", tone: .success)
        } else {
            print("[Bezel] No bezel found for \(currentROM.displayName)")
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
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }

                Divider().overlay(Color.white.opacity(0.08))

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
                    .background(Color.white.opacity(0.1))
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
                    Divider().overlay(Color.white.opacity(0.08))

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
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                }

                // Download and manage buttons
                HStack(spacing: 6) {
                    Button {
                        Task {
                            print("[CheatUI] === Download button tapped ===")
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

                Divider().overlay(Color.white.opacity(0.08))

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
                    .background(Color.white.opacity(0.05))
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
                    
                    Divider().overlay(Color.white.opacity(0.08))
                    
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

                Divider().overlay(Color.white.opacity(0.08))

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
        .onChange(of: currentROM.id) { _ in
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
                print("File import error: \(error)")
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

                    Divider().overlay(Color.white.opacity(0.08))

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
            coreManager.requestCoreDownload(for: cid, systemID: sysID)
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
                            .fill(Color.white.opacity(0.05))
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
        .onChange(of: showPlayButton) { _ in
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
                .background(Color.white.opacity(0.1))
                .foregroundColor(.white.opacity(0.6))
                .cornerRadius(4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.03))
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
            .onChange(of: selectedTag) { tag in
                guard let tag else { return }
                coreManager.setActiveVersion(coreID: core.id, tag: tag)
            }
        }
        .onAppear { selectedTag = core.activeVersionTag }
    }
}
