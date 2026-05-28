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

    private var cachedCoreLabels: [String: [String: String]] = [:]
    private var cachedSystemLabels: [String: [String: String]] = [:]
    private var cachedSystemTurboButtons: [String: [String]] = [:]
    private var cachedSystemCategories: [String: String] = [:]
    private var cachedCoreOverrides: [String: [String: OverrideEntry]] = [:]
    private var missingCoreLabels: Set<String> = []
    private var missingSystemLabels: Set<String> = []
    private var missingCoreOverrides: Set<String> = []

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

    private init() {}

    private func loadCoreLabel(for key: String) -> [String: String]? {
        let lower = key.lowercased()
        if let cached = cachedCoreLabels[lower] { return cached }
        if missingCoreLabels.contains(lower) { return nil }

        guard let url = Bundle.main.url(forResource: "input_coreLabels_\(lower)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: LabelOnlyEntry].self, from: data) else {
            missingCoreLabels.insert(lower)
            return nil
        }
        let result = decoded.mapValues { $0.label }
        cachedCoreLabels[lower] = result
        return result
    }

    private func loadSystemLabel(for key: String) -> SystemLabelData? {
        let lower = key.lowercased()
        if cachedSystemLabels[lower] != nil { return nil }
        if missingSystemLabels.contains(lower) { return nil }

        guard let url = Bundle.main.url(forResource: "input_systemLabels_\(lower)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SystemLabelData.self, from: data) else {
            missingSystemLabels.insert(lower)
            return nil
        }
        cachedSystemLabels[lower] = decoded.buttons.mapValues { $0.label }
        if let turbo = decoded.turboButtons {
            cachedSystemTurboButtons[lower] = turbo
        }
        if let cat = decoded.systemCategory {
            cachedSystemCategories[lower] = cat
        }
        return decoded
    }

    private func ensureSystemLabelLoaded(_ key: String) {
        let lower = key.lowercased()
        if cachedSystemLabels[lower] != nil || missingSystemLabels.contains(lower) { return }
        loadSystemLabel(for: lower)
    }

    private func loadCoreOverride(for key: String) -> [String: OverrideEntry]? {
        let lower = key.lowercased()
        if let cached = cachedCoreOverrides[lower] { return cached }
        if missingCoreOverrides.contains(lower) { return nil }

        guard let url = Bundle.main.url(forResource: "input_coreOverrides_\(lower)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: OverrideEntry].self, from: data) else {
            missingCoreOverrides.insert(lower)
            return nil
        }
        cachedCoreOverrides[lower] = decoded
        return decoded
    }

    func label(for button: RetroButton, coreID: String?) -> String? {
        guard let coreID = coreID else { return nil }
        return loadCoreLabel(for: coreID)?[button.rawValue]
    }

    func label(for button: RetroButton, systemID: String?) -> String? {
        guard let systemID = systemID else { return nil }
        ensureSystemLabelLoaded(systemID)
        return cachedSystemLabels[systemID.lowercased()]?[button.rawValue]
    }

    func retroID(for button: RetroButton, coreID: String) -> Int32? {
        guard let core = loadCoreOverride(for: coreID),
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

        if let key = key, let labels = loadCoreLabel(for: key) {
            var result: [RetroButton] = []
            for btnName in labels.keys {
                if let btn = RetroButton(rawValue: btnName) {
                    result.append(btn)
                }
            }
            if !result.isEmpty {
                return result.sorted {
                    $0.displayName(for: systemID, coreID: coreID) <
                    $1.displayName(for: systemID, coreID: coreID)
                }
            }
        }

        let sysKey = systemID.lowercased()
        ensureSystemLabelLoaded(sysKey)
        if let labels = cachedSystemLabels[sysKey] {
            var result: [RetroButton] = []
            for btnName in labels.keys {
                if let btn = RetroButton(rawValue: btnName) {
                    result.append(btn)
                }
            }
            if !result.isEmpty {
                return result.sorted {
                    $0.displayName(for: systemID, coreID: coreID) <
                    $1.displayName(for: systemID, coreID: coreID)
                }
            }
        }

        return Self.defaultButtons.sorted {
            $0.displayName(for: systemID, coreID: coreID) <
            $1.displayName(for: systemID, coreID: coreID)
        }
    }

    func turboButtons(for systemID: String) -> [RetroButton] {
        ensureSystemLabelLoaded(systemID)
        guard let turboNames = cachedSystemTurboButtons[systemID.lowercased()] else { return [] }
        return turboNames.compactMap { name in
            if name == "a" { return RetroButton.turboA }
            if name == "b" { return RetroButton.turboB }
            if name == "x" { return RetroButton.turboX }
            if name == "y" { return RetroButton.turboY }
            return nil
        }
    }

    func systemCategory(for systemID: String) -> String? {
        ensureSystemLabelLoaded(systemID)
        return cachedSystemCategories[systemID.lowercased()]
    }
}
