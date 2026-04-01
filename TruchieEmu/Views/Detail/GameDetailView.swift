import SwiftUI

// Shown only when the user triggers an action from Game detail (e.g. Identify).
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
        case .info: return .accentColor
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

// MARK: - Section Card Component

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    var isExpanded: Bool = true
    var badge: String? = nil
    @ViewBuilder let content: Content
    @State private var expanded: Bool
    
    init(
        title: String,
        icon: String,
        isExpanded: Bool = true,
        badge: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self._expanded = State(initialValue: isExpanded)
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                    Text(title)
                        .font(.headline)
                    if let badge = badge {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                    .padding(.vertical, 8)

                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
        .animation(.easeInOut(duration: 0.2), value: expanded)
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
    @State private var gameWindowController: StandaloneGameWindowController? = nil
    @State private var boxArtImage: NSImage? = nil
    @State private var crcHash: String? = nil
    @State private var fileSize: String? = nil
    @State private var slotInfoList: [SlotInfo] = []
    @State private var gameAchievements: [Achievement] = []
    @State private var isAchievementsLoading = false
    @State private var showCheatManager = false

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
        VStack(spacing: 0) {
            // Header always visible
            compactHeaderSection

            Divider()

            // Sidebar + Content layout
            HStack(spacing: 0) {
                // Sidebar
                sidebarNavigation

                Divider()

                // Main content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                .background(Color(NSColor.windowBackgroundColor))
            }

            if manualActionStatus.isVisible {
                manualActionStatusBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
    }

    // MARK: - Sidebar Navigation

    private var sidebarNavigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sections")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(DetailSection.allCases, id: \.self) { section in
                sidebarItem(for: section)
            }

            Spacer()
        }
        .frame(width: 160)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
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
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .frame(width: 16)
                    Text(section.rawValue)
                        .lineLimit(1)
                    Spacer()
                    if isSelected {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                }
                .foregroundColor(isSelected ? .accentColor : .primary)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
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
        isAchievementsLoading = true
        // For now, we'll display placeholder achievements since game identification
        // needs proper RetroAchievements game ID mapping
        gameAchievements = []
        isAchievementsLoading = false
    }

    private func loadBoxArt() {
        if let path = currentROM.boxArtPath {
            boxArtImage = NSImage(contentsOf: path)
        } else {
            boxArtImage = nil
        }
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
                    .foregroundColor(.primary)
            case .result(let message, let tone):
                Image(systemName: tone.iconName)
                    .font(.title3)
                    .foregroundStyle(tone.foregroundColor)
                    .frame(width: 22, alignment: .center)
                Text(message)
                    .font(.callout)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if case .result = manualActionStatus {
                Button {
                    clearManualStatus()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
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
        HStack(alignment: .top, spacing: 20) {
            ZStack {
                if let img = boxArtImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    placeholderArt
                }
            }
            .frame(width: 140, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8)
            .onTapGesture { showBoxArtPicker = true }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Game Title", text: Binding(
                        get: { currentROM.customName ?? currentROM.metadata?.title ?? currentROM.name },
                        set: { newName in
                            var updated = currentROM
                            updated.customName = newName.isEmpty ? nil : newName
                            library.updateROM(updated)
                        }
                    ))
                    .font(.system(size: 24, weight: .bold))
                    .textFieldStyle(.plain)
                    
                    Spacer()
                    
                }
                
                if let sys = system {
                    HStack(spacing: 8) {
                        if let emuImg = sys.emuImage(size: 132) {
                            Image(nsImage: emuImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                        }
                        Text(sys.name)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                launchButton
            }
            .padding(.vertical, 4)
            
            Spacer()
        }
        .padding(24)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - Section 1: Game Info

    private var gameInfoSection: some View {
        SectionCard(title: "Game Info", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 12) {
                // Action buttons
                HStack(spacing: 12) {
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
                        if case .working = manualActionStatus {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Identify Game", systemImage: "qrcode.viewfinder")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isIdentifyWorking)

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
                        Label("Fetch Box Art", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                }

                Divider()

                // Metadata grid
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("System").bold().frame(width: 80, alignment: .leading)
                        Text(system?.name ?? currentROM.systemID ?? "Unknown").foregroundColor(.secondary)
                    }
                    GridRow {
                        Text("File").bold().frame(width: 80, alignment: .leading)
                        Text(currentROM.path.lastPathComponent).foregroundColor(.secondary)
                    }
                    GridRow {
                        Text("Path").bold().frame(width: 80, alignment: .leading)
                        HStack {
                            Text(currentROM.path.deletingLastPathComponent().path)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(currentROM.path.path, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc").font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Copy Full Path")
                        }
                    }

                    if let size = fileSize {
                        GridRow {
                            Text("Size").bold().frame(width: 80, alignment: .leading)
                            Text(size).foregroundColor(.secondary)
                        }
                    }

                    if let crc = crcHash {
                        GridRow {
                            Text("CRC32").bold().frame(width: 80, alignment: .leading)
                            HStack {
                                Text(crc).font(.system(.body, design: .monospaced)).foregroundColor(.secondary)
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(crc, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc").font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Copy Hash")
                            }
                        }
                    }

                    if let meta = currentROM.metadata {
                        if let original = meta.title, currentROM.customName != nil {
                            GridRow {
                                Text("Orig. Name").bold().frame(width: 80, alignment: .leading)
                                Text(original).foregroundColor(.secondary)
                            }
                        }
                        if let dev = meta.developer {
                            GridRow {
                                Text("Developer").bold().frame(width: 80, alignment: .leading)
                                Text(dev).foregroundColor(.secondary)
                            }
                        }
                        if let pub = meta.publisher {
                            GridRow {
                                Text("Publisher").bold().frame(width: 80, alignment: .leading)
                                Text(pub).foregroundColor(.secondary)
                            }
                        }
                        if let year = meta.year {
                            GridRow {
                                Text("Year").bold().frame(width: 80, alignment: .leading)
                                Text(year).foregroundColor(.secondary)
                            }
                        }
                        if let genre = meta.genre {
                            GridRow {
                                Text("Genre").bold().frame(width: 80, alignment: .leading)
                                Text(genre).foregroundColor(.secondary)
                            }
                        }
                        if let players = meta.players {
                            GridRow {
                                Text("Players").bold().frame(width: 80, alignment: .leading)
                                Text(String(players)).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if let desc = currentROM.metadata?.description {
                    Divider()
                    Text(desc)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Section 2: Shader

    private var shaderSection: some View {
        SectionCard(
            title: "Shader",
            icon: "tv",
            badge: isShaderCustomized ? "Custom" : nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Current shader display and edit button
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Shader")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Post-processing shader for this game")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(ShaderManager.displayName(for: currentROM.settings.shaderPresetID)) {
                        presentShaderWindow()
                    }
                    .buttonStyle(.bordered)
                }

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
                                    .foregroundColor(.accentColor)
                                    .frame(width: 20)
                                Text(preset.name)
                                    .font(.subheadline)
                                Spacer()
                                if currentROM.settings.shaderPresetID == preset.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                                if let desc = preset.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                currentROM.settings.shaderPresetID == preset.id
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // Reset to system default button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Default Shader")
                            .font(.caption)
                        Text("Reset to the default shader for this system")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Use System Default") {
                        updateSettings { $0.shaderPresetID = systemDefaultShaderID }
                    }
                    .buttonStyle(.bordered)
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
        SectionCard(
            title: "Controls",
            icon: "gamecontroller",
            badge: "System"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Controller display
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Controller Mapping")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Per-game controls for \(system?.name ?? "this system")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Edit Controls") {
                        showControlsPicker = true
                    }
                    .buttonStyle(.bordered)
                }

                // Controller icon display
                if let sys = system, let controllerIcon = controllerIconForSystem(sys) {
                    HStack(spacing: 16) {
                        Image(nsImage: controllerIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Default Mapping")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Uses the standard \(sys.name) controller layout")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }

                Divider()

                // Reset to system defaults
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Default Controls")
                            .font(.caption)
                        Text("Reset to the default controls for this system")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Use System Default") {
                        resetControlsToSystemDefault()
                    }
                    .buttonStyle(.bordered)
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
        // Reset keyboard mapping for this system to defaults
        let systemID = currentROM.systemID ?? ""
        controllerService.updateKeyboardMapping(
            KeyboardMapping.defaults(for: systemID),
            for: systemID
        )
    }

    // MARK: - Section 4: Saved States

    private var savedStatesSection: some View {
        SectionCard(
            title: "Saved States",
            icon: "externaldrive",
            badge: slotInfoList.filter(\.exists).isEmpty ? nil : "\(slotInfoList.filter(\.exists).count)"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                let existingSlots = slotInfoList.filter { $0.exists }
                let emptySlots = slotInfoList.filter { !$0.exists && $0.id >= 0 }.prefix(10)
                let showSlots = existingSlots.isEmpty ? Array(emptySlots) : slotInfoList.filter { $0.id >= 0 }

                if showSlots.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive.slash")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                        Text("No saved states")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Save states are created during gameplay")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                            SaveStateSlotView(
                                slot: slot,
                                rom: currentROM,
                                saveStateManager: saveStateManager,
                                onDelete: { loadSlotInfo() }
                            )
                        }
                    }
                }

                if !existingSlots.isEmpty {
                    Divider()

                    // Summary
                    HStack {
                        Text("\(existingSlots.count) save state(s)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        let totalSize = existingSlots.reduce(0) { $0 + ($1.fileSize ?? 0) }
                        if totalSize > 0 {
                            Text(Int64(totalSize).formattedByteSize)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section 5: Cheats

    private var cheatsSection: some View {
        SectionCard(
            title: "Cheats",
            icon: "wand.and.stars"
        ) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cheat Codes")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Import and manage cheat codes for this game")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Divider()

                HStack {
                    Spacer()
                    Button {
                        showCheatManager = true
                    } label: {
                        Label("Manage Cheats", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        // Note: CheatManagerView is not part of the project build phase.
        // To enable cheat management, add CheatManagerView.swift and Cheat.swift
        // to the TruchieEmu target in Xcode.
    }

    // MARK: - Section 6: Achievements

    private var achievementsSection: some View {
        SectionCard(
            title: "Achievements",
            icon: "trophy",
            badge: gameAchievements.isEmpty ? nil : "\(unlockedAchievementCount)/\(gameAchievements.count)"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if isAchievementsLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading achievements...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else if gameAchievements.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.slash")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                        Text("No achievements available")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("This game may not have RetroAchievements data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    // Summary
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(unlockedAchievementCount) of \(gameAchievements.count)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Achievements")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(earnedPoints)/\(totalAchievementPoints)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Points")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Progress bar
                        let progress = gameAchievements.isEmpty
                            ? 0.0
                            : Double(unlockedAchievementCount) / Double(gameAchievements.count)
                        ProgressView(value: progress)
                            .frame(width: 100)
                    }

                    Divider()

                    // Achievement list (limited display)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(gameAchievements.prefix(6)) { achievement in
                                AchievementBadgeView(achievement: achievement)
                            }

                            if gameAchievements.count > 6 {
                                Text("+\(gameAchievements.count - 6) more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 60)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Launch Button

    private var launchButton: some View {
        Button {
            launchGame()
        } label: {
            Label("Launch Game", systemImage: "play.fill")
                .frame(width: 200)
        }
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Placeholder Art

    private var placeholderArt: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            if let img = system?.emuImage(size: 600) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
            } else {
                Image(systemName: system?.iconName ?? "gamecontroller")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func updateSettings(_ action: (inout ROMSettings) -> Void) {
        var updated = currentROM
        action(&updated.settings)
        library.updateROM(updated)
    }

    private func launchGame() {
        guard let sysID = currentROM.systemID,
              let system = SystemDatabase.system(forID: sysID) else { return }
        
        let sysPrefs = SystemPreferences.shared
        let coreID = currentROM.useCustomCore
            ? (currentROM.selectedCoreID ?? sysPrefs.preferredCoreID(for: sysID) ?? system.defaultCoreID)
            : (sysPrefs.preferredCoreID(for: sysID) ?? system.defaultCoreID)
        
        guard let cid = coreID else { return }
        
        if !coreManager.isInstalled(coreID: cid) {
            coreManager.requestCoreDownload(for: cid, systemID: sysID)
            return
        }

        library.markPlayed(currentROM)
        
        // Activate shader preset
        let presetID = currentROM.settings.shaderPresetID.isEmpty
            ? "builtin-crt-classic"
            : currentROM.settings.shaderPresetID
        if let preset = ShaderPreset.preset(id: presetID) {
            ShaderManager.shared.activatePreset(preset)
        }
        
        let runner = EmulatorRunner.forSystem(sysID)
        let controller = StandaloneGameWindowController(runner: runner)
        self.gameWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        controller.launch(rom: currentROM, coreID: cid)
    }
}

// MARK: - Save State Slot View

struct SaveStateSlotView: View {
    let slot: SlotInfo
    let rom: ROM
    @ObservedObject var saveStateManager: SaveStateManager
    var onDelete: () -> Void
    @State private var thumbnail: NSImage?
    @State private var showContextMenu = false

    var body: some View {
        VStack(spacing: 6) {
            // Thumbnail or placeholder
            ZStack {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .overlay(
                            Image(systemName: slot.exists ? "externaldrive.fill" : "externaldrive")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .frame(width: 70, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(slot.exists ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
            )

            // Slot number
            Text(slot.displayName)
                .font(.caption)
                .fontWeight(slot.exists ? .semibold : .regular)
                .foregroundColor(slot.exists ? .primary : .secondary)

            // Date and size info
            if let date = slot.formattedDate {
                Text(date)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else if let fileSize = slot.fileSize {
                Text(fileSize.formattedByteSize)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 74)
        .contentShape(Rectangle())
        .onTapGesture {
            if slot.exists {
                // Could trigger load state action
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
                RoundedRectangle(cornerRadius: 6)
                    .fill(achievement.isUnlocked
                        ? Color.accentColor.opacity(0.2)
                        : Color.secondary.opacity(0.1))
                    .frame(width: 50, height: 50)

                Image(systemName: achievement.isUnlocked ? "trophy.fill" : "trophy")
                    .font(.system(size: 24))
                    .foregroundColor(achievement.isUnlocked ? .accentColor : .secondary)
            }

            // Points
            Text("\(achievement.points)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(achievement.isUnlocked ? .accentColor : .secondary)

            // Title
            Text(achievement.isUnlocked ? achievement.title : "???")
                .font(.system(size: 9))
                .lineLimit(1)
                .frame(width: 60)
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
                .foregroundColor(.secondary)
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
