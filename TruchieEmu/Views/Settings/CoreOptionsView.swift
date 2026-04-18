import SwiftUI
import Combine

// MARK: - Core Options View
// Shows options for a specific core.
struct CoreOptionsView: View {
    let coreID: String
    @StateObject private var viewModel: CoreOptionsViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: ROMLibrary

    init(coreID: String) {
        self.coreID = coreID
        self._viewModel = StateObject(wrappedValue: CoreOptionsViewModel(coreID: coreID))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.options.isEmpty, !viewModel.hasLoadedOnce {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading core settings…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.options.isEmpty {
                    VStack(spacing: 24) {
                        Image(systemName: "slider.vertical.3")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        VStack(spacing: 8) {
                            Text("No settings cached for this core.")
                                .foregroundColor(.secondary)
                            Text("Launch a game with this core first. Core settings are saved after you play, and will be available here for future adjustments.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)
                        }
                        
                         Button("Load Settings from Definitions") {
                             Task {
                                 await viewModel.discoverOptions(for: coreID, library: library)
                             }
                         }
                         .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            ForEach(viewModel.sortedKeys, id: \.self) { category in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(viewModel.categoryDisplayName(for: category))
                                        .font(.headline)
                                        .padding(.top)
                                    ForEach(viewModel.optionKeysInCategory(category), id: \.self) { key in
                                        CoreOptionRow(versionedKey: key, viewModel: viewModel)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            Divider()
                            VStack(spacing: 12) {
                                Button("Reset All to Defaults") { viewModel.resetAll() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                Text("Changes take effect the next time you launch a game with this core.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Core Options — \(coreID)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { viewModel.loadOptions(for: coreID) }
        }
    }
}

// MARK: - View Model
@MainActor
class CoreOptionsViewModel: ObservableObject {
    private let manager = CoreOptionsManager.shared
    let coreID: String
    @Published var hasLoadedOnce = false
    private var cancellables = Set<AnyCancellable>()

    var options: [String: CoreOption] { manager.options }
    var categories: [String: CoreOptionCategory] { manager.categories }

    var sortedKeys: [String] {
        var catKeys = Set(options.values.compactMap { $0.category })
        if catKeys.isEmpty, !options.isEmpty { catKeys.insert("") }
        if catKeys.isEmpty { return [] }
        var result = Array(catKeys)
        result.sort { a, b in
            if a.isEmpty, !b.isEmpty { return true }
            if !a.isEmpty, b.isEmpty { return false }
            return categories[a]?.description ?? "" < categories[b]?.description ?? ""
        }
        return result
    }

    init(coreID: String) {
        self.coreID = coreID
        
        // Observe manager changes to update the view model
        manager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func categoryDisplayName(for key: String) -> String {
        if key.isEmpty { return "General" }
        return categories[key]?.description ?? key
    }

    func optionKeysInCategory(_ categoryKey: String) -> [String] {
        let targetCat = categoryKey.isEmpty ? nil : categoryKey
        // Filter by category, then map to the versioned key
        return options.values.filter { $0.category == targetCat }
            .sorted { $0.description < $1.description }
            .map { "\($0.key)_\($0.version.rawValue)" }
    }

    func loadOptions(for coreID: String) {
        hasLoadedOnce = false
        manager.loadForCore(coreID: coreID)
        hasLoadedOnce = true
    }

    func discoverOptions(for coreID: String, library: ROMLibrary) async {
        // Find the dylib path for this core
        let runner = EmulatorRunner.forSystem(nil) // Use a generic runner to access findCoreLib
        guard let dylibPath = runner.findCoreLib(coreID: coreID) else {
            LoggerService.error(category: "CoreOptionsView", "Could not find dylib for core: \(coreID)")
            return
        }
        
        // To fulfill the "launch with any random game" requirement, we attempt to find a random ROM.
        var randomRomPath: String? = nil
        if let randomRom = library.roms.randomElement() {
            randomRomPath = randomRom.path.path
        }
        
        await manager.discoverOptions(for: coreID, dylibPath: dylibPath, romPath: randomRomPath)
        
        // Reload the options from the newly created definitions
        manager.loadForCore(coreID: coreID)
    }

    func resetAll() {
        manager.resetAllToDefaults()
    }

    func updateValue(_ value: String, for key: String) {
        manager.updateValue(value, for: key)
    }
}

// MARK: - Option Row
struct CoreOptionRow: View {
    @ObservedObject var viewModel: CoreOptionsViewModel
    let versionedKey: String
    @State private var selectedValue: String

    init(versionedKey: String, viewModel: CoreOptionsViewModel) {
        self.versionedKey = versionedKey
        self.viewModel = viewModel
        // We need to initialize selectedValue based on the current value in the manager
        let initialValue = viewModel.options[versionedKey]?.currentValue ?? ""
        _selectedValue = State(initialValue: initialValue)
    }

    var body: some View {
        Group {
            if let option = viewModel.options[versionedKey] {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(option.description).font(.body)
                                Text("[\(option.version.rawValue)]")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if !option.info.isEmpty {
                                Text(option.info).font(.caption).foregroundColor(.secondary).lineLimit(3)
                            }
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if option.values.count > 1 {
                        Picker("", selection: $selectedValue) {
                            ForEach(option.values) { v in Text(v.label).tag(v.value) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: selectedValue) { _, newValue in
                            // Use the base key for the update
                            viewModel.updateValue(newValue, for: option.key)
                        }
                    } else {
                        Text(option.currentValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }

                    if option.isModified {
                        HStack {
                            Text("Changed from default")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Spacer()
                            Button("Reset to Default") {
                                selectedValue = option.defaultValue
                                viewModel.updateValue(option.defaultValue, for: option.key)
                            }
                            .buttonStyle(.link)
                            .foregroundColor(.blue)
                            .font(.caption2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
