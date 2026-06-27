import Foundation

@MainActor
class SlangPresetDiscoveryService: ObservableObject {
    static let shared = SlangPresetDiscoveryService()

    @Published private(set) var presets: [SlangPreset] = []
    @Published private(set) var categories: [String] = []

    private init() {
        scanForPresets()
    }

    func scanForPresets() {
        var allPresets: [SlangPreset] = []

        if let bundled = scanBundledSlangShaders() {
            allPresets.append(contentsOf: bundled)
        }

        let userPresets = scanUserSlangPresets()
        allPresets.append(contentsOf: userPresets)

        presets = allPresets
        categories = Array(Set(allPresets.map { $0.category })).sorted()
    }

    func presetsByCategory() -> [(category: String, presets: [SlangPreset])] {
        let grouped = Dictionary(grouping: presets) { $0.category }
        return grouped.map { ($0.key, $0.value) }
            .sorted { $0.category < $1.category }
    }

    func presets(for category: String) -> [SlangPreset] {
        presets.filter { $0.category == category }
    }

    private func scanBundledSlangShaders() -> [SlangPreset]? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let slangDir = (resourcePath as NSString).appendingPathComponent("slang-shaders")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: slangDir, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return scanSlangpFiles(in: URL(fileURLWithPath: slangDir))
    }

    private func scanUserSlangPresets() -> [SlangPreset] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TruchiEmu/SlangPresets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return scanSlangpFiles(in: dir)
    }

    private func scanSlangpFiles(in directory: URL) -> [SlangPreset] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var results: [SlangPreset] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "slangp" else { continue }
            let id = "slang-\(fileURL.lastPathComponent)-\(fileURL.hashValue)"
            let name = fileURL.deletingPathExtension().lastPathComponent

            let components = fileURL.pathComponents
            let category: String
            if let idx = components.lastIndex(of: "slang-shaders"), idx + 1 < components.count {
                category = components[idx + 1]
            } else {
                category = "slang"
            }

            let preset = SlangPreset(
                id: id,
                name: name,
                path: fileURL,
                parameters: [],
                parameterDefaults: [:],
                category: category
            )
            results.append(preset)
            enumerator.skipDescendants()
        }
        return results
    }
}
