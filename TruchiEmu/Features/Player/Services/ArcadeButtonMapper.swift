import Foundation

enum ArcadeLayout: String, Codable {
    case capcom6
    case midway6
    case snk4
    case capcom4
}

@MainActor
class ArcadeButtonMapper {
    static let shared = ArcadeButtonMapper()

    private struct MappingEntry: Codable {
        let fightDataKey: String
        let retroButton: String
    }

    private struct SystemMapping: Codable {
        let layout: ArcadeLayout
        let systemID: String
        let mappings: [MappingEntry]
    }

    private struct MappingsFile: Codable {
        let mappings: [SystemMapping]
    }

    private var cachedMappings: [String: [ArcadeLayout: [String: RetroButton]]] = [:]
    private var originalKeys: [String: String] = [:]

    private init() {}

    func retroButton(for fightDataKey: String, layout: ArcadeLayout, systemID: String, systemControlMappings: [String: [String: String]]? = nil) -> RetroButton? {
        let resolvedKey = resolveAlias(fightDataKey)
        let mapKey: String = {
            let key = systemID.lowercased()
            if ["genesis", "megadrive", "32x"].contains(key),
               AppSettings.getGenesisControllerType() == .threeButton {
                return "genesis3"
            }
            return key
        }()
        if let sysMap = systemControlMappings?[mapKey] {
            for (btnRaw, fdKey) in sysMap where normalizeKey(fdKey) == normalizeKey(resolvedKey) {
                if let button = RetroButton(rawValue: btnRaw) { return button }
            }
        }

        let key = systemID.lowercased()
        ensureLoaded(for: key)

        guard let layoutMap = cachedMappings[key]?[layout],
            let button = layoutMap[normalizeKey(resolvedKey)] else {
            return fallbackMapping(fightDataKey: resolvedKey, layout: layout)
        }
        return button
    }

    func arcadeLayout(for game: FightDataGame) -> ArcadeLayout {
        let controls = game.controls

        let hasCapcom6Keys = controls["^E"] != nil && controls["^F"] != nil && controls["^G"] != nil &&
                             controls["^H"] != nil && controls["^I"] != nil && controls["^J"] != nil
        if hasCapcom6Keys {
            return .capcom6
        }

        let hasMidwayKeys = controls["^G"] != nil && controls["^E"] != nil &&
                            controls["_G"] != nil && controls["^J"] != nil && controls["^H"] != nil
        if hasMidwayKeys && controls["^F"] == nil && controls["^I"] == nil {
            return .midway6
        }

        let hasSNK4Keys = controls["_A"] != nil && controls["_B"] != nil &&
                          controls["_C"] != nil && controls["_D"] != nil
        if hasSNK4Keys {
            return .snk4
        }

        if controls.count <= 3, controls["_A"] != nil {
            return .capcom4
        }

        return .capcom6
    }

    func translateButtonSet(_ fightDataKeys: Set<String>, layout: ArcadeLayout, systemID: String, systemControlMappings: [String: [String: String]]? = nil) -> Set<RetroButton> {
        var result = Set<RetroButton>()
        for key in fightDataKeys {
            if let button = retroButton(for: key, layout: layout, systemID: systemID, systemControlMappings: systemControlMappings) {
                result.insert(button)
            }
        }
        return result
    }

    func fightDataKey(for button: RetroButton, layout: ArcadeLayout, systemID: String, systemControlMappings: [String: [String: String]]? = nil) -> String? {
        let mapKey: String = {
            let key = systemID.lowercased()
            if ["genesis", "megadrive", "32x"].contains(key),
               AppSettings.getGenesisControllerType() == .threeButton {
                return "genesis3"
            }
            return key
        }()
        LoggerService.info("FDK: button=\(button.rawValue) systemID=\(systemID) mapKey=\(mapKey) hasCtrlMap=\(systemControlMappings != nil)")
        if let sysMap = systemControlMappings?[mapKey] {
            if let fdKey = sysMap[button.rawValue] {
                LoggerService.info("FDK: FOUND fdKey=\(fdKey) for button=\(button.rawValue)")
                return fdKey
            } else {
                LoggerService.info("FDK: sysMap keys=\(sysMap.keys.joined(separator: ",")) missing key=\(button.rawValue)")
            }
        } else {
            LoggerService.info("FDK: mapKey \(mapKey) not found in sysCtrlMap, keys=\(systemControlMappings?.keys.joined(separator: ",") ?? "nil")")
        }

        let key = systemID.lowercased()
        ensureLoaded(for: key)

        if let layoutMap = cachedMappings[key]?[layout] {
            for (normalizedKey, retroBtn) in layoutMap where retroBtn == button {
                return originalKeys[normalizedKey] ?? normalizedKey
            }
        }

        return fallbackReverseMapping(button: button, layout: layout)
    }

    private func fallbackReverseMapping(button: RetroButton, layout: ArcadeLayout) -> String? {
        switch layout {
        case .capcom6:
            switch button {
            case .y: return "^E"
            case .x: return "^F"
            case .l1: return "^G"
            case .b: return "^H"
            case .a: return "^I"
            case .r1: return "^J"
            default: return nil
            }
        case .midway6:
            switch button {
            case .y: return "^G"
            case .x: return "^E"
            case .l1: return "_G"
            case .b: return "^J"
            case .a: return "^H"
            case .r1: return "_R"
            default: return nil
            }
        case .snk4:
            switch button {
            case .y: return "_A"
            case .x: return "_B"
            case .b: return "_C"
            case .a: return "_D"
            default: return nil
            }
        case .capcom4:
            switch button {
            case .b: return "_A"
            default: return nil
            }
        }
    }

    private func normalizeKey(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: "^", with: "")
    }

    private func ensureLoaded(for systemID: String) {
        guard cachedMappings[systemID] == nil else { return }

        guard let url = Bundle.main.url(forResource: "arcade_button_mappings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(MappingsFile.self, from: data) else {
            cachedMappings[systemID] = [:]
            return
        }

        var result: [String: [ArcadeLayout: [String: RetroButton]]] = [:]
        var origKeys: [String: String] = [:]
        for entry in file.mappings {
            let sysKey = entry.systemID.lowercased()
            if result[sysKey] == nil { result[sysKey] = [:] }
            var layoutMap: [String: RetroButton] = [:]
            for mapping in entry.mappings {
                if let button = RetroButton(rawValue: mapping.retroButton) {
                    let normalized = normalizeKey(mapping.fightDataKey)
                    layoutMap[normalized] = button
                    origKeys[normalized] = mapping.fightDataKey
                }
            }
            result[sysKey]?[entry.layout] = layoutMap
        }

        cachedMappings = result
        originalKeys = origKeys
    }

    private func fallbackMapping(fightDataKey: String, layout: ArcadeLayout) -> RetroButton? {
        let key = normalizeKey(fightDataKey)

        if key == "_s" { return .start }
        if key == "^s" { return .select }
        if key == "_r" { return .r1 }

        switch layout {
        case .capcom6:
            switch key {
            case "e": return .y
            case "f": return .x
            case "g": return .l1
            case "h": return .b
            case "i": return .a
            case "j": return .r1
            case "_p": return .y
            case "_k": return .b
            default: return nil
            }
        case .midway6:
            switch key {
            case "g": return .y
            case "e": return .x
            case "_g": return .l1
            case "j": return .b
            case "h": return .a
            case "_r": return .r1
            default: return nil
            }
        case .snk4:
            switch key {
            case "a": return .y
            case "b": return .x
            case "c": return .b
            case "d": return .a
            default: return nil
            }
        case .capcom4:
            switch key {
            case "a": return .b
            default: return nil
            }
        }
    }

    private func resolveAlias(_ key: String) -> String {
        if key == "@R-button" { return "_R" }
        return key
    }
}
