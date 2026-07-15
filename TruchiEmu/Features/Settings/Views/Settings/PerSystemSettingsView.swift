import SwiftUI

struct PerSystemSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(SystemDatabaseWrapper.self) private var systemDB
    @ObservedObject var prefs = SystemPreferences.shared
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager

    @State private var selectedSystemID: String?
    @State private var selectedTab: PerSystemTab = .shader
    @ObservedObject private var achievementsService = RetroAchievementsService.shared
    @StateObject private var shaderManager = ShaderManager.shared

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?
    @Binding var pendingSystemID: String?
    @State private var showAvailableSystems = true
    @State private var forceShowTabs = false

    enum PerSystemTab: String, CaseIterable, Identifiable {
        case shader = "Shader"
        case controls = "Controls"
        case cheats = "Cheats"
        case boxArt = "Box Art"
        case core = "Core"
        case achievements = "Achievements"
        case bezel = "Bezel"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .shader: return "wand.and.rays"
            case .controls: return "gamecontroller"
            case .cheats: return "wand.and.stars"
            case .boxArt: return "photo.stack"
            case .core: return "cpu"
            case .achievements: return "shield.lefthalf.filled"
            case .bezel: return "rectangle.on.rectangle"
            }
        }
    }

    init(searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil),
         pendingSystemID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
        self._pendingSystemID = pendingSystemID
    }

    var body: some View {
        let activeIDs = computeActiveSystemIDs()
        let all = systemDB.systemsForDisplay
        let active = all.filter { activeIDs.contains($0.id) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let inactive = all.filter { !activeIDs.contains($0.id) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let filteredActive: [SystemInfo] = searchText.isEmpty
            ? active
            : active.filter { systemMatchesQuery($0, query: searchText) }
        let filteredInactive: [SystemInfo] = searchText.isEmpty
            ? inactive
            : inactive.filter { systemMatchesQuery($0, query: searchText) }

        return HStack(spacing: 0) {
            // System list (left)
            systemList(activeIDs: activeIDs, filteredActive: filteredActive, filteredInactive: filteredInactive)
                .frame(width: 220)

            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(width: 1)

            // Detail (right)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(AppColors.brandAccent.opacity(0.3))
                    .frame(height: 1)

                if let sid = selectedSystemID, let system = systemDB.system(forID: sid) {
                    VStack(spacing: 0) {
                        systemHeader(system)
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.vertical, AppSpacing.md)

                        Rectangle()
                            .fill(AppColors.divider(colorScheme))
                            .frame(height: 1)

                        if activeIDs.contains(sid) || forceShowTabs {
                            tabPicker

                            tabContent(systemID: sid)
                        } else {
                            inactiveSystemPlaceholder(system)
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label(selectedSystemID == nil
                              ? loc.localized("perSystem.selectSystem")
                              : loc.localized("perSystem.systemNotFound"),
                              systemImage: "square.grid.2x2")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            forceShowTabs = false
            if let pending = pendingSystemID,
               let sys = systemDB.system(forID: pending) {
                selectedSystemID = sys.id
                pendingSystemID = nil
                forceShowTabs = true
            } else if selectedSystemID == nil {
                selectedSystemID = active.first?.id ?? inactive.first?.id
            }
        }
        .onChange(of: pendingSystemID) { _, newValue in
            guard let pid = newValue else { return }
            if let sys = systemDB.system(forID: pid) {
                selectedSystemID = sys.id
                forceShowTabs = true
                pendingSystemID = nil
            }
        }
        .onChange(of: selectedSystemID) { _, _ in
            forceShowTabs = false
        }
    }

    private func computeActiveSystemIDs() -> Set<String> {
        let systemIDsWithGames = Set(library.roms.compactMap { $0.systemID })
        let systemIDsWithCores = Set(coreManager.installedCores.flatMap { core in
            core.systemIDs.map { SystemDatabase.normalizeSystemID($0) }
        })

        var result = Set<String>()
        for system in systemDB.systemsForDisplay {
            let internalIDs = systemDB.allInternalIDs(forDisplayID: system.id)
            let hasGames = internalIDs.contains { systemIDsWithGames.contains($0) }
            let hasCores = internalIDs.contains { systemIDsWithCores.contains($0) }
            if hasGames || hasCores {
                result.insert(system.id)
            }
        }
        return result
    }

    private func systemMatchesQuery(_ system: SystemInfo, query: String) -> Bool {
        let q = query.lowercased()
        guard !q.isEmpty else { return true }
        let sysName = system.name.lowercased()
        let sysId = system.id.lowercased()
        if sysId == q { return true }
        let queryTokens = q.split(whereSeparator: { !$0.isLetter }).map { String($0) }
        let nameTokens = sysName.split(whereSeparator: { !$0.isLetter }).map { String($0) }
        let idTokens = sysId.split(whereSeparator: { !$0.isLetter }).map { String($0) }
        if queryTokens.contains(where: { nameTokens.contains($0) || idTokens.contains($0) }) { return true }
        if nameTokens.contains(where: { $0.hasPrefix(q) || $0.contains(q) }) { return true }
        if idTokens.contains(where: { $0.hasPrefix(q) || $0.contains(q) }) { return true }
        return false
    }

    // MARK: - System List

    private enum SidebarItem: Identifiable {
        case sectionHeader(String, String, Bool)
        case divider
        case system(SystemInfo, isInactive: Bool)

        var id: String {
            switch self {
            case .sectionHeader(let key, _, _): return "header-\(key)"
            case .divider: return "divider"
            case .system(let sys, _): return "system-\(sys.id)"
            }
        }
    }

    private func buildSidebarItems(filteredActive: [SystemInfo], filteredInactive: [SystemInfo]) -> [SidebarItem] {
        var items: [SidebarItem] = []
        if !filteredActive.isEmpty {
            items.append(.sectionHeader("perSystem.activeSystems", "checkmark.circle.fill", false))
            for system in filteredActive {
                items.append(.system(system, isInactive: false))
            }
        }
        if !filteredActive.isEmpty && !filteredInactive.isEmpty {
            items.append(.divider)
        }
        if !filteredInactive.isEmpty {
            items.append(.sectionHeader("perSystem.availableSystems", "icloud.and.arrow.down", true))
            if showAvailableSystems || !searchText.isEmpty {
                for system in filteredInactive {
                    items.append(.system(system, isInactive: true))
                }
            }
        }
        return items
    }

    private func systemList(activeIDs: Set<String>, filteredActive: [SystemInfo], filteredInactive: [SystemInfo]) -> some View {
        let items = buildSidebarItems(filteredActive: filteredActive, filteredInactive: filteredInactive)
        return ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(items) { item in
                    switch item {
                    case .sectionHeader(let key, let icon, let isCollapsible):
                        if isCollapsible {
                            Button {
                                showAvailableSystems.toggle()
                            } label: {
                                HStack {
                                    Label(loc.localized(key), systemImage: icon)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.textSecondary(colorScheme))
                                    Spacer()
                                    Image(systemName: showAvailableSystems ? "chevron.down" : "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(AppColors.textSecondary(colorScheme))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        } else {
                            HStack {
                                Label(loc.localized(key), systemImage: icon)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.textSecondary(colorScheme))
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        }

                    case .divider:
                        Rectangle()
                            .fill(AppColors.divider(colorScheme))
                            .frame(height: 1)
                            .padding(.vertical, 6)

                    case .system(let system, let isInactive):
                        PerSystemSystemRow(
                            system: system,
                            isSelected: selectedSystemID == system.id,
                            isInactive: isInactive,
                            colorScheme: colorScheme
                        ) {
                            selectedSystemID = system.id
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(width: 1)
        }
    }

    // MARK: - System Header

    private func systemHeader(_ system: SystemInfo) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: system.iconName)
                .font(.title)
                .foregroundColor(AppColors.brandAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(system.name)
                    .font(.headline)
                Text(system.manufacturer)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            Spacer()
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(PerSystemTab.allCases) { tab in
                Label(tab.rawValue, systemImage: tab.icon).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(systemID: String) -> some View {
        switch selectedTab {
        case .shader:
            PerSystemShaderView(systemID: systemID)
        case .controls:
            ControllerSettingsView(systemID: systemID, searchText: $searchText)
        case .cheats:
            CheatSettingsView(systemID: systemID, searchText: $searchText)
        case .boxArt:
            boxArtStyleView(systemID: systemID)
        case .core:
            if let system = systemDB.system(forID: systemID) {
                VStack(spacing: 0) {
                    HStack {
                        if coreManager.isFetchingCoreList {
                            HStack(spacing: AppSpacing.md) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(loc.localized("cores.fetchingCoreList"))
                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                                    .font(.caption)
                            }
                        } else {
                            Button {
                                Task { await coreManager.performFullSystemUpdate() }
                            } label: {
                                HStack {
                                    if coreManager.isFetchingCoreList || LibretroInfoManager.shared.isRefreshing {
                                        ProgressView().controlSize(.small)
                                        Text(loc.localized("cores.updatingSystemsCores"))
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text(loc.localized("cores.checkForUpdates"))
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(coreManager.isFetchingCoreList || LibretroInfoManager.shared.isRefreshing)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)

                    SystemCoresView(system: system, coreManager: coreManager)
                        .id(coreManager.installedCores.count + coreManager.availableCores.count)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .achievements:
            achievementsSettingsView(systemID: systemID)
        case .bezel:
            BezelSettingsView(systemID: systemID, searchText: $searchText)
        }
    }

    // MARK: - Box Art Style tab (inline per-system)

    private func boxArtStyleView(systemID: String) -> some View {
        Form {
            Section(header: Label(loc.localized("library.boxArtStyle"), systemImage: "photo.stack")) {
                Picker(loc.localized("library.boxArtStyle"), selection: Binding<BoxType>(
                    get: { prefs.boxType(for: systemID) },
                    set: { prefs.setBoxType($0, for: systemID) }
                )) {
                    ForEach(BoxType.allCases) { type in
                        Label(type.rawValue, systemImage: type.iconName).tag(type)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
    }

    private func achievementsSettingsView(systemID: String) -> some View {
        let perSystemKey = "ra_hardcore_system_\(systemID)"

        return Form {
            Section(header: Label(loc.localized("hardcore.perSystem"), systemImage: "shield.lefthalf.filled")) {
                Picker(loc.localized("hardcore.perSystem"), selection: Binding<Int>(
                    get: {
                        if !achievementsService.isEnabled { return 0 }
                        if let perSystem = AppSettings.get(perSystemKey, type: Bool.self) {
                            return perSystem ? 1 : 2
                        }
                        return 0
                    },
                    set: { newValue in
                        switch newValue {
                        case 0:
                            AppSettings.remove(perSystemKey)
                        case 1:
                            AppSettings.setBool(perSystemKey, value: true)
                        case 2:
                            AppSettings.setBool(perSystemKey, value: false)
                        default:
                            break
                        }
                    }
                )) {
                    Text("\(loc.localized("hardcore.useDefault")) (\(loc.localized(achievementsService.hardcoreMode ? "hardcore.enabled" : "hardcore.disabled")))").tag(0)
                    Text(loc.localized("hardcore.enabled")).tag(1)
                    Text(loc.localized("hardcore.disabled")).tag(2)
                }
                .pickerStyle(.segmented)
                .disabled(!achievementsService.isEnabled)

                if !achievementsService.isEnabled {
                    Text(loc.localized("hardcore.requireRA"))
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                }
            }
            Section {
                Text(loc.localized("hardcore.perSystemDescription"))
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func inactiveSystemPlaceholder(_ system: SystemInfo) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "gamecontroller")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary(colorScheme))

            VStack(spacing: 8) {
                Text(loc.localized("perSystem.noGamesOrCores"))
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                    .multilineTextAlignment(.center)

                Text(loc.localized("perSystem.noGamesOrCoresDescription"))
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                Button {
                    addLibraryFolder(for: system)
                } label: {
                    Label(loc.localized("perSystem.addRomFolder"), systemImage: "folder.badge.plus")
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    browseCores(for: system)
                } label: {
                    Label(loc.localized("perSystem.browseCores"), systemImage: "magnifyingglass.circle")
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func addLibraryFolder(for system: SystemInfo) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = loc.localized("library.addFolder")

        if panel.runModal() == .OK, let url = panel.url {
            library.addPrimaryFolder(url: url)
            NotificationCenter.default.post(name: .closeAppSettings, object: nil)
        }
    }

    private func browseCores(for system: SystemInfo) {
        forceShowTabs = true
        selectedTab = .core
        let internalIDs = systemDB.allInternalIDs(forDisplayID: system.id)
        if let firstID = internalIDs.first {
            AppSettings.set("pending_settings_system_id", value: firstID)
        }
    }
}

private struct PerSystemSystemRow: View, Equatable {
    let system: SystemInfo
    let isSelected: Bool
    let isInactive: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    static func == (lhs: PerSystemSystemRow, rhs: PerSystemSystemRow) -> Bool {
        lhs.system.id == rhs.system.id &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isInactive == rhs.isInactive
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: system.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? AppColors.brandAccent : AppColors.textSecondary(colorScheme))
                    .frame(width: 24)

                Text(system.name)
                    .font(AppTypography.callout)
                    .foregroundColor(isSelected ? AppColors.textPrimary(colorScheme) : AppColors.textSecondary(colorScheme))
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)

                Spacer()

                if isInactive {
                    Image(systemName: "circle.dotted")
                        .font(.caption2)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(isSelected ? AppColors.accentBackground(colorScheme) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Per-System Shader Settings

private struct PerSystemShaderView: View {
    let systemID: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SystemDatabaseWrapper.self) private var systemDB
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var shaderManager = ShaderManager.shared
    @ObservedObject private var slangDiscovery = SlangPresetDiscoveryService.shared
    @State private var shaderWindowSettings: ShaderWindowSettings?
    @State private var selectedCategory: CategoryFilter = .all
    @State private var localSearchText: String = ""
    @State private var savedPresets: [SavedShaderPreset] = []

    enum CategoryFilter: Hashable {
        case all, builtin(ShaderType), saved, slang
    }

    private var system: SystemInfo? {
        systemDB.system(forID: systemID)
    }

    private var currentPresetID: String {
        system?.defaultShaderPresetID ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            currentShaderHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            searchBarView
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            categoryTabs

            Divider()

            presetList
        }
        .onAppear {
            savedPresets = ShaderPresetStorageService.shared.savedPresets
        }
        .onReceive(ShaderPresetStorageService.shared.$savedPresets) { presets in
            savedPresets = presets
        }
    }

    // MARK: - Current Shader Header

    private var currentShaderHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.localized("shader.currentShader"))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                Text(ShaderManager.displayName(for: currentPresetID))
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            Button(loc.localized("shader.advanced")) {
                presentShaderWindow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(loc.localized("shader.resetToNone")) {
                resetShader()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
            .disabled(currentPresetID.isEmpty || currentPresetID == ShaderPreset.defaultPreset.id)
        }
    }

    // MARK: - Search Bar

    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            TextField(loc.localized("shader.searchShaders"), text: $localSearchText)
                .textFieldStyle(.plain)
            if !localSearchText.isEmpty {
                Button(loc.localized("shader.clear"), systemImage: "xmark.circle.fill") {
                    localSearchText = ""
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(6)
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(title: loc.localized("shader.all"), filter: .all, count: ShaderPreset.allPresets.count + savedPresets.count + slangDiscovery.curatedPresets.count, isActive: selectedCategory == .all)

                ForEach(ShaderType.allCases, id: \.self) { type in
                    let count = filteredBuiltinPresets(for: type).count
                    if count > 0 {
                        categoryChip(title: type.displayName, filter: .builtin(type), count: count, isActive: selectedCategory == .builtin(type))
                    }
                }

                categoryChip(title: loc.localized("shader.saved"), filter: .saved, count: visibleSavedPresets.count, isActive: selectedCategory == .saved)

                if !slangDiscovery.presets.isEmpty {
                    categoryChip(title: "Slang", filter: .slang, count: visibleSlangPresets.count, isActive: selectedCategory == .slang)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func categoryChip(title: String, filter: CategoryFilter, count: Int, isActive: Bool) -> some View {
        Button {
            withAnimation {
                selectedCategory = filter
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(isActive ? AppColors.textOnAccent(colorScheme).opacity(0.7) : AppColors.textSecondaryNeutral(colorScheme))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isActive ? AppColors.brandAccent : AppColors.cardBackgroundSubtle(colorScheme))
            .foregroundColor(isActive ? AppColors.textOnAccent(colorScheme) : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preset List

    private var presetList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                switch selectedCategory {
                case .saved:
                    savedPresetsListContent
                case .slang:
                    slangPresetsListContent
                case .all:
                    allPresetsListContent
                default:
                    builtinPresetsListContent
                }
            }
            .padding(8)
        }
    }

    private var allPresetsListContent: some View {
        VStack(spacing: 0) {
            if !visibleSavedPresets.isEmpty {
                sectionHeader(loc.localized("shader.saved"))
                ForEach(visibleSavedPresets, id: \.id) { preset in
                    savedPresetRow(preset: preset)
                }
            }
            if !visibleBuiltinPresets.isEmpty {
                if !visibleSavedPresets.isEmpty {
                    Divider().padding(.vertical, 8)
                }
                sectionHeader(loc.localized("shader.builtIn"))
                ForEach(visibleBuiltinPresets, id: \.id) { preset in
                    presetRow(preset: preset)
                }
            }
            if !visibleSlangPresets.isEmpty {
                if !visibleSavedPresets.isEmpty || !visibleBuiltinPresets.isEmpty {
                    Divider().padding(.vertical, 8)
                }
                sectionHeader("Slang")
                ForEach(visibleSlangPresets, id: \.id) { preset in
                    slangPresetRow(preset: preset)
                }
            }
            if visibleSavedPresets.isEmpty && visibleBuiltinPresets.isEmpty && visibleSlangPresets.isEmpty {
                Text(loc.localized("shader.noShadersFound"))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .padding()
            }
        }
    }

    private var builtinPresetsListContent: some View {
        let presets = visibleBuiltinPresets
        return VStack(spacing: 0) {
            if presets.isEmpty {
                Text(loc.localized("shader.noShadersFound"))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .padding()
            } else {
                ForEach(presets, id: \.id) { preset in
                    presetRow(preset: preset)
                }
            }
        }
    }

    private var savedPresetsListContent: some View {
        Group {
            if visibleSavedPresets.isEmpty {
                Text(savedPresets.isEmpty ? loc.localized("shader.noSavedPresets") : loc.localized("shader.noMatchesFound"))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .padding()
            } else {
                ForEach(visibleSavedPresets, id: \.id) { preset in
                    savedPresetRow(preset: preset)
                }
            }
        }
    }

    private var slangPresetsListContent: some View {
        Group {
            if visibleSlangPresets.isEmpty {
                Text("No slang shaders found")
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .padding()
            } else {
                ForEach(visibleSlangPresets, id: \.id) { preset in
                    slangPresetRow(preset: preset)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundColor(AppColors.textSecondary(colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
    }

    // MARK: - Preset Filtering

    private var visibleBuiltinPresets: [ShaderPreset] {
        switch selectedCategory {
        case .all:
            break
        case .builtin(let type):
            return ShaderPreset.allPresets.filter { $0.shaderType == type }
        case .saved, .slang:
            return []
        }
        let filtered = ShaderPreset.allPresets
        if localSearchText.isEmpty { return filtered }
        let search = localSearchText.lowercased()
        return filtered.filter { preset in
            preset.name.lowercased().contains(search) ||
            preset.description?.lowercased().contains(search) == true ||
            preset.recommendedSystems.contains { $0.lowercased().contains(search) }
        }
    }

    private var visibleSavedPresets: [SavedShaderPreset] {
        if localSearchText.isEmpty { return savedPresets }
        let search = localSearchText.lowercased()
        return savedPresets.filter { $0.name.lowercased().contains(search) }
    }

    private var visibleSlangPresets: [SlangPreset] {
        let source: [SlangPreset]
        if selectedCategory == .all && localSearchText.isEmpty {
            source = slangDiscovery.curatedPresets
        } else {
            source = slangDiscovery.presets
        }
        if localSearchText.isEmpty { return source }
        let search = localSearchText.lowercased()
        return source.filter { preset in
            preset.displayName.lowercased().contains(search) ||
            preset.category.lowercased().contains(search)
        }
    }

    private func filteredBuiltinPresets(for type: ShaderType) -> [ShaderPreset] {
        let search = localSearchText.lowercased()
        let categoryFiltered = ShaderPreset.allPresets.filter { $0.shaderType == type }
        if search.isEmpty { return categoryFiltered }
        return categoryFiltered.filter { preset in
            preset.name.lowercased().contains(search) ||
            preset.description?.lowercased().contains(search) == true
        }
    }

    // MARK: - Preset Row

    private func presetRow(preset: ShaderPreset) -> some View {
        VStack(spacing: 0) {
            ShaderPresetRowView(
                preset: preset,
                isSelected: preset.id == currentPresetID,
                onSelect: { selectShader(preset.id) }
            )
            Divider()
                .padding(.leading, 40)
                .opacity(0.5)
        }
    }

    private func savedPresetRow(preset: SavedShaderPreset) -> some View {
        VStack(spacing: 0) {
            SavedPresetRowView(
                preset: preset,
                isSelected: preset.id.uuidString == currentPresetID,
                onSelect: {
                    systemDB.updateSystemShaderPreset(systemID: systemID, presetID: preset.id.uuidString)
                    shaderManager.activateSavedPreset(preset)
                },
                onRename: {},
                onExport: {},
                onDelete: {
                    ShaderPresetStorageService.shared.delete(preset: preset)
                    savedPresets = ShaderPresetStorageService.shared.savedPresets
                }
            )
            Divider()
                .padding(.leading, 40)
                .opacity(0.5)
        }
    }

    private func slangPresetRow(preset: SlangPreset) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.body)
                    .frame(width: 24)
                    .foregroundColor(preset.path.path == currentPresetID ? AppColors.brandAccent : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.displayName)
                        .font(.subheadline.weight(preset.path.path == currentPresetID ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundColor(preset.path.path == currentPresetID ? AppColors.brandAccent : .primary)
                    Text(preset.category)
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                        .lineLimit(1)
                }

                Spacer()

                if !preset.parameters.isEmpty {
                    Text("⚙️ \(preset.parameters.count)")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.cardBackground(colorScheme))
                        .cornerRadius(4)
                }

                if preset.path.path == currentPresetID {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.brandAccent)
                        .font(.body)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if preset.path.path == currentPresetID {
                    AppColors.brandAccent.opacity(0.2).cornerRadius(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                systemDB.updateSystemShaderPreset(systemID: systemID, presetID: preset.path.path)
                shaderManager.activateSlangPreset(preset)
            }

            Divider()
                .padding(.leading, 40)
                .opacity(0.5)
        }
    }

    private func selectShader(_ id: String) {
        systemDB.updateSystemShaderPreset(systemID: systemID, presetID: id)
        shaderManager.activatePresetWithOverrides(presetID: id, overrides: [:])
    }

    private func resetShader() {
        systemDB.updateSystemShaderPreset(systemID: systemID, presetID: "")
        shaderManager.resetToDefault()
    }

    @MainActor
    private func presentShaderWindow() {
        shaderWindowSettings = ShaderWindowSettings(
            shaderPresetID: currentPresetID,
            uniformValues: shaderManager.uniformValues,
            systemID: systemID
        )

        let windowController = ShaderWindowController(
            settings: shaderWindowSettings!
        ) { [self] newPresetID, newUniformValues, _ in
            systemDB.updateSystemShaderPreset(systemID: systemID, presetID: newPresetID)
            let isSlang = SlangPresetDiscoveryService.shared.presets.contains { $0.path.path == newPresetID }
            if isSlang {
                shaderManager.activateSlangPreset(
                    SlangPresetDiscoveryService.shared.presets.first { $0.path.path == newPresetID }!,
                    overrides: newUniformValues
                )
            } else if let preset = ShaderPreset.preset(id: newPresetID) {
                shaderManager.activatePreset(preset)
                for (key, value) in newUniformValues { shaderManager.updateUniform(key, value: value) }
            } else if let savedPreset = ShaderPresetStorageService.shared.savedPresets.first(where: { $0.id.uuidString == newPresetID }) {
                shaderManager.activateSavedPreset(savedPreset)
            }
            ShaderWindowController.shared?.close()
        }

        ShaderWindowController.shared = windowController
        windowController.show()
    }
}
