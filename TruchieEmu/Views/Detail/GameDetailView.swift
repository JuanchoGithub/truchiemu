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

// MARK: - Collapsible Detail Section

enum DetailSection: String, CaseIterable {
    case gameInfo = "Game Info"
    case shader = "Shader"
    case controls = "Controls"
    case savedStates = "Saved States"
    case cheats = "Cheats"
    case achievements = "Achievements"
}

// MARK: - Modern Section Card Component

struct ModernSectionCard<Content: View>: View {
    let title: String?
    let icon: String?
    var isExpanded: Bool = true
    var badge: String? = nil
    var showHeader: Bool = true
    @ViewBuilder let content: Content
    @State private var expanded: Bool
    
    init(
        title: String? = nil,
        icon: String? = nil,
        isExpanded: Bool = true,
        badge: String? = nil,
        showHeader: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.showHeader = showHeader
        self._expanded = State(initialValue: isExpanded)
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader, let title = title {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expanded.toggle()
                    }
                } label: {
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
                        if icon != nil {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider()
                    .padding(.vertical, 10)
                    .overlay(Color.white.opacity(0.1))
            }

            if expanded || !showHeader {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
        .animation(.easeInOut(duration: 0.2), value: expanded)
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

                    // Main content area
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            switch selectedSection {
                            case .gameInfo:
                                gameInfoSection
                            case .shader:
                                shaderSection
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
        ZStack {
            // Deep charcoal base
            Color(red: 0.12, green: 0.13, blue: 0.16)
            
            // Blurred box art overlay
            if let img = boxArtImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 60, opaque: false)
                    .scaleEffect(1.1)
                    .opacity(0.25)
            }
        }
        .ignoresSafeArea()
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
        case .shader: return "tv"
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

    // MARK: - Compact Header

    private var compactHeaderSection: some View {
        HStack(alignment: .top, spacing: 24) {
            // Cover art with play overlay
            ZStack {
                if let img = boxArtImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    placeholderArt
                }
                
                // Play icon overlay
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white)
                    .shadow(radius: 8)
            }
            .frame(width: 160, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            .onTapGesture { showBoxArtPicker = true }

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
                    .font(.system(size: 28, weight: .bold))
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
                                .frame(width: 18, height: 18)
                        }
                        Text(sys.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                // Launch button - Pill shape
                launchButton
            }
            .padding(.vertical, 4)
            
            Spacer()
        }
        .padding(24)
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
                        ? Array(ShaderPreset.builtinPresets.prefix(4))
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
                uniformValues: [:]
            )
        } else {
            shaderWindowSettings?.shaderPresetID = currentROM.settings.shaderPresetID
        }

        let windowController = ShaderWindowController(
            settings: shaderWindowSettings!
        ) { [self] newPresetID in
            updateSettings { $0.shaderPresetID = newPresetID }
            if let preset = ShaderPreset.preset(id: newPresetID) {
                ShaderManager.shared.activatePreset(preset)
            }
        }

        ShaderWindowController.shared = windowController
        windowController.show()
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
    @State private var cheatCount: Int = 0
    @State private var enabledCheatCount: Int = 0

    private var cheatsSection: some View {
        ModernSectionCard(
            title: "Cheats",
            icon: "wand.and.stars",
            badge: cheatCount > 0 ? "\(enabledCheatCount)/\(cheatCount)" : nil
        ) {
            VStack(spacing: 14) {
                // Cheat status display
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cheat Codes")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.85))
                        
                        if cheatCount > 0 {
                            Text("\(enabledCheatCount) of \(cheatCount) enabled")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        } else {
                            Text("No cheats loaded")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                    
                    // Quick actions
                    if cheatCount > 0 {
                        Button {
                            if enabledCheatCount > 0 {
                                cheatManagerService.disableAllCheats(for: currentROM)
                            } else {
                                cheatManagerService.enableAllCheats(for: currentROM)
                            }
                        } label: {
                            Label(enabledCheatCount > 0 ? "Disable All" : "Enable All", 
                                  systemImage: enabledCheatCount > 0 ? "stop.circle" : "play.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                // Download and manage buttons
                HStack(spacing: 8) {
                    // Download cheats button
                    Button {
                        Task {
                            _ = await CheatDownloadService.shared.downloadCheatsForSystem(currentROM.systemID ?? "")
                            cheatManagerService.loadCheatsForROM(currentROM)
                            updateCheatCounts()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                            Text("Download")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.6))
                        .cornerRadius(6)
                    }
                    
                    // Import .cht file button
                    Button {
                        showImportCheatFile = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.6))
                        .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    // Manage cheats button
                    Button {
                        showCheatManager = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                            Text("Manage")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(6)
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                // Link to cheat settings
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
        }
        .onChange(of: currentROM.id) { _ in
            updateCheatCounts()
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
                    }
                }
            case .failure(let error):
                print("File import error: \(error)")
            }
        }
    }
    
    private func updateCheatCounts() {
        cheatCount = cheatManagerService.totalCount(for: currentROM)
        enabledCheatCount = cheatManagerService.enabledCount(for: currentROM)
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