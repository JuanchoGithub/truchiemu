import SwiftUI
import Combine // <--- ESTA es la que te falta

// MARK: - View Model (La lógica que faltaba)
@MainActor
class CoreOptionsViewModel: ObservableObject {
    private let manager = CoreOptionsManager.shared
    let identifier: String
    
    @Published var selectedCoreID: String?
    @Published var availableCores: [LibretroCore] = []
    @Published var options: [String: CoreOption] = [:]
    @Published var categories: [String: CoreOptionCategory] = [:]
    @Published var hasLoadedOnce = false
    
    private var cancellables = Set<AnyCancellable>()

    // Ordenamos las categorías para que no aparezcan al azar
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

    init(identifier: String) {
        self.identifier = identifier
        
        // Esto hace que la UI reaccione cuando el manager cambia
        manager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func load() async {
        let matchingCores = CoreManager.shared.installedCores.filter { core in
            core.id == identifier || CoreManager.supportedSystems(for: core.id).contains(identifier)
        }
        
        self.availableCores = matchingCores
        
        if matchingCores.count == 1 {
            self.selectedCoreID = matchingCores[0].id
            await loadOptions(for: self.selectedCoreID!)
        } else {
            self.selectedCoreID = nil
            self.options = [:]
            self.categories = [:]
        }
    }

    func selectCore(id: String) async {
        self.selectedCoreID = id
        await loadOptions(for: id)
    }

    func categoryDisplayName(for key: String) -> String {
        if key.isEmpty { return "General" }
        return categories[key]?.description ?? key
    }

    func optionKeysInCategory(_ categoryKey: String) -> [String] {
        let targetCat = categoryKey.isEmpty ? nil : categoryKey
        return options.values.filter { $0.category == targetCat }
            .sorted { $0.description < $1.description }
            .map { "\($0.key)_\($0.version.rawValue)" }
    }

    func loadOptions(for coreID: String) async {
        hasLoadedOnce = false
        manager.loadForCore(coreID: coreID)
        
        // Sync with manager
        self.options = manager.options
        self.categories = manager.categories
        
        hasLoadedOnce = true
    }

    func forceDiscovery() async {
        guard let selectedID = selectedCoreID,
               let core = CoreManager.shared.installedCores.first(where: { $0.id == selectedID }),
               let activeVersion = core.activeVersion ?? core.installedVersions.first else {
            LoggerService.error(category: "CoreOptions", "Starting Core Options discovery failed, no selectedCoreID found")
            return
        }
        LoggerService.info(category: "CoreOptions", "Starting Core Options discovery for: \(selectedCoreID)")
        let dylibPath = activeVersion.dylibPath.path
        LoggerService.debug(category: "CoreOptions", "For: \(selectedCoreID), found active core \(dylibPath)")
        
        await manager.discoverOptions(for: selectedID, dylibPath: dylibPath, romPath: nil)
        await loadOptions(for: selectedID)
    }

    func updateValue(_ value: String, for key: String) {
        manager.updateValue(value, for: key)
    }

    func resetAll() {
        manager.resetAllToDefaults()
    }
}
// MARK: - Estilos Constantes
enum UIConstants {
    static let cardBackground = Color(NSColor.windowBackgroundColor).opacity(0.5)
    static let accentColor = Color.blue
}

struct CoreOptionsView: View {
    let identifier: String
    @StateObject private var viewModel: CoreOptionsViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(identifier: String) {
        self.identifier = identifier
        self._viewModel = StateObject(wrappedValue: CoreOptionsViewModel(identifier: identifier))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()
                
                if viewModel.availableCores.count > 1 {
                    CoreSelectionView(viewModel: viewModel)
                } else if let selectedID = viewModel.selectedCoreID {
                    if viewModel.options.isEmpty {
                        EmptyStateView(identifier: identifier, viewModel: viewModel)
                    } else {
                        ScrollView {
                            VStack(spacing: 24) {
                                ForEach(viewModel.sortedKeys, id: \.self) { category in
                                    CategorySection(
                                        title: viewModel.categoryDisplayName(for: category),
                                        optionKeys: viewModel.optionKeysInCategory(category),
                                        viewModel: viewModel
                                    )
                                }
                                
                                ResetFooter(viewModel: viewModel)
                            }
                            .padding()
                        }
                    }
                } else if viewModel.availableCores.isEmpty {
                    EmptyStateView(identifier: identifier, viewModel: viewModel)
                }
            }
            .navigationTitle("Options: \(identifier)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .task {
                await viewModel.load()
            }
        }
    }
}

// MARK: - Componentes Refactorizados

struct CategorySection: View {
    let title: String
    let optionKeys: [String]
    @ObservedObject var viewModel: CoreOptionsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
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
            .background(UIConstants.cardBackground)
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
                HStack(alignment: .center, spacing: 12) {
                    // Texto e Info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(option.description)
                                .font(.system(size: 13, weight: .medium))
                            
                            Text(option.version.rawValue)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .background(Capsule().fill(Color.secondary.opacity(0.2)))
                        }
                        
                        if !option.info.isEmpty {
                            Text(option.info)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    // Control inteligente
                    ControlPicker(option: option, selection: $selectedValue)
                        .onChange(of: selectedValue) { _, newValue in
                            viewModel.updateValue(newValue, for: option.key)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                
                // Badge de "Modificado" solo si aplica
                if option.isModified {
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.orange)
                        Text("Modified from default").font(.system(size: 10)).foregroundColor(.orange)
                        Spacer()
                        Button("Reset") {
                            selectedValue = option.defaultValue
                            viewModel.updateValue(option.defaultValue, for: option.key)
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

// MARK: - Picker Inteligente
struct ControlPicker: View {
    let option: CoreOption
    @Binding var selection: String
    
    var body: some View {
        if isBoolean {
            Toggle("", isOn: Binding(
                get: { selection.lowercased() == "enabled" || selection == "on" },
                set: { selection = $0 ? "enabled" : "disabled" }
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.7)
            .labelsHidden()
        } else {
            Picker("", selection: $selection) {
                ForEach(option.values) { v in
                    Text(v.label).tag(v.value)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .labelsHidden()
        }
    }
    
    private var isBoolean: Bool {
        let labels = option.values.map { $0.label.lowercased() }
        return labels.contains(where: { ["enabled", "disabled", "on", "off"].contains($0) })
    }
}

struct ResetFooter: View {
    @ObservedObject var viewModel: CoreOptionsViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Button(role: .destructive) {
                viewModel.resetAll()
            } label: {
                Label("Reset All to Defaults", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
            Text("Changes will be applied when you restart the core.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    let identifier: String
    @ObservedObject var viewModel: CoreOptionsViewModel
    
    var body: some View {
        ContentUnavailableView {
            Label("No Settings Found", systemImage: "gearshape.2")
        } description: {
            Text("Launch a game with \(identifier) first to generate the configuration file.")
        } actions: {
            Button("Force Discovery") {
                Task {
                    await viewModel.forceDiscovery()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct CoreSelectionView: View {
    @ObservedObject var viewModel: CoreOptionsViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select a Core")
                .font(.headline)
            
            Text("Multiple cores are installed for this system. Please choose one to configure its options.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            List(viewModel.availableCores, id: \.id) { core in
                Button(action: {
                    Task {
                        await viewModel.selectCore(id: core.id)
                    }
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(core.displayName)
                                .font(.body)
                            Text(core.id)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
            .cornerRadius(12)
            .padding(.horizontal)
            
            Button("Back") {
                // How to go back? The view is in a NavigationStack. 
                // We might need to pass a dismissal or something, but usually, 
                // if this is a modal, we might want to dismiss or just let them go back.
                // For now, let's just rely on the NavigationStack if it was pushed.
                // But it seems it's in a ZStack inside a NavigationStack.
                // If it's a modal, they can dismiss.
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 50)
    }
}
