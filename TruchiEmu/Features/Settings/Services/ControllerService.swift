import Foundation
import GameController
import Combine

private let mappingVersionKey = "controller_mapping_version"
private let currentMappingVersion = 4

@MainActor
class ControllerService: ObservableObject {
    static let shared = ControllerService()
    @Published var currentSystemID: String = "default"

    @Published var connectedControllers: [PlayerController] = []

    @Published var sessionSlotAssignments: [ObjectIdentifier: Set<Int>] = [:]

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

    var parentModePlayers: Set<Int> {
        var result = Set<Int>()
        for slot in 1...4 {
            let count = connectedControllers.filter { $0.assignedPlayers.contains(slot) }.count
            if count > 1 { result.insert(slot) }
        }
        return result
    }

    var isParentModeActive: Bool { !parentModePlayers.isEmpty }

    func controllerIsInParentMode(_ player: PlayerController) -> Bool {
        !player.assignedPlayers.intersection(parentModePlayers).isEmpty
    }

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
        if storedVersion < 3 { migrateFromV2toV3() }
        if storedVersion < 4 { migrateFromV3toV4() }
        AppSettings.setInt(mappingVersionKey, value: currentMappingVersion)
    }

    private func migrateFromV2toV3() {
    }

    private func migrateFromV3toV4() {
    }

    private func setupControllerNotifications() {
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .sink { [weak self] _ in self?.refreshConnectedControllers() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .sink { [weak self] _ in self?.refreshConnectedControllers() }
            .store(in: &cancellables)
    }

    static let keyboardId = UUID()

    private static func stableId(for gc: GCController) -> UUID {
        let hash = ObjectIdentifier(gc).hashValue
        return UUID(uuid: (
            UInt8(truncatingIfNeeded: hash >> 24), UInt8(truncatingIfNeeded: hash >> 16),
            UInt8(truncatingIfNeeded: hash >> 8), UInt8(truncatingIfNeeded: hash),
            0x01, 0x23, 0x45, 0x67,
            0x89, 0xAB, 0xCD, 0xEF,
            UInt8(truncatingIfNeeded: hash), UInt8(truncatingIfNeeded: hash >> 8),
            UInt8(truncatingIfNeeded: hash >> 16), UInt8(truncatingIfNeeded: hash >> 24)
        ))
    }

    private var previousControllerIDs: Set<String> = []

    private func refreshConnectedControllers() {
        let previousIDs = previousControllerIDs
        var players: [PlayerController] = []
        var currentIDs: Set<String> = []

        let keyboardPlayer = PlayerController(
            id: Self.keyboardId,
            assignedPlayers: [1],
            mapping: ControllerGamepadMapping.defaults(for: "Keyboard", systemID: "default", handedness: handedness),
            sortOrder: 0,
            isKeyboard: true
        )
        players.append(keyboardPlayer)

        let allGCs = Array(GCController.controllers().prefix(4))
        var connectedIDs = Set<ObjectIdentifier>()
        for gc in allGCs {
            connectedIDs.insert(ObjectIdentifier(gc))
        }
        sessionSlotAssignments = sessionSlotAssignments.filter { connectedIDs.contains($0.key) }

        var nameCounts: [String: Int] = [:]
        for gc in allGCs {
            let baseName = gc.vendorName ?? "Unknown Controller"
            nameCounts[baseName, default: 0] += 1
        }

        let unassigned = allGCs.filter { sessionSlotAssignments[ObjectIdentifier($0)] == nil }
        var nextSlot = 1
        for gc in unassigned {
            while nextSlot <= 4 && hasControllerAssigned(to: nextSlot) {
                nextSlot += 1
            }
            if nextSlot <= 4 {
                sessionSlotAssignments[ObjectIdentifier(gc)] = [nextSlot]
                nextSlot += 1
            } else {
                sessionSlotAssignments[ObjectIdentifier(gc)] = [1]
            }
        }

        var nameIndices: [String: Int] = [:]
        for gc in allGCs {
            let baseName = gc.vendorName ?? "Unknown Controller"
            currentIDs.insert(baseName)

            let assigned = sessionSlotAssignments[ObjectIdentifier(gc)] ?? [1]
            let category = gc.productCategory

            LoggerService.info(category: "ControllerService", "Detected controller: vendorName=\(baseName), productCategory=\(category)")

            let mapping = savedMappings[baseName]?["default"]
            ?? ControllerGamepadMapping.defaults(for: baseName, systemID: "default", handedness: handedness)

            let displayName: String
            if nameCounts[baseName, default: 0] > 1 {
                nameIndices[baseName, default: 0] += 1
                displayName = "\(baseName) #\(nameIndices[baseName]!)"
            } else {
                displayName = baseName
            }

            var player = PlayerController(
                id: Self.stableId(for: gc),
                assignedPlayers: assigned,
                gcController: gc,
                mapping: mapping,
                sortOrder: players.count,
                productCategory: category
            )
            players.append(player)
        }

        let newIDs = currentIDs.subtracting(previousIDs)
        for player in players where !player.isKeyboard {
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

        ensureP1Exists()

        if activePlayerIndex == 0 && !players.isEmpty {
            activePlayerIndex = 1
        }
    }

    private func hasControllerAssigned(to slot: Int) -> Bool {
        sessionSlotAssignments.values.contains { $0.contains(slot) }
    }

    private func ensureP1Exists() {
        let hasP1 = sessionSlotAssignments.values.contains { $0.contains(1) }
        guard !hasP1 else { return }
        for key in sessionSlotAssignments.keys {
            var slots = sessionSlotAssignments[key] ?? []
            if let min = slots.min(), min > 1 {
                slots.insert(1)
                sessionSlotAssignments[key] = slots
                return
            }
        }
        if let firstKey = sessionSlotAssignments.keys.first {
            sessionSlotAssignments[firstKey] = [1]
        }
    }

    func assignController(_ controller: GCController, to slot: Int) {
        guard slot >= 1 && slot <= 4 else { return }
        let key = ObjectIdentifier(controller)

        var newSlots = sessionSlotAssignments[key] ?? []
        let oldPrimary = newSlots.min() ?? 1

        newSlots.remove(oldPrimary)
        newSlots.insert(slot)

        let controllersInSlot = controllersAtSlot(slot)
        for other in controllersInSlot where ObjectIdentifier(other) != key {
            let otherKey = ObjectIdentifier(other)
            var otherSlots = sessionSlotAssignments[otherKey] ?? []
            otherSlots.remove(slot)
            if otherSlots.isEmpty {
                otherSlots.insert(oldPrimary)
            }
            sessionSlotAssignments[otherKey] = otherSlots
        }

        if !newSlots.contains(1) {
            ensureP1Exists()
        }

        sessionSlotAssignments[key] = newSlots
        refreshConnectedControllers()
    }

    func toggleController(_ controller: GCController, player slot: Int) {
        guard slot >= 1 && slot <= 4 else { return }
        let key = ObjectIdentifier(controller)
        var slots = sessionSlotAssignments[key] ?? []

        if slots.contains(slot) {
            if slots.count == 1 && slot == 1 { return }
            slots.remove(slot)
            if slots.isEmpty {
                slots.insert(1)
            }
        } else {
            slots.insert(slot)
        }

        if !slots.contains(1) {
            ensureP1Exists()
        }

        sessionSlotAssignments[key] = slots
        refreshConnectedControllers()
    }

    func controllersForPlayer(_ slot: Int) -> [PlayerController] {
        connectedControllers.filter { $0.assignedPlayers.contains(slot) }
    }

    func controllersAtSlot(_ slot: Int) -> [GCController] {
        guard slot >= 1 && slot <= 4 else { return [] }
        var result: [GCController] = []
        for gc in GCController.controllers() {
            if let slots = sessionSlotAssignments[ObjectIdentifier(gc)], slots.contains(slot) {
                result.append(gc)
            }
        }
        return result
    }

    func assignedSlot(for controller: GCController) -> Int? {
        sessionSlotAssignments[ObjectIdentifier(controller)]?.min()
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

    func deadzone(for vendorName: String, systemID: String) -> (left: Float, right: Float) {
        let m = mapping(for: vendorName, systemID: systemID)
        return (left: m.leftStickDeadzone, right: m.rightStickDeadzone)
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

        if player > 1 {
            return keyboardMappings[key] ?? KeyboardMapping(buttons: [:])
        }

        return keyboardMappings[key]
            ?? keyboardMappings[kbKey(systemID, player: 1)]
            ?? keyboardMappings["default"]
            ?? KeyboardMapping.defaults(for: systemID, handedness: handedness)
    }
}
