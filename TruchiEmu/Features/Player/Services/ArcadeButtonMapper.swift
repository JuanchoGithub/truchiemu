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

    private init() {}

    func retroButton(for fightDataKey: String, layout: ArcadeLayout, systemID: String) -> RetroButton? {
        let key = systemID.lowercased()
        ensureLoaded(for: key)

        guard let layoutMap = cachedMappings[key]?[layout],
              let button = layoutMap[normalizeKey(fightDataKey)] else {
            return fallbackMapping(fightDataKey: fightDataKey, layout: layout)
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

    func translateButtonSet(_ fightDataKeys: Set<String>, layout: ArcadeLayout, systemID: String) -> Set<RetroButton> {
        var result = Set<RetroButton>()
        for key in fightDataKeys {
            if let button = retroButton(for: key, layout: layout, systemID: systemID) {
                result.insert(button)
            }
        }
        return result
    }

    func fightDataKey(for button: RetroButton, layout: ArcadeLayout, systemID: String) -> String? {
        let key = systemID.lowercased()
        ensureLoaded(for: key)

        if let layoutMap = cachedMappings[key]?[layout] {
            for (fdKey, retroBtn) in layoutMap where retroBtn == button {
                return fdKey
            }
        }

        return fallbackReverseMapping(button: button, layout: layout)
    }

    private func fallbackReverseMapping(button: RetroButton, layout: ArcadeLayout) -> String? {
        switch layout {
        case .capcom6:
            switch button {
            case .y: return "e"
            case .x: return "f"
            case .r1: return "g"
            case .b: return "h"
            case .a: return "i"
            case .r2: return "j"
            default: return nil
            }
        case .midway6:
            switch button {
            case .y: return "g"
            case .x: return "e"
            case .l1: return "_g"
            case .b: return "j"
            case .a: return "h"
            default: return nil
            }
        case .snk4:
            switch button {
            case .y: return "a"
            case .x: return "b"
            case .b: return "c"
            case .a: return "d"
            default: return nil
            }
        case .capcom4:
            switch button {
            case .b: return "a"
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
        for entry in file.mappings {
            let sysKey = entry.systemID.lowercased()
            if result[sysKey] == nil {
                result[sysKey] = [:]
            }
            var layoutMap: [String: RetroButton] = [:]
            for mapping in entry.mappings {
                if let button = RetroButton(rawValue: mapping.retroButton) {
                    layoutMap[normalizeKey(mapping.fightDataKey)] = button
                }
            }
            result[sysKey]?[entry.layout] = layoutMap
        }

        cachedMappings = result
    }

    private func fallbackMapping(fightDataKey: String, layout: ArcadeLayout) -> RetroButton? {
        let key = normalizeKey(fightDataKey)

        if key == "_s" { return .start }
        if key == "^s" { return .select }

        switch layout {
        case .capcom6:
            switch key {
            case "e": return .y
            case "f": return .x
            case "g": return .r1
            case "h": return .b
            case "i": return .a
            case "j": return .r2
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
}
