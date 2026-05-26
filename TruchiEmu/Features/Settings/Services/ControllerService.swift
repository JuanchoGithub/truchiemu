import Foundation
import GameController
import Combine

private let mappingVersionKey = "controller_mapping_version"
private let currentMappingVersion = 3

@MainActor
class ControllerService: ObservableObject {
    static let shared = ControllerService()
    @Published var currentSystemID: String = "default" 

    @Published var connectedControllers: [PlayerController] = []

    @Published var activePlayerIndex: Int = 0 {
        didSet {
            AppSettings.setInt("active_player_index", value: activePlayerIndex)
        }
    }

    @Published var handedness: String {
        didSet {
            AppSettings.set("controller_handedness", value: handedness)
        }
    }
    private let mappingKey = "controller_mappings_v2"
    private let kbMappingKey = "keyboard_mapping_v1"
    private var savedMappings: [String: [String: ControllerGamepadMapping]] = [:]

    private var cancellables = Set<AnyCancellable>()

    init() {
        self.handedness = AppSettings.get("controller_handedness", type: String.self) ?? "right"
        self.activePlayerIndex = AppSettings.getInt("active_player_index", defaultValue: 0)
        migrateIfNeeded()
        loadMappings()
        setupControllerNotifications()
        refreshConnectedControllers()
    }

    private func migrateIfNeeded() {
        let storedVersion = AppSettings.getInt(mappingVersionKey, defaultValue: 0)
        guard storedVersion < currentMappingVersion else { return }
        migrateFromV2toV3()
        AppSettings.setInt(mappingVersionKey, value: currentMappingVersion)
    }

    private func migrateFromV2toV3() {
    }

    private func setupControllerNotifications() {
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .sink { [weak self] _ in self?.refreshConnectedControllers() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .sink { [weak self] _ in self?.refreshConnectedControllers() }
            .store(in: &cancellables)
    }

    private var previousControllerIDs: Set<String> = []

    private func refreshConnectedControllers() {
        let previousIDs = previousControllerIDs
        var players: [PlayerController] = []
        var currentIDs: Set<String> = []

        for (index, gc) in GCController.controllers().prefix(4).enumerated() {
            let vendorName = gc.vendorName ?? "Unknown Controller"
            currentIDs.insert(vendorName)
            let mapping = savedMappings[vendorName]?["default"]
                ?? ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: handedness)
            players.append(PlayerController(
                playerIndex: index + 1,
                gcController: gc,
                mapping: mapping
            ))
        }

        let newIDs = currentIDs.subtracting(previousIDs)
        for player in players {
            if let vendorName = player.gcController?.vendorName, newIDs.contains(vendorName) {
                let loc = LocalizationManager.shared
                NotificationPillManager.shared.post(PillNotification(
                    icon: "gamecontroller",
                    title: loc.localized("pill.controllerConnected"),
                    subtitle: player.name,
                    autoDismissDelay: 4
                ))
                break
            }
        }

        previousControllerIDs = currentIDs
        connectedControllers = players

        if activePlayerIndex == 0 && !players.isEmpty {
            activePlayerIndex = 1
        }
    }

    func updateMapping(for vendorName: String, systemID: String, mapping: ControllerGamepadMapping) {
        var cleanedButtons = mapping.buttons
        var seenNames = Set<String>()
        for (btn, btnMapping) in mapping.buttons {
            if seenNames.contains(btnMapping.gcElementName) {
                cleanedButtons.removeValue(forKey: btn)
            } else {
                seenNames.insert(btnMapping.gcElementName)
            }
        }
        var cleaned = mapping
        cleaned.buttons = cleanedButtons
        if savedMappings[vendorName] == nil { savedMappings[vendorName] = [:] }
        savedMappings[vendorName]?[systemID] = cleaned
        
        refreshConnectedControllers()
        saveMappings()
    }
    
    func mapping(for vendorName: String, systemID: String, gameID: String? = nil) -> ControllerGamepadMapping {
        if let gid = gameID, let profile = GameMappingStorage.shared.load(for: gid),
           let overrides = profile.gamepadOverrides {
            var base = mapping(for: vendorName, systemID: systemID)
            for (btn, btnMapping) in overrides {
                base.buttons[btn] = btnMapping
            }
            return base
        }

        return savedMappings[vendorName]?[systemID]
            ?? savedMappings[vendorName]?["default"]
            ?? ControllerGamepadMapping.defaults(for: vendorName, systemID: systemID, handedness: handedness)
    }

    func updateKeyboardMapping(_ mapping: KeyboardMapping, for systemID: String) {
        var all = keyboardMappings
        all[systemID] = mapping
        keyboardMappings = all
        if let data = try? JSONEncoder().encode(all) {
            AppSettings.setData(kbMappingKey, value: data)
        }
    }

    func removeMapping(for vendorName: String, systemID: String) {
        savedMappings[vendorName]?.removeValue(forKey: systemID)
        if savedMappings[vendorName]?.isEmpty == true {
            savedMappings.removeValue(forKey: vendorName)
        }
        refreshConnectedControllers()
        saveMappings()
    }

    func removeKeyboardMapping(for systemID: String) {
        keyboardMappings.removeValue(forKey: systemID)
        if let data = try? JSONEncoder().encode(keyboardMappings) {
            AppSettings.setData(kbMappingKey, value: data)
        }
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(savedMappings) {
            AppSettings.setData(mappingKey, value: data)
        }
    }

    private func loadMappings() {
        if let data = AppSettings.getData(mappingKey),
           let saved = try? JSONDecoder().decode([String: [String: ControllerGamepadMapping]].self, from: data) {
            savedMappings = saved
        }
        
        if let data = AppSettings.getData(kbMappingKey),
           let saved = try? JSONDecoder().decode([String: KeyboardMapping].self, from: data) {
            keyboardMappings = saved
        }
    }
    
    @Published var keyboardMappings: [String: KeyboardMapping] = [:]
    
    func keyboardMapping(for systemID: String, gameID: String? = nil) -> KeyboardMapping {
        if let gid = gameID, let profile = GameMappingStorage.shared.load(for: gid),
           let overrides = profile.keyboardOverrides {
            var base = keyboardMapping(for: systemID)
            for (btn, keyCode) in overrides {
                base.buttons[btn] = keyCode
            }
            return base
        }

        return keyboardMappings[systemID]
            ?? keyboardMappings["default"]
            ?? KeyboardMapping.defaults(for: systemID, handedness: handedness)
    }
}
