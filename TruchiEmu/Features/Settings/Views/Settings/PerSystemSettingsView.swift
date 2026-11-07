import SwiftUI
import UniformTypeIdentifiers

// MARK: - Systems Column

/// Middle navigation column: the list of active and available systems.
///
/// When `isCompact` is true the column renders as an icon rail so it can stay
/// visible behind the options column.
struct PerSystemSystemsColumn: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SystemDatabaseWrapper.self) private var systemDB
    @ObservedObject private var loc = LocalizationManager.shared

    let activeSystemIDs: Set<String>
    let selectedSystemID: String?
    let isCompact: Bool
    @Binding var searchText: String
    let onSelect: (SystemInfo) -> Void

    @State private var showAvailableSystems = true

    private var sortedSystems: (active: [SystemInfo], inactive: [SystemInfo]) {
        let all = systemDB.systemsForDisplay
        let active = all.filter { activeSystemIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let inactive = all.filter { !activeSystemIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (active, inactive)
    }

    private func matches(_ system: SystemInfo) -> Bool {
        let q = searchText.lowercased()
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

    var body: some View {
        let (active, inactive) = sortedSystems
        let filteredActive = isCompact ? active : active.filter { matches($0) }
        let filteredInactive = isCompact ? inactive : inactive.filter { matches($0) }

        return ScrollView {
            VStack(spacing: 2) {
                // Headers stay in the layout when the column is a rail, so the
                // rows keep their vertical position during the slide.
                if !filteredActive.isEmpty {
                    sectionHeader(key: "perSystem.activeSystems", icon: "checkmark.circle.fill", collapsible: false)
                    ForEach(filteredActive, id: \.id) { system in
                        row(for: system, isInactive: false)
                    }
                }
                if !filteredActive.isEmpty && !filteredInactive.isEmpty {
                    Rectangle()
                        .fill(AppColors.divider(colorScheme))
                        .frame(height: 1)
                        .padding(.vertical, 6)
                }
                if !filteredInactive.isEmpty {
                    sectionHeader(key: "perSystem.availableSystems", icon: "icloud.and.arrow.down", collapsible: true)
                    if showAvailableSystems || !searchText.isEmpty {
                        ForEach(filteredInactive, id: \.id) { system in
                            row(for: system, isInactive: true)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, isCompact ? 0 : 8)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
    }

    @ViewBuilder
    private func row(for system: SystemInfo, isInactive: Bool) -> some View {
        PerSystemSystemRow(
            system: system,
            isSelected: selectedSystemID == system.id,
            isInactive: isInactive,
            isCompact: isCompact,
            colorScheme: colorScheme
        ) {
            onSelect(system)
        }
    }

    @ViewBuilder
    private func sectionHeader(key: String, icon: String, collapsible: Bool) -> some View {
        if collapsible {
            Button {
                showAvailableSystems.toggle()
            } label: {
                HStack {
                    Label(loc.localized(key), systemImage: icon)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
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
            .opacity(isCompact ? 0 : 1)
            .allowsHitTesting(!isCompact)
        } else {
            HStack {
                Label(loc.localized(key), systemImage: icon)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .opacity(isCompact ? 0 : 1)
        }
    }
}

private struct PerSystemSystemRow: View, Equatable {
    let system: SystemInfo
    let isSelected: Bool
    let isInactive: Bool
    let isCompact: Bool
    let colorScheme: ColorScheme
    let action: () -> Void
    @State private var isHovered = false

    static func == (lhs: PerSystemSystemRow, rhs: PerSystemSystemRow) -> Bool {
        lhs.system.id == rhs.system.id &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isInactive == rhs.isInactive &&
        lhs.isCompact == rhs.isCompact
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                systemIcon
                    .frame(width: 24)

                if !isCompact {
                    Text(system.name)
                        .font(AppTypography.callout)
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                        .fontWeight(isSelected ? .medium : .regular)
                        .lineLimit(1)

                    Spacer()

                    if isInactive {
                        Image(systemName: "circle.dotted")
                            .font(.caption2)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                }
            }
            // Same trick as the main sidebar: a fixed row height prevents the
            // rows from drifting vertically when the column collapses to a rail.
            .frame(height: 18)
            .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(isSelected ? AppColors.accentBackground(colorScheme) : (isHovered ? AppColors.cardBackgroundSubtle(colorScheme) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(system.name)
    }

    /// The system icon from the library, so the list and its rail are quick to
    /// scan. Systems without a bundled icon keep their SF Symbol.
    @ViewBuilder
    private var systemIcon: some View {
        if let image = system.emuImage(size: 132) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 18)
        } else {
            Image(systemName: system.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isSelected ? AppColors.brandAccent : (isHovered ? AppColors.brandAccent : AppColors.textSecondary(colorScheme)))
        }
    }
}

// MARK: - Options Column

/// Right navigation column: the per-system option categories.
///
/// An active system shows every category. An inactive system shows a single
/// "Setup" row that maps to the inactive-system placeholder.
struct PerSystemOptionsColumn: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    let system: SystemInfo
    let isActive: Bool
    let selectedCategory: PerSystemCategory?
    let onSelect: (PerSystemCategory?) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                // The system name, in the same style as the main sidebar titles,
                // so the options panel says which system it belongs to.
                HStack {
                    Text(system.name.uppercased())
                        .font(AppTypography.sectionHeader)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 4)

                if isActive {
                    ForEach(PerSystemCategory.allCases) { category in
                        row(
                            icon: category.icon,
                            title: loc.localized(category.labelKey),
                            isSelected: selectedCategory == category
                        ) {
                            onSelect(category)
                        }
                    }
                } else {
                    row(
                        icon: "square.and.arrow.down",
                        title: loc.localized("perSystem.setup"),
                        isSelected: true
                    ) {
                        onSelect(nil)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
    }

    @ViewBuilder
    private func row(icon: String, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        PerSystemOptionRow(icon: icon, title: title, isSelected: isSelected, colorScheme: colorScheme, action: action)
    }
}

private struct PerSystemOptionRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(width: 20)
                    .fixedSize()
                    .foregroundColor(isSelected ? AppColors.brandAccent : (isHovered ? AppColors.brandAccent : AppColors.textSecondary(colorScheme)))

                Text(title)
                    .font(AppTypography.callout)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(isSelected ? AppColors.accentBackground(colorScheme) : (isHovered ? AppColors.cardBackgroundSubtle(colorScheme) : .clear))
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
        .onHover { isHovered = $0 }
    }
}

// MARK: - Detail

/// Right detail pane for the Per-System section. Shows the system header and the
/// selected option, or the inactive-system placeholder.
struct PerSystemDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var prefs = SystemPreferences.shared
    @ObservedObject private var achievementsService = RetroAchievementsService.shared

    let system: SystemInfo
    let category: PerSystemCategory?
    let isActive: Bool
    let onBrowseCores: () -> Void
    @Binding var searchText: String

    @State private var showCoreImporter = false
    @State private var coreImportError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if isActive {
                systemHeader
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)

                Rectangle()
                    .fill(AppColors.divider(colorScheme))
                    .frame(height: 1)

                content
            } else {
                inactiveSystemPlaceholder
            }
        }
    }

    // MARK: - Header

    private var systemHeader: some View {
        HStack(spacing: AppSpacing.md) {
            systemHeaderIcon
                .frame(width: 32, height: 32)

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

    /// Title icon: the system icon from the library, with the SF Symbol as a
    /// fallback for systems that have no bundled image.
    @ViewBuilder
    private var systemHeaderIcon: some View {
        if let image = system.emuImage(size: 132) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: system.iconName)
                .font(.title)
                .foregroundColor(AppColors.brandAccent)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch category {
        case .shader:
            PerSystemShaderView(systemID: system.id)
        case .controls:
            ControllerSettingsView(systemID: system.id, searchText: $searchText)
        case .cheats:
            CheatSettingsView(systemID: system.id, searchText: $searchText)
        case .boxArt:
            boxArtStyleView
        case .core:
            coreView
        case .achievements:
            achievementsSettingsView
        case .bezel:
            BezelSettingsView(systemID: system.id, searchText: $searchText)
        case nil:
            EmptyView()
        }
    }

    private var boxArtStyleView: some View {
        Form {
            Section(header: Label(loc.localized("library.boxArtStyle"), systemImage: "photo.stack")) {
                Picker(loc.localized("library.boxArtStyle"), selection: Binding<BoxType>(
                    get: { prefs.boxType(for: system.id) },
                    set: { prefs.setBoxType($0, for: system.id) }
                )) {
                    ForEach(BoxType.allCases) { type in
                        Label(loc.localized(type.localizationKey), systemImage: type.iconName).tag(type)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
    }

    private var coreView: some View {
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
                } else if coreManager.isFetchingCoreList || LibretroInfoManager.shared.isRefreshing {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(loc.localized("cores.updatingSystemsCores"))
                    }
                } else {
                    SettingsActionButton(loc.localized("cores.checkForUpdates"), systemImage: "arrow.triangle.2.circlepath") {
                        Task { await coreManager.performFullSystemUpdate() }
                    }
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

    private var achievementsSettingsView: some View {
        let perSystemKey = "ra_hardcore_system_\(system.id)"

        return Form {
            Section(header: Label(loc.localized("hardcore.perSystem"), systemImage: "shield.lefthalf.filled")) {
                CompactSegmentedPicker(
                    options: [
                        .init(id: 0, title: "\(loc.localized("hardcore.useDefault")) (\(loc.localized(achievementsService.hardcoreMode ? "hardcore.enabled" : "hardcore.disabled")))"),
                        .init(id: 1, title: loc.localized("hardcore.enabled")),
                        .init(id: 2, title: loc.localized("hardcore.disabled"))
                    ],
                    selection: Binding<Int>(
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
                    )
                )
                .disabled(!achievementsService.isEnabled)
                .opacity(achievementsService.isEnabled ? 1 : 0.5)

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

    // MARK: - Inactive Placeholder

    @ViewBuilder
    private var inactiveSystemPlaceholder: some View {
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
                    addLibraryFolder()
                } label: {
                    Label(loc.localized("perSystem.addRomFolder"), systemImage: "folder.badge.plus")
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                SettingsActionButton(loc.localized("perSystem.browseCores"), systemImage: "magnifyingglass.circle") {
                    onBrowseCores()
                }
                .controlSize(.large)
            }

            SettingsActionButton(loc.localized("cores.importCustom"), systemImage: "square.and.arrow.down") {
                showCoreImporter = true
            }
            .controlSize(.large)
            .disabled(coreManager.isDownloadingCore)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .fileImporter(isPresented: $showCoreImporter, allowedContentTypes: [.zip, .item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let ext = url.pathExtension.lowercased()
                guard ext == "zip" || ext == "dylib" else {
                    coreImportError = url.lastPathComponent
                    return
                }
                Task {
                    do {
                        _ = try await coreManager.installCustomCore(from: url, systemIDs: [system.id])
                    } catch {
                        coreImportError = error.localizedDescription
                    }
                }
            case .failure(let error):
                coreImportError = error.localizedDescription
            }
        }
        .alert(loc.localized("cores.importFailed"), isPresented: Binding(
            get: { coreImportError != nil },
            set: { if !$0 { coreImportError = nil } }
        )) {
            Button(loc.localized("general.cancel"), role: .cancel) { coreImportError = nil }
        } message: {
            Text(coreImportError ?? "")
        }
    }

    private func addLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = loc.localized("library.addFolder")

        if panel.runModal() == .OK, let url = panel.url {
            library.addPrimaryFolder(url: url)
            NotificationCenter.default.post(name: .closeAppSettings, object: nil)
        }
    }
}

// MARK: - Per-System Shader Settings

struct PerSystemShaderView: View {
    let systemID: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SystemDatabaseWrapper.self) private var systemDB
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var shaderManager = ShaderManager.shared
    @ObservedObject private var slangDiscovery = SlangPresetDiscoveryService.shared
    @State private var shaderWindowSettings: ShaderWindowSettings?
    @State private var selectedCategory: CategoryFilter = .all
    @State private var chipHover: CategoryFilter? = nil
    @State private var localSearchText: String = ""
    @State private var expandedSlangGroups: Set<String> = ["curated"]
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
        let activeFill = AppColors.selectedFill(for: AppColors.brandAccent)
        return Button {
            withAnimation {
                selectedCategory = filter
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                Text("(\(count))")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    isActive ? activeFill
                        : (chipHover == filter ? AppColors.accentBackground(colorScheme) : AppColors.cardBackgroundSubtle(colorScheme))
                )
            )
            .foregroundColor(
                isActive ? AppColors.textOnAccent(for: activeFill, colorScheme: colorScheme)
                    : (chipHover == filter ? AppColors.brandAccent : .primary)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .onHover { chipHover = $0 ? filter : nil }
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
            } else if localSearchText.isEmpty {
                groupedSlangPresetsListContent
            } else {
                ForEach(visibleSlangPresets, id: \.id) { preset in
                    slangPresetRow(preset: preset)
                }
            }
        }
    }

    private var groupedSlangPresetsListContent: some View {
        VStack(spacing: 0) {
            let curated = slangDiscovery.curatedPresets
            if !curated.isEmpty {
                slangGroupHeader(group: "curated", count: curated.count)
                if expandedSlangGroups.contains("curated") {
                    ForEach(curated, id: \.id) { preset in
                        slangPresetRow(preset: preset)
                    }
                }
                Divider()
                    .padding(.vertical, 8)
            }

            let grouped = slangDiscovery.presetsByGroup()
            ForEach(grouped, id: \.group) { section in
                if !curated.contains(where: { $0.group == section.group }) {
                    slangGroupHeader(group: section.group, count: section.presets.count)
                    if expandedSlangGroups.contains(section.group) {
                        ForEach(section.presets, id: \.id) { preset in
                            slangPresetRow(preset: preset)
                        }
                    }
                }
            }
        }
    }

    private func slangGroupHeader(group: String, count: Int) -> some View {
        let isExpanded = expandedSlangGroups.contains(group)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isExpanded {
                    expandedSlangGroups.remove(group)
                } else {
                    expandedSlangGroups.insert(group)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                Text(groupDisplayName(group))
                    .font(.caption.bold())
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(AppColors.textPrimary(colorScheme))
    }

    private func groupDisplayName(_ group: String) -> String {
        if group == "curated" || group == "presets" { return loc.localized("shader.curated") }
        return group.replacingOccurrences(of: "/", with: " / ").capitalized
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
        return source.filter { $0.matchesSearchQuery(localSearchText) }
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
                    Text(preset.rawFileName)
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
            .help(preset.rawFileName)
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

// MARK: - Compact Segmented Picker

/// A segmented control whose segments are as wide as their text.
/// `Picker` with the `.segmented` style gives every segment an equal width, which
/// clips long labels in narrow panes.
private struct CompactSegmentedPicker: View {
    struct Option: Identifiable {
        let id: Int
        let title: String
    }

    let options: [Option]
    @Binding var selection: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    selection = option.id
                } label: {
                    Text(option.title)
                        .font(.callout)
                        .lineLimit(1)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                .fill(selection == option.id ? AppColors.accentBackground(colorScheme) : .clear)
                        )
                        .foregroundStyle(selection == option.id ? AppColors.brandAccent : AppColors.textPrimary(colorScheme))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
        )
        .fixedSize()
    }
}
