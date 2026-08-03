import Foundation
import CryptoKit

@MainActor
class SlangPresetDiscoveryService: ObservableObject {
    static let shared = SlangPresetDiscoveryService()

    /// Presets under libretro's curated `presets/` folder (fully-composed, console-ready looks).
    /// These are surfaced first in the picker as the "Curated" set.
    static let curatedFolderPath = "presets"

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

    var curatedPresets: [SlangPreset] {
        presets.filter { preset in
            guard let relPath = relativePath(for: preset.path) else { return false }
            return relPath.hasPrefix(Self.curatedFolderPath + "/")
        }
    }

    private func relativePath(for url: URL) -> String? {
        let components = url.pathComponents
        guard let idx = components.lastIndex(of: "slang-shaders"),
              idx + 1 < components.count else { return nil }
        return components[(idx + 1)...].joined(separator: "/")
    }

    func presetsByGroup() -> [(group: String, presets: [SlangPreset])] {
        let grouped = Dictionary(grouping: presets) { $0.group }
        return grouped.map { ($0.key, $0.value) }
            .sorted { $0.group < $1.group }
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
        guard let resourcePath = Bundle.main.resourcePath else {
            LoggerService.error(category: "Slang", "scanBundledSlangShaders: Bundle.main.resourcePath is nil")
            return nil
        }
        let slangDir = (resourcePath as NSString).appendingPathComponent("slang-shaders")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: slangDir, isDirectory: &isDir), isDir.boolValue else {
            LoggerService.error(category: "Slang", "scanBundledSlangShaders: bundled slang-shaders directory missing at \(slangDir) — slang presets will be empty until the submodule is restored")
            return nil
        }
        return scanSlangpFiles(in: URL(fileURLWithPath: slangDir))
    }

    private func scanUserSlangPresets() -> [SlangPreset] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TruchiEmu/SlangPresets", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            LoggerService.warning(category: "Slang", "scanUserSlangPresets: failed to create user directory at \(dir.path): \(error.localizedDescription)")
        }
        return scanSlangpFiles(in: dir)
    }

    private func scanSlangpFiles(in directory: URL) -> [SlangPreset] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var raw: [(url: URL, basename: String, category: String, group: String, relPath: String, recommendedSystems: [String])] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "slangp" else { continue }
            let basename = fileURL.deletingPathExtension().lastPathComponent

            let components = fileURL.pathComponents
            let category: String
            var group: String
            let relPath: String
            if let idx = components.lastIndex(of: "slang-shaders"), idx + 1 < components.count {
                category = components[idx + 1]
                relPath = components[(idx + 1)...].joined(separator: "/")
                let rest = components[(idx + 1)...]
                if category == Self.curatedFolderPath {
                    group = rest.count > 2 ? "presets/\(rest[rest.startIndex + 1])" : "presets"
                } else {
                    group = category
                }
            } else {
                category = "slang"
                group = "slang"
                relPath = basename
            }

            let recommendedSystems = category == Self.curatedFolderPath
                ? SlangPreset.keywordsToSystems(basename)
                : []

            raw.append((url: fileURL, basename: basename, category: category, group: group, relPath: relPath, recommendedSystems: recommendedSystems))
            enumerator.skipDescendants()
        }

        // Detect bare-name collisions so we can disambiguate display names.
        // The bundled slang-shaders tree has ~429 duplicate basenames
        // (mostly `.slangp` presets under `bezel/Mega_Bezel/Presets/`),
        // which make the picker unusable without disambiguation.
        let basenameCounts = Dictionary(raw.map { ($0.basename, 1) }, uniquingKeysWith: +)

        var results: [SlangPreset] = []
        results.reserveCapacity(raw.count)
        for item in raw {
            // Use the immediate parent folder (the one inside the category
            // tree) to disambiguate, falling back to bare basename.
            let displayName: String
            if basenameCounts[item.basename, default: 0] > 1 {
                let parent = item.url.deletingLastPathComponent().lastPathComponent
                if parent == "slang-shaders" || parent.isEmpty {
                    displayName = "\(item.basename) (\(item.category))"
                } else {
                    displayName = "\(item.basename) (\(parent))"
                }
            } else {
                displayName = item.basename
            }

            // Stable id: SHA-256 of the relative path, truncated. Replaces
            // the earlier `URL.hashValue` (randomized per process) so ids
            // survive app restarts and SwiftData/SavedShaderPreset lookups.
            var hasher = SHA256()
            hasher.update(data: Data(item.relPath.utf8))
            let idHex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            let id = "slang-\(item.basename)-\(String(idHex.prefix(16)))"

            results.append(SlangPreset(
                id: id,
                name: displayName,
                path: item.url,
                parameters: [],
                parameterDefaults: [:],
                category: item.category,
                group: item.group,
                recommendedSystems: item.recommendedSystems
            ))
        }
        return results
    }
}
