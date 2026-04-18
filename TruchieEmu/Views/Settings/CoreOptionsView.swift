import SwiftUI

// MARK: - Core Options View
/// Shows options for a specific core.
struct CoreOptionsView: View {
    let coreID: String
    @StateObject private var viewModel: CoreOptionsViewModel
    @Environment(\.dismiss) private var dismiss

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
                    VStack(spacing: 16) {
                        Image(systemName: "slider.vertical.3")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No settings cached for this core.")
                            .foregroundColor(.secondary)
                        Text("Launch a game with this core first. Core settings are saved after you play, and will be available here for future adjustments.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
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
                                        CoreOptionRow(key: key, viewModel: viewModel)
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
    @ObservedObject private var manager = CoreOptionsManager.shared
    let coreID: String
    @Published var hasLoadedOnce = false

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
    }

    func categoryDisplayName(for key: String) -> String {
        if key.isEmpty { return "General" }
        return categories[key]?.description ?? key
    }

    func optionKeysInCategory(_ categoryKey: String) -> [String] {
        let targetCat = categoryKey.isEmpty ? nil : categoryKey
        return options.values.filter { $0.category == targetCat }
            .sorted { $0.description < $1.description }.map { $0.key }
    }

    func loadOptions(for coreID: String) {
        hasLoadedOnce = false
        manager.loadForCore(coreID: coreID)
        hasLoadedOnce = true
    }

    func updateValue(_ value: String, for key: String) {
        manager.updateValue(value, for: key)
    }

    func resetAll() {
        manager.resetAllToDefaults()
    }
}

// MARK: - Option Row
struct CoreOptionRow: View {
    @ObservedObject var viewModel: CoreOptionsViewModel
    let key: String
    @State private var selectedValue: String

    init(key: String, viewModel: CoreOptionsViewModel) {
        self.key = key
        self.viewModel = viewModel
        // We need to initialize selectedValue based on the current value in the manager
        let initialValue = viewModel.options[key]?.currentValue ?? ""
        _selectedValue = State(initialValue: initialValue)
    }

    var body: some View {
        Group {
            if let option = viewModel.options[key] {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.description).font(.body)
                        if !option.info.isEmpty {
                            Text(option.info).font(.caption).foregroundColor(.secondary).lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if option.values.count > 1 {
                        Picker("", selection: $selectedValue) {
                            ForEach(option.values) { v in Text(v.label).tag(v.value) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: selectedValue) { _, newValue in
                            viewModel.updateValue(newValue, for: key)
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
                                viewModel.updateValue(option.defaultValue, for: key)
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