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

    @Published var sessionSlotOrder: [ObjectIdentifier: Int] = [:]

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

        let allGCs = Array(GCController.controllers().prefix(4))
        var usedSlots = Set<Int>()
        var connectedIDs = Set<ObjectIdentifier>()
        for gc in allGCs {
            connectedIDs.insert(ObjectIdentifier(gc))
        }
        // Remove stale sessionSlotOrder entries
        sessionSlotOrder = sessionSlotOrder.filter { connectedIDs.contains($0.key) }

        let unassignedOrder = allGCs.filter { sessionSlotOrder[ObjectIdentifier($0)] == nil }

        var orderIndex = 0
        for gc in allGCs {
            let vendorName = gc.vendorName ?? "Unknown Controller"
            currentIDs.insert(vendorName)

            let preferred = sessionSlotOrder[ObjectIdentifier(gc)]
            var slot = preferred ?? 0
            if slot > 0 && !usedSlots.contains(slot) {
                usedSlots.insert(slot)
            } else {
                // Slot taken or unassigned — find the next free slot
                repeat {
                    orderIndex += 1
                    slot = orderIndex
                } while usedSlots.contains(slot) && orderIndex <= 4
                if slot > 4 { slot = max(1, (allGCs.firstIndex(of: gc) ?? 0) + 1) }
                usedSlots.insert(slot)
                if preferred != nil { sessionSlotOrder[ObjectIdentifier(gc)] = slot }
            }

            let mapping = savedMappings[vendorName]?["default"]
                ?? ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: handedness)
            players.append(PlayerController(
                playerIndex: slot,
                gcController: gc,
                mapping: mapping,
                sortOrder: players.count
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

    func assignController(_ controller: GCController, to slot: Int) {
        guard slot >= 1 && slot <= 4 else { return }
        // If slot is taken by another controller, swap them
        if let existing = controllerAtSlot(slot), existing != controller {
            let existingId = ObjectIdentifier(existing)
            sessionSlotOrder.removeValue(forKey: existingId)
        }
        sessionSlotOrder[ObjectIdentifier(controller)] = slot
        refreshConnectedControllers()
    }

    func assignedSlot(for controller: GCController) -> Int? {
        sessionSlotOrder[ObjectIdentifier(controller)]
    }

    func controllerAtSlot(_ slot: Int) -> GCController? {
        guard slot >= 1 && slot <= 4 else { return nil }
        for (id, s) in sessionSlotOrder where s == slot {
            // Find the matching GCController instance
            for gc in GCController.controllers() where ObjectIdentifier(gc) == id {
                return gc
            }
        }
        return nil
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

    func updateKeyboardMapping(_ mapping: KeyboardMapping, for systemID: String, player: Int = 1) {
        let key = kbKey(systemID, player: player)
        var all = keyboardMappings
        all[key] = mapping
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

    func removeKeyboardMapping(for systemID: String, player: Int = 1) {
        let key = kbKey(systemID, player: player)
        keyboardMappings.removeValue(forKey: key)
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
    
    private func kbKey(_ systemID: String, player: Int) -> String {
        player <= 1 ? systemID : "\(systemID)_p\(player)"
    }
    
    func keyboardMapping(for systemID: String, player: Int = 1, gameID: String? = nil) -> KeyboardMapping {
        let key = kbKey(systemID, player: player)
        if let gid = gameID, let profile = GameMappingStorage.shared.load(for: gid),
           let overrides = profile.keyboardOverrides {
            var base = keyboardMapping(for: systemID, player: player)
            for (btn, keyCode) in overrides {
                base.buttons[btn] = keyCode
            }
            return base
        }

        // Players 2-4 only get saved mappings — no fallback to P1 or defaults
        if player > 1 {
            return keyboardMappings[key] ?? KeyboardMapping(buttons: [:])
        }

        return keyboardMappings[key]
            ?? keyboardMappings[kbKey(systemID, player: 1)]
            ?? keyboardMappings["default"]
            ?? KeyboardMapping.defaults(for: systemID, handedness: handedness)
    }
}
