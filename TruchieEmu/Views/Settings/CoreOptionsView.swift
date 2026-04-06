import SwiftUI

// MARK: - Core Options View
/// Shows options for a specific core. Reads from the Obj-C bridge when the core
/// is running; falls back to a persisted JSON cache on disk.
struct CoreOptionsView: View {
    let coreID: String
    @StateObject private var viewModel = CoreOptionsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if viewModel.sortedKeys.isEmpty, !viewModel.hasLoadedOnce {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading core settings…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.sortedKeys.isEmpty {
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
        }
        .onAppear { viewModel.loadOptions(for: coreID) }
    }
}

// MARK: - View Model
@MainActor
class CoreOptionsViewModel: ObservableObject {
    @Published var options: [String: CoreOption] = [:]
    @Published var categories: [String: CoreOptionCategory] = [:]
    @Published var isLoading = false
    @Published var hasLoadedOnce = false

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
        isLoading = true; hasLoadedOnce = false
        // 1) Read active options from Obj-C bridge (populated when core is running)
        if let defs = LibretroBridge.getOptionsDictionary(), !defs.isEmpty {
            parseAndSave(defs: defs, cats: LibretroBridge.getCategoriesDictionary(), coreID: coreID)
        } else {
            // 2) Fallback: load persisted JSON from disk
            if !loadPersisted(for: coreID) { options.removeAll(); categories.removeAll() }
        }
        isLoading = false; hasLoadedOnce = true
    }

    func parseAndSave(defs: [String: Any], cats: [String: Any]?, coreID: String) {
        options.removeAll(); categories.removeAll()
        if let catDict = cats as? [String: [String: String]] {
            for (k, v) in catDict { categories[k] = CoreOptionCategory(key: k, description: v["desc"] ?? k, info: v["info"] ?? "") }
        }
        for (key, def) in defs {
            guard let d = def as? [String: Any] else { continue }
            let desc = d["desc"] as? String ?? key
            let info = d["info"] as? String ?? ""
            let catKey = d["category"] as? String ?? ""
            let defaultVal = d["defaultValue"] as? String ?? ""
            let currentVal = d["currentValue"] as? String ?? defaultVal
            var values: [CoreOptionValue] = []
            if let valsArr = d["values"] as? [[String: String]] {
                for v in valsArr { values.append(CoreOptionValue(value: v["value"] ?? "", label: v["label"] ?? v["value"] ?? "")) }
            }
            if values.isEmpty { values = [CoreOptionValue(value: currentVal, label: currentVal)] }
            options[key] = CoreOption(key: key, description: desc, info: info, category: catKey.isEmpty ? nil : catKey,
                                      values: values, defaultValue: defaultVal, currentValue: currentVal)
        }
        persistDefinitions(for: coreID)
    }

    // MARK: - Disk persistence for option definitions
    private func definitionsURL(for coreID: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("TruchieEmu/CoreOptionDefinitions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(coreID).json")
    }

    func persistDefinitions(for coreID: String) {
        let payload: [String: Any] = [
            "categories": categories.mapValues { ["desc": $0.description, "info": $0.info] },
            "options": options.mapValues { o -> [String: Any] in
                return ["desc": o.description, "info": o.info, "category": o.category ?? "",
                        "defaultValue": o.defaultValue, "currentValue": o.currentValue,
                        "values": o.values.map { ["value": $0.value, "label": $0.label] }]
            }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: definitionsURL(for: coreID))
        }
    }

    func loadPersisted(for coreID: String) -> Bool {
        let url = definitionsURL(for: coreID)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        categories.removeAll(); options.removeAll()
        if let cats = json["categories"] as? [String: [String: String]] {
            for (k, v) in cats { categories[k] = CoreOptionCategory(key: k, description: v["desc"] ?? k, info: v["info"] ?? "") }
        }
        if let opts = json["options"] as? [String: [String: Any]] {
            for (key, d) in opts {
                let desc = d["desc"] as? String ?? key
                let info = d["info"] as? String ?? ""
                let catKey = d["category"] as? String ?? ""
                let defaultVal = d["defaultValue"] as? String ?? ""
                let storedVal = d["currentValue"] as? String ?? defaultVal
                var values: [CoreOptionValue] = []
                if let valsArr = d["values"] as? [[String: String]] {
                    for v in valsArr { values.append(CoreOptionValue(value: v["value"] ?? "", label: v["label"] ?? v["value"] ?? "")) }
                }
                if values.isEmpty { values = [CoreOptionValue(value: storedVal, label: storedVal)] }
                options[key] = CoreOption(key: key, description: desc, info: info, category: catKey.isEmpty ? nil : catKey,
                                          values: values, defaultValue: defaultVal, currentValue: storedVal)
            }
        }
        return !options.isEmpty
    }

    func updateValue(_ value: String, for key: String) {
        options[key]?.currentValue = value
        LibretroBridge.setOptionValue(value, forKey: key)
        AppSettings.set("coreopt_\(coreID)_\(key)", value: value)
        if let coreID = AppSettings.get("lastLoadedCoreID", type: String.self) { persistDefinitions(for: coreID) }
    }

    func resetAll() {
        for key in options.keys {
            let defaultVal = options[key]?.defaultValue ?? ""
            options[key]?.currentValue = defaultVal
            LibretroBridge.setOptionValue(defaultVal, forKey: key)
        }
        if let coreID = AppSettings.get("lastLoadedCoreID", type: String.self) { persistDefinitions(for: coreID) }
    }
    
    let coreID: String = ""
}

// MARK: - Option Row
struct CoreOptionRow: View {
    @ObservedObject var viewModel: CoreOptionsViewModel
    let key: String
    @State private var selectedValue: String

    init(key: String, viewModel: CoreOptionsViewModel) {
        self.key = key
        self.viewModel = viewModel
        _selectedValue = State(initialValue: viewModel.options[key]?.currentValue ?? "")
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
