import SwiftUI
import Combine

// MARK: - View Model
@MainActor
class CoreOptionsViewModel: ObservableObject {
    private let manager = CoreOptionsManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @Published var currentCoreID: String
    @Published var isSystemMode: Bool = false
    @Published var systemID: String? = nil
    @Published var availableCores: [(id: String, name: String)] = []
    let gameFilename: String?

    @Published var isLoading = false
    @Published var hasLoadedOnce = false
    @Published var searchText: String = ""

    @Published private(set) var filteredSortedKeys: [String] = []
    @Published private(set) var filteredOptionKeysByCategory: [String: [String]] = [:]

    private var cancellables = Set<AnyCancellable>()

    var options: [String: CoreOption] { manager.options }
    var categories: [String: CoreOptionCategory] { manager.categories }

    init(id: String, systemID: String? = nil, gameFilename: String? = nil) {
        if let system = SystemDatabase.system(forID: id) {
            self.currentCoreID = system.defaultCoreID ?? ""
            self.isSystemMode = true
            self.systemID = id
        } else if let displaySystem = SystemDatabase.displaySystem(forInternalID: id) {
            self.currentCoreID = displaySystem.defaultCoreID ?? ""
            self.isSystemMode = true
            self.systemID = id
        } else {
            self.currentCoreID = id
            self.isSystemMode = systemID != nil
            self.systemID = systemID
        }
        self.gameFilename = gameFilename

        manager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(manager.objectWillChange, $searchText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateFilteredData()
                }
            }
            .store(in: &cancellables)
    }

    private func updateFilteredData() {
        let allOptions = options.values
        var query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let modifiedKeyword = "is:modified"
        let isSearchingModified = query.contains(modifiedKeyword)
        if isSearchingModified {
            query = query.replacingOccurrences(of: modifiedKeyword, with: "").trimmingCharacters(in: .whitespaces)
        }

        let matchingOptions = allOptions.filter { option in
            if isSearchingModified && option.overrideSource == .coreDefault {
                return false
            }

            if query.isEmpty { return true }
            let optDesc = option.description.lowercased()
            let optInfo = option.info.lowercased()
            let optKey = option.key.lowercased()
            let optPretty = prettify(option.key).lowercased()
            return optKey.contains(query) || optDesc.contains(query) || optInfo.contains(query) || optPretty.contains(query)
        }

        var categoryToKeys: [String: [String]] = [:]
        for option in matchingOptions {
            let internalKey = "\(option.key)_\(option.version.rawValue)"
            let cat = option.category ?? ""
            categoryToKeys[cat, default: []].append(internalKey)
        }

        for (cat, keys) in categoryToKeys {
            categoryToKeys[cat] = keys.sorted { k1, k2 in
                let opt1 = options[k1]!
                let opt2 = options[k2]!
                return opt1.description < opt2.description
            }
        }

        var visibleCatKeys: Set<String> = Set(matchingOptions.compactMap { $0.category })

        if !query.isEmpty {
            let emptyCatMatches = allOptions.filter { ($0.category == nil || $0.category == "") }
                .contains { option in
                    let optDesc = option.description.lowercased()
                    let optInfo = option.info.lowercased()
                    let optKey = option.key.lowercased()
                    let optPretty = prettify(option.key).lowercased()
                    return optKey.contains(query) || optDesc.contains(query) || optInfo.contains(query) || optPretty.contains(query)
                }
            if emptyCatMatches { visibleCatKeys.insert("") }
        } else if !allOptions.isEmpty {
            if allOptions.contains(where: { $0.category == nil || $0.category == "" }) {
                visibleCatKeys.insert("")
            }
        }

        let sortedCats = visibleCatKeys.sorted { a, b in
            if a.isEmpty { return true }
            if b.isEmpty { return false }
            return (categories[a]?.description ?? "") < (categories[b]?.description ?? "")
        }

        self.filteredSortedKeys = sortedCats
        self.filteredOptionKeysByCategory = categoryToKeys
    }


    func loadOptions(for id: String, library: ROMLibrary? = nil) {
        isLoading = true

        var dylibPath: String? = nil
        if let core = CoreManager.shared.installedCores.first(where: { $0.id == id }) {
            LoggerService.debug(category: "CoreOptionsViewModel", "Found installed core: \(core.id). Versions: \(core.installedVersions.count). ActiveTag: \(core.activeVersionTag ?? "nil")")
            if let activeVersion = core.activeVersion {
                dylibPath = activeVersion.dylibPath.path
                LoggerService.debug(category: "CoreOptionsViewModel", "Resolved dylibPath: \(dylibPath!)")
            } else {
                LoggerService.debug(category: "CoreOptionsViewModel", "No active version found for core: \(id)")
            }
        } else {
            LoggerService.debug(category: "CoreOptionsViewModel", "Core \(id) not found in installedCores")
        }

        var romPath: String? = nil
        if let lib = library {
            let systemIDs = CoreManager.supportedSystems(for: id)
            if let sysID = systemIDs.first, let rom = lib.roms.first(where: { $0.systemID == sysID }) {
                romPath = rom.path.path
                LoggerService.debug(category: "CoreOptionsViewModel", "Resolved romPath: \(romPath!) for system: \(sysID)")
            } else {
                LoggerService.debug(category: "CoreOptionsViewModel", "No ROM found in library for system(s): \(systemIDs)")
            }
        }

        self.manager.setScope(systemID: self.systemID, gameFilename: self.gameFilename)
        if self.isSystemMode, let sysID = self.systemID {
            self.discoverCoresForSystem(sysID)
        } else {
            self.manager.loadForCore(coreID: id, dylibPath: dylibPath, romPath: romPath)
        }
        self.isLoading = false
        self.hasLoadedOnce = true
    }

    private func discoverCoresForSystem(_ sysID: String) {
        let compatibleIDs = SystemDatabase.compatibleIDs(for: sysID)
        let installed = CoreManager.shared.installedCores.filter { core in
            !Set(core.systemIDs).isDisjoint(with: compatibleIDs) || SystemDatabase.system(forID: sysID)?.defaultCoreID == core.id
        }

        self.availableCores = installed.map { core in
            let baseID = core.id.replacingOccurrences(of: "_libretro", with: "")
            let name = LibretroCore.knownCoreMetadata[baseID]?.displayName ?? core.id.replacingOccurrences(of: "_libretro", with: "").capitalized
            return (id: core.id, name: name)
        }

        if let system = SystemDatabase.system(forID: sysID), let defaultID = system.defaultCoreID, availableCores.contains(where: { $0.id == defaultID }) {
            self.currentCoreID = defaultID
        } else if let firstCore = availableCores.first?.id {
            self.currentCoreID = firstCore
        } else {
            self.currentCoreID = ""
        }

        if !currentCoreID.isEmpty {
            self.manager.loadForCore(coreID: currentCoreID)
        }
    }

    func prettify(_ key: String) -> String {
        let clean = key.replacingOccurrences(of: "^[a-zA-Z0-9]+_", with: "", options: .regularExpression)
        let words = clean.components(separatedBy: "_")
        let pretty = words.map { $0.capitalized }.joined(separator: " ")
        return "\(pretty) (\(key))"
    }

    func categoryDisplayName(for key: String) -> String {
        key.isEmpty ? loc.localized("coreOptions.general") : (categories[key]?.description ?? key)
    }

    func optionKeysInCategory(_ categoryKey: String) -> [String] {
        return filteredOptionKeysByCategory[categoryKey] ?? []
    }

    func updateValue(_ value: String, for key: String) {
        manager.updateValue(value, for: key)
    }

    func restoreToPreviousLayer(key: String) {
        manager.restoreToPreviousLayer(key: key)
    }

    func resetAll() {
        manager.resetAllToDefaults()
    }

    func discoverOptions(for coreID: String, library: ROMLibrary) async {
        isLoading = true
        defer { isLoading = false }

        var dylibPath: String? = nil
        if let core = CoreManager.shared.installedCores.first(where: { $0.id == coreID }) {
            if let activeVersion = core.activeVersion {
                dylibPath = activeVersion.dylibPath.path
            }
        }

        var romPath: String? = nil
        let systemIDs = CoreManager.supportedSystems(for: coreID)
        if let sysID = systemIDs.first, let rom = library.roms.first(where: { $0.systemID == sysID }) {
            romPath = rom.path.path
        }

        if let dylib = dylibPath {
            await manager.discoverOptions(for: coreID, dylibPath: dylib, romPath: romPath)
            hasLoadedOnce = true
            updateFilteredData()
        } else {
            LoggerService.error(category: "CoreOptionsViewModel", "Discovery failed: dylibPath not found for \(coreID)")
        }
    }
}

// MARK: - Main View
struct CoreOptionsView: View {
    let initialID: String
    @StateObject private var viewModel: CoreOptionsViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: ROMLibrary
    @ObservedObject private var loc = LocalizationManager.shared

    init(coreID: String, systemID: String? = nil, gameFilename: String? = nil) {
        self.initialID = coreID
        self._viewModel = StateObject(wrappedValue: CoreOptionsViewModel(id: coreID, systemID: systemID, gameFilename: gameFilename))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()

                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView().controlSize(.large)
                        Text(loc.localized("coreOptions.loading")).foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                } else if viewModel.options.isEmpty {
                    EmptyStateView(coreID: viewModel.isSystemMode ? (viewModel.systemID ?? "") : viewModel.currentCoreID, viewModel: viewModel)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            if viewModel.isSystemMode {
                                Picker(loc.localized("coreOptions.core"), selection: $viewModel.currentCoreID) {
                                    ForEach(viewModel.availableCores, id: \.id) { core in
                                        Text(core.name).tag(core.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding(.horizontal)
                                .onChange(of: viewModel.currentCoreID) { _, newID in
                                    viewModel.loadOptions(for: newID, library: library)
                                }
                                Divider()
                            }

                            ForEach(viewModel.filteredSortedKeys, id: \.self) { category in
                                CategorySection(
                                    title: viewModel.categoryDisplayName(for: category),
                                    optionKeys: viewModel.optionKeysInCategory(category),
                                    viewModel: viewModel
                                )
                            }

                            VStack(spacing: 16) {
                                Button(action: {
                                    Task { await viewModel.discoverOptions(for: viewModel.currentCoreID, library: library) }
                                }) {
                                    Label(loc.localized("coreOptions.rediscoverFromCore"), systemImage: "arrow.triangle.2.circlepath")
                                }
                                .buttonStyle(.link)

                                ResetFooter(viewModel: viewModel)
                            }
                            .padding(.top)
                        }
                        .padding()
                    }
                }
            }
        }
        .animation(.easeInOut, value: viewModel.isLoading)
        .navigationTitle(viewModel.isSystemMode ? "\(loc.localized("coreOptions.options")) \(SystemDatabase.systemName(forInternalID: viewModel.systemID ?? ""))" : "\(loc.localized("coreOptions.options")) \(viewModel.currentCoreID)")
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: loc.localized("coreOptions.searchOptions"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let currentSearch = viewModel.searchText
                    if currentSearch.contains("is:modified") {
                        viewModel.searchText = currentSearch.replacingOccurrences(of: "is:modified", with: "").trimmingCharacters(in: .whitespaces)
                    } else {
                        viewModel.searchText = (currentSearch.isEmpty ? "" : currentSearch + " ") + "is:modified"
                    }
                } label: {
                    Image(systemName: viewModel.searchText.contains("is:modified") ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundColor(viewModel.searchText.contains("is:modified") ? AppColors.brandAccent : .secondary)
                }
                .help("Filter modified options")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(loc.localized("core.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { viewModel.loadOptions(for: initialID, library: library) }
    }
}

// MARK: - Components

struct CategorySection: View {
    let title: String
    let optionKeys: [String]
    @ObservedObject var viewModel: CoreOptionsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(optionKeys, id: \.self) { key in
                    CoreOptionRow(versionedKey: key, viewModel: viewModel)
                    if key != optionKeys.last {
                        Divider().opacity(0.5).padding(.horizontal, 10)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}

struct CoreOptionRow: View {
    @ObservedObject var viewModel: CoreOptionsViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    let versionedKey: String
    @State private var selectedValue: String

    init(versionedKey: String, viewModel: CoreOptionsViewModel) {
        self.versionedKey = versionedKey
        self.viewModel = viewModel
        let options = viewModel.options
        let initialValue = options[versionedKey]?.currentValue ?? ""
        _selectedValue = State(initialValue: initialValue)
    }

    var body: some View {
        if let option = viewModel.options[versionedKey] {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.prettify(option.key))
                            .font(.system(size: 13, weight: .medium))

                        if !option.info.isEmpty {
                            Text(option.info)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    ControlPicker(option: option, selection: $selectedValue)
                        .onChange(of: selectedValue) { _, newValue in
                            viewModel.updateValue(newValue, for: option.key)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            if option.overrideSource != .coreDefault {
                HStack {
                    overrideSourceLabel(for: option.overrideSource)
                    Spacer()
                    if option.overrideSource == .systemOverride || option.overrideSource == .gameOverride {
                        Button(loc.localized("coreOptions.restoreDefault")) {
                            viewModel.restoreToPreviousLayer(key: option.key)
                            if let updated = viewModel.options[versionedKey] {
                                selectedValue = updated.currentValue
                            }
                        }
                        .buttonStyle(.link).font(.system(size: 10))
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
            }
        }
    }

    @ViewBuilder
    private func overrideSourceLabel(for source: OverrideSource) -> some View {
        switch source {
        case .appDefault:
            HStack(spacing: 4) {
                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(.cyan)
                Text(loc.localized("coreOptions.appDefault")).font(.system(size: 10)).foregroundColor(.cyan)
            }
        case .appSystemDefault:
            HStack(spacing: 4) {
                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(.cyan)
                Text(loc.localized("coreOptions.appSystemDefault")).font(.system(size: 10)).foregroundColor(.cyan)
            }
        case .systemOverride:
            HStack(spacing: 4) {
                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(.purple)
                Text(loc.localized("coreOptions.systemOverride")).font(.system(size: 10)).foregroundColor(.purple)
            }
        case .gameOverride:
            HStack(spacing: 4) {
                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(.orange)
                Text(loc.localized("coreOptions.gameOverride")).font(.system(size: 10)).foregroundColor(.orange)
            }
        default:
            EmptyView()
        }
    }
}

struct ControlPicker: View {
    let option: CoreOption
    @Binding var selection: String

    var body: some View {
        if isBoolean {
            Toggle("", isOn: Binding(
                get: { ["enabled", "on", "yes", "true"].contains(selection.lowercased()) },
                set: { selection = $0 ? "enabled" : "disabled" }
            ))
            .toggleStyle(.switch).scaleEffect(0.7).labelsHidden()
        } else if option.values.count <= 4 && !longText {
            Picker("", selection: $selection) {
                ForEach(option.values) { v in Text(v.label).tag(v.value) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 220)
        } else {
            Picker("", selection: $selection) {
                ForEach(option.values) { v in Text(v.label).tag(v.value) }
            }
            .pickerStyle(.menu).labelsHidden().frame(width: 140)
        }
    }

    private var isBoolean: Bool {
        guard option.values.count == 2 else { return false }
        let labels = option.values.map { $0.label.lowercased() }
        return labels.contains(where: { ["enabled", "on", "yes", "true"].contains($0) })
            && labels.contains(where: { ["disabled", "off", "no", "false"].contains($0) })
    }

    private var longText: Bool {
        option.values.contains { $0.label.count > 12 }
    }
}

struct ResetFooter: View {
    @ObservedObject var viewModel: CoreOptionsViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    var body: some View {
        VStack(spacing: 8) {
            Button(loc.localized("coreOptions.resetAllToDefaults")) { viewModel.resetAll() }
                .buttonStyle(.bordered)
            Text(loc.localized("coreOptions.effectiveOnNextLaunch")).font(.caption2).foregroundColor(.secondary)
        }
    }
}

struct EmptyStateView: View {
    let coreID: String
    @ObservedObject var viewModel: CoreOptionsViewModel
    @EnvironmentObject var library: ROMLibrary
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        ContentUnavailableView {
            Label(loc.localized("coreOptions.noSettingsFound"), systemImage: "gearshape.2")
        } description: {
            Text(loc.localized("coreOptions.noSettingsDescription"))
        } actions: {
            Button(loc.localized("coreOptions.rediscoverFromCore")) {
                Task { await viewModel.discoverOptions(for: coreID, library: library) }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
