import Foundation

struct OverrideEntry: Codable {
    let id: Int?
    let label: String?
}

struct LabelOnlyEntry: Codable {
    let label: String
}

struct SystemLabelData: Codable {
    let buttons: [String: LabelOnlyEntry]
    let turboButtons: [String]?
    let systemCategory: String?
}

class CoreButtonOverride {
    static let shared = CoreButtonOverride()

    private var coreLabels: [String: [String: String]] = [:]
    private var systemLabels: [String: [String: String]] = [:]
    private var systemTurboButtons: [String: [String]] = [:]
    private var systemCategories: [String: String] = [:]
    private var coreOverrides: [String: [String: OverrideEntry]] = [:]

    private static let identityMap: [String: Int32] = [
        "b": 0, "y": 1, "select": 2, "start": 3,
        "up": 4, "down": 5, "left": 6, "right": 7,
        "a": 8, "x": 9, "l1": 10, "r1": 11,
        "l2": 12, "r2": 13, "l3": 14, "r3": 15,
    ]

    private static let defaultButtons: [RetroButton] = [
        .up, .down, .left, .right,
        .a, .b, .x, .y,
        .l1, .r1, .l2, .r2, .l3, .r3,
        .start, .select,
        .lStickUp, .lStickDown, .lStickLeft, .lStickRight,
        .rStickUp, .rStickDown, .rStickLeft, .rStickRight,
    ]

    private init() {
        load()
    }

    private func load() {
        loadCoreLabels()
        loadSystemLabels()
        loadCoreOverrides()
    }

    private func loadCoreLabels() {
        guard let resourcePath = Bundle.main.resourcePath,
              let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) else { return }

        for filename in files where filename.hasPrefix("input_coreLabels_") && filename.hasSuffix(".json") {
            let key = filename
                .replacingOccurrences(of: "input_coreLabels_", with: "")
                .replacingOccurrences(of: ".json", with: "")

            let fileURL = URL(fileURLWithPath: resourcePath).appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode([String: LabelOnlyEntry].self, from: data) else { continue }

            coreLabels[key] = decoded.mapValues { $0.label }
        }
    }

    private func loadSystemLabels() {
        guard let resourcePath = Bundle.main.resourcePath,
              let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) else { return }

        for filename in files where filename.hasPrefix("input_systemLabels_") && filename.hasSuffix(".json") {
            let key = filename
                .replacingOccurrences(of: "input_systemLabels_", with: "")
                .replacingOccurrences(of: ".json", with: "")

            let fileURL = URL(fileURLWithPath: resourcePath).appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode(SystemLabelData.self, from: data) else { continue }

            systemLabels[key] = decoded.buttons.mapValues { $0.label }
            if let turbo = decoded.turboButtons {
                systemTurboButtons[key] = turbo
            }
            if let cat = decoded.systemCategory {
                systemCategories[key] = cat
            }
        }
    }

    private func loadCoreOverrides() {
        guard let resourcePath = Bundle.main.resourcePath,
              let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) else { return }

        for filename in files where filename.hasPrefix("input_coreOverrides_") && filename.hasSuffix(".json") {
            let key = filename
                .replacingOccurrences(of: "input_coreOverrides_", with: "")
                .replacingOccurrences(of: ".json", with: "")

            let fileURL = URL(fileURLWithPath: resourcePath).appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode([String: OverrideEntry].self, from: data) else { continue }

            coreOverrides[key] = decoded
        }
    }

    func label(for button: RetroButton, coreID: String?) -> String? {
        guard let coreID = coreID else { return nil }
        return coreLabels[coreID.lowercased()]?[button.rawValue]
    }

    func label(for button: RetroButton, systemID: String?) -> String? {
        guard let systemID = systemID else { return nil }
        return systemLabels[systemID.lowercased()]?[button.rawValue]
    }

    func retroID(for button: RetroButton, coreID: String) -> Int32? {
        guard let core = coreOverrides[coreID.lowercased()],
              let entry = core[button.rawValue],
              let rid = entry.id else {
            return nil
        }
        return Int32(rid)
    }

    func retroID(for button: RetroButton, systemID: String) -> Int32? {
        return nil
    }

    static func identityID(for button: RetroButton) -> Int32? {
        return identityMap[button.rawValue]
    }

    func buttons(for systemID: String, coreID: String? = nil) -> [RetroButton] {
        let key = coreID?.lowercased() ?? SystemDatabase.system(forID: systemID)?.defaultCoreID?.lowercased()

        if let key = key, let labels = coreLabels[key] {
            var result: [RetroButton] = []
            for btnName in labels.keys {
                if let btn = RetroButton(rawValue: btnName) {
                    result.append(btn)
                }
            }
            if !result.isEmpty {
                // Sort alphabetically by display name
                return result.sorted { 
                    $0.displayName(for: systemID, coreID: coreID) < 
                    $1.displayName(for: systemID, coreID: coreID) 
                }
            }
        }

        let sysKey = systemID.lowercased()
        if let labels = systemLabels[sysKey] {
            var result: [RetroButton] = []
            for btnName in labels.keys {
                if let btn = RetroButton(rawValue: btnName) {
                    result.append(btn)
                }
            }
            if !result.isEmpty {
                // Sort alphabetically by display name  
                return result.sorted { 
                    $0.displayName(for: systemID, coreID: coreID) < 
                    $1.displayName(for: systemID, coreID: coreID) 
                }
            }
        }

        // Sort fallback defaultButtons alphabetically
        return Self.defaultButtons.sorted { 
            $0.displayName(for: systemID, coreID: coreID) < 
            $1.displayName(for: systemID, coreID: coreID) 
        }
    }

    func turboButtons(for systemID: String) -> [RetroButton] {
        guard let turboNames = systemTurboButtons[systemID.lowercased()] else { return [] }
        return turboNames.compactMap { name in
            if name == "a" { return RetroButton.turboA }
            if name == "b" { return RetroButton.turboB }
            if name == "x" { return RetroButton.turboX }
            if name == "y" { return RetroButton.turboY }
            return nil
        }
    }

    func systemCategory(for systemID: String) -> String? {
        return systemCategories[systemID.lowercased()]
    }
}
