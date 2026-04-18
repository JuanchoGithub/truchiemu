import SwiftUI
import Combine

// MARK: - View Model
@MainActor
class CoreOptionsViewModel: ObservableObject {
    private let manager = CoreOptionsManager.shared
    
    @Published var currentCoreID: String
    @Published var isSystemMode: Bool = false
    @Published var systemID: String? = nil
    @Published var availableCores: [(id: String, name: String)] = []
    
    @Published var isLoading = false
    @Published var hasLoadedOnce = false
    private var cancellables = Set<AnyCancellable>()

    var options: [String: CoreOption] { manager.options }
    var categories: [String: CoreOptionCategory] { manager.categories }

    var sortedKeys: [String] {
        var catKeys = Set(options.values.compactMap { $0.category })
        if catKeys.isEmpty && !options.isEmpty { catKeys.insert("") }
        var result = Array(catKeys)
        result.sort { a, b in
            if a.isEmpty { return true }
            if b.isEmpty { return false }
            return (categories[a]?.description ?? "") < (categories[b]?.description ?? "")
        }
        return result
    }

    init(id: String) {
        if let system = SystemDatabase.system(forID: id) {
            self.currentCoreID = system.defaultCoreID ?? ""
            self.isSystemMode = true
            self.systemID = id
        } else {
            self.currentCoreID = id
            self.isSystemMode = false
            self.systemID = nil
        }
        
        manager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func loadOptions(for id: String, library: ROMLibrary? = nil) {
        isLoading = true
        
        // Find dylib path from installed cores
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
        
        // Find rom path from library
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
        
        // Simulação de carga para a animação
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if self.isSystemMode, let sysID = self.systemID {
                self.discoverCoresForSystem(sysID)
            } else {
                self.manager.loadForCore(coreID: id, dylibPath: dylibPath, romPath: romPath)
            }
            self.isLoading = false
            self.hasLoadedOnce = true
        }
    }

    private func discoverCoresForSystem(_ sysID: String) {
        let cores = LibretroInfoManager.coreToSystemMap
            .filter { $0.value.contains(sysID) }
            .map { $0.key }
        
        self.availableCores = cores.map { coreID in
            let baseID = coreID.replacingOccurrences(of: "_libretro", with: "")
            let name = LibretroCore.knownCoreMetadata[baseID]?.displayName ?? coreID.replacingOccurrences(of: "_libretro", with: "").capitalized
            return (id: coreID, name: name)
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
        // mgba_gb_colors_preset -> Gb Colors Preset
        let clean = key.replacingOccurrences(of: "^[a-zA-Z0-9]+_", with: "", options: .regularExpression)
        let words = clean.components(separatedBy: "_")
        let pretty = words.map { $0.capitalized }.joined(separator: " ")
        return "\(pretty) (\(key))"
    }

    func categoryDisplayName(for key: String) -> String {
        key.isEmpty ? "General" : (categories[key]?.description ?? key)
    }

    func optionKeysInCategory(_ categoryKey: String) -> [String] {
        let targetCat = categoryKey.isEmpty ? nil : categoryKey
        return options.values.filter { $0.category == targetCat }
            .sorted { $0.description < $1.description }
            .map { "\($0.key)_\($0.version.rawValue)" }
    }

    func updateValue(_ value: String, for key: String) {
        manager.updateValue(value, for: key)
    }

    func resetAll() {
        manager.resetAllToDefaults()
    }
    
    func discoverOptions(for coreID: String, library: ROMLibrary) async {
        // Implementación de descubrimiento (lógica original)
        // ... (Tu código de EmulatorRunner y manager.discoverOptions)
    }
}

// MARK: - Main View
struct CoreOptionsView: View {
    let initialID: String
    @StateObject private var viewModel: CoreOptionsViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: ROMLibrary

    init(coreID: String) {
        self.initialID = coreID
        self._viewModel = StateObject(wrappedValue: CoreOptionsViewModel(id: coreID))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()
                
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView().controlSize(.large)
                        Text("Loading core settings...").foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                } else if viewModel.options.isEmpty {
                    EmptyStateView(coreID: viewModel.isSystemMode ? (viewModel.systemID ?? "") : viewModel.currentCoreID, viewModel: viewModel)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            if viewModel.isSystemMode {
                                Picker("Core", selection: $viewModel.currentCoreID) {
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

                            ForEach(viewModel.sortedKeys, id: \.self) { category in
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
                                    Label("Rediscover from Core", systemImage: "arrow.triangle.2.circlepath.mag")
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
             .animation(.easeInOut, value: viewModel.isLoading)
             .navigationTitle(viewModel.isSystemMode ? "Options: \(SystemDatabase.system(forID: viewModel.systemID ?? "")?.name ?? "")" : "Options: \(viewModel.currentCoreID)")
             .toolbar {
                 ToolbarItem(placement: .confirmationAction) {
                     Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                 }
             }
             .onAppear { viewModel.loadOptions(for: initialID, library: library) }
        }
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
    let versionedKey: String
    @State private var selectedValue: String

    init(versionedKey: String, viewModel: CoreOptionsViewModel) {
        self.versionedKey = versionedKey
        self.viewModel = viewModel
        let initialValue = viewModel.options[versionedKey]?.currentValue ?? ""
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
                
                if option.isModified {
                    HStack {
                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(.orange)
                        Text("Modified from default").font(.system(size: 10)).foregroundColor(.orange)
                        Spacer()
                        Button("Restore Default") {
                            selectedValue = option.defaultValue
                            viewModel.updateValue(option.defaultValue, for: option.key)
                        }
                        .buttonStyle(.link).font(.system(size: 10))
                    }
                    .padding(.horizontal, 12).padding(.bottom, 8)
                }
            }
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
        let labels = option.values.map { $0.label.lowercased() }
        return labels.contains(where: { ["enabled", "disabled", "on", "off"].contains($0) })
    }
    
    private var longText: Bool {
        option.values.contains { $0.label.count > 12 }
    }
}

struct ResetFooter: View {
    @ObservedObject var viewModel: CoreOptionsViewModel
    var body: some View {
        VStack(spacing: 8) {
            Button("Reset All to Defaults") { viewModel.resetAll() }
                .buttonStyle(.bordered)
            Text("Changes will take effect on next launch.").font(.caption2).foregroundColor(.secondary)
        }
    }
}

struct EmptyStateView: View {
    let coreID: String
    @ObservedObject var viewModel: CoreOptionsViewModel
    @EnvironmentObject var library: ROMLibrary
    
    var body: some View {
        ContentUnavailableView {
            Label("No Settings Found", systemImage: "gearshape.2")
        } description: {
            Text("Launch a game with \(coreID) to generate settings, or try discovering them now.")
        } actions: {
            Button("Rediscover from Core") {
                Task { await viewModel.discoverOptions(for: coreID, library: library) }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}