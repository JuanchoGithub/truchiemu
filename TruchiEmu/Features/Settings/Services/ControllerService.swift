import Foundation
import GameController
import Combine

private let mappingVersionKey = "controller_mapping_version"
private let currentMappingVersion = 5

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
    private let sdlMappingKey = "sdl_controller_mappings_v1"
    private let kbMappingKey = "keyboard_mapping_v1"
    private let identityMappingKey = "controller_identities_v1"
    private let identitySDLMappingKey = "sdl_controller_identities_v1"
    private let calibrationKey = "controller_calibration_v1"
    private let keyboardAssignedPlayersKey = "keyboard_assigned_players"
    private var savedMappings: [String: [String: ControllerGamepadMapping]] = [:]
    private var savedSDLMappings: [String: [String: SDLControllerMapping]] = [:]
    private var savedIdentityMappings: [String: [String: ControllerGamepadMapping]] = [:]
    private var savedIdentitySDLMappings: [String: [String: SDLControllerMapping]] = [:]
    private var savedCalibrations: [String: ControllerCalibration] = [:]
    private var bundledGC: [String: ControllerGamepadMapping] = [:]
    private var bundledSDL: [String: SDLControllerMapping] = [:]

    var sdlSlotAssignments: [Int32: Set<Int>] = [:]

    var replaceKeyboardWithController: Bool {
        get { AppSettings.getBool("replaceKeyboardWithController", defaultValue: true) }
        set { AppSettings.setBool("replaceKeyboardWithController", value: newValue) }
    }

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
        if storedVersion < 5 { migrateFromV4toV5() }
        AppSettings.setInt(mappingVersionKey, value: currentMappingVersion)
    }

    private func migrateFromV2toV3() {
    }

    private func migrateFromV3toV4() {
    }

    private func migrateFromV4toV5() {
    }

    private func setupControllerNotifications() {
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .sink { [weak self] _ in
                SDLInputManager.shared.reconcileWithGCControllers()
                self?.refreshConnectedControllers()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .sink { [weak self] _ in self?.refreshConnectedControllers() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sdlControllerConnected)
            .sink { [weak self] _ in
                SDLInputManager.shared.reconcileWithGCControllers()
                self?.refreshConnectedControllers()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sdlControllerDisconnected)
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
            assignedPlayers: keyboardAssignedPlayers,
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

        // If any existing controller is covering P1 (has P1 + a higher slot
        // due to ensureP1Exists after a disconnection), temporarily free P1
        // so a newly connecting controller can take it — otherwise the new
        // controller goes to P3/P4 and the covering controller stays sprawled.
        for key in sessionSlotAssignments.keys {
            var slots = sessionSlotAssignments[key]!
            if slots.contains(1) && slots.contains(where: { $0 > 1 }) {
                slots.remove(1)
                sessionSlotAssignments[key] = slots
                break
            }
        }
        for key in sdlSlotAssignments.keys {
            var slots = sdlSlotAssignments[key]!
            if slots.contains(1) && slots.contains(where: { $0 > 1 }) {
                slots.remove(1)
                sdlSlotAssignments[key] = slots
                break
            }
        }

        let unassigned = allGCs.filter { sessionSlotAssignments[ObjectIdentifier($0)] == nil }
        for gc in unassigned {
            let taken = allControllerSlots()
            let totalControllers = taken.count + 1
            if totalControllers > 4 {
                sessionSlotAssignments[ObjectIdentifier(gc)] = []
                continue
            }
            var available = Set(1...4).subtracting(taken)
            if let gap = firstGapSlot(), available.contains(gap) {
                available = [gap]
            } else if !replaceKeyboardWithController {
                let withoutKB = available.subtracting(keyboardAssignedPlayers)
                if !withoutKB.isEmpty { available = withoutKB }
            }
            if let slot = available.min() {
                sessionSlotAssignments[ObjectIdentifier(gc)] = [slot]
            }
        }

        var nameIndices: [String: Int] = [:]
        for gc in allGCs {
            let baseName = gc.vendorName ?? "Unknown Controller"
            currentIDs.insert(baseName)

            let assigned = sessionSlotAssignments[ObjectIdentifier(gc)] ?? [1]
            let category = gc.productCategory

            LoggerService.info(category: "ControllerService", "Detected controller: vendorName=\(baseName), productCategory=\(category)")

            let identity = self.identityKey(for: gc)
            let mapping: ControllerGamepadMapping
            if let saved = savedIdentityMappings[identity.compositeKey]?["default"] {
                mapping = saved
            } else if let saved = savedMappings[baseName]?["default"] {
                mapping = saved
            } else {
                mapping = ControllerGamepadMapping.defaults(for: baseName, systemID: "default", handedness: handedness)
            }

            let displayName: String
            if nameCounts[baseName, default: 0] > 1 {
                nameIndices[baseName, default: 0] += 1
                displayName = "\(baseName) #\(nameIndices[baseName]!)"
            } else {
                displayName = baseName
            }
            _ = displayName
            let player = PlayerController(
                id: Self.stableId(for: gc),
                assignedPlayers: assigned,
                gcController: gc,
                mapping: mapping,
                sortOrder: players.count,
                productCategory: category,
                identityKey: identity
            )
            players.append(player)
        }

        // SDL controllers
        let sdlIDs = SDLInputManager.shared.connectedSDLInstanceIDs()
        let existingSDLKeys = Set(sdlSlotAssignments.keys)
        let removedSDLKeys = existingSDLKeys.subtracting(sdlIDs)
        for key in removedSDLKeys { sdlSlotAssignments.removeValue(forKey: key) }

        let unassignedSDL = sdlIDs.filter { sdlSlotAssignments[$0] == nil }
        for instanceID in unassignedSDL {
            let taken = allControllerSlots()
            let totalControllers = taken.count + 1
            if totalControllers > 4 {
                sdlSlotAssignments[instanceID] = []
                continue
            }
            var available = Set(1...4).subtracting(taken)
            if let gap = firstGapSlot(), available.contains(gap) {
                available = [gap]
            } else if !replaceKeyboardWithController {
                let withoutKB = available.subtracting(keyboardAssignedPlayers)
                if !withoutKB.isEmpty { available = withoutKB }
            }
            if let slot = available.min() {
                sdlSlotAssignments[instanceID] = [slot]
            }
        }

        for instanceID in sdlIDs {
            currentIDs.insert("sdl_\(instanceID)")

            let vendorName = SDLInputManager.shared.sdlVendorName(for: instanceID)
            let sdlIdentity = self.identityKey(forSDL: instanceID)
            let sdlMapping: SDLControllerMapping
            if let identity = sdlIdentity, let saved = savedIdentitySDLMappings[identity.compositeKey]?["default"] {
                sdlMapping = saved
            } else if let saved = savedSDLMappings[vendorName]?["default"] {
                sdlMapping = saved
            } else {
                sdlMapping = SDLControllerMapping.defaults(for: "default")
            }

            let sdlControllerName = SDLInputManager.shared.sdlControllerName(for: instanceID) ?? vendorName

            let player = PlayerController(
                id: Self.stableSDLId(for: instanceID),
                assignedPlayers: sdlSlotAssignments[instanceID] ?? [1],
                mapping: ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: handedness),
                sortOrder: players.count,
                sdlInstanceID: instanceID,
                sdlMapping: sdlMapping,
                sdlName: sdlControllerName,
                identityKey: sdlIdentity
            )
            players.append(player)
        }

        let newIDs = currentIDs.subtracting(previousIDs)
        for player in players where !player.isKeyboard {
            let loc = LocalizationManager.shared
            if let vendorName = player.gcController?.vendorName, newIDs.contains(vendorName) {
                NotificationPillManager.shared.post(PillNotification(
                    icon: "gamecontroller",
                    title: loc.localized("pill.controllerConnected"),
                    subtitle: player.name,
                    autoDismissDelay: 4
                ))
                break
            } else if player.isSDL, let sdlID = player.sdlInstanceID, newIDs.contains("sdl_\(sdlID)") {
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

        // Re-wire GC controller input on active runners when controllers
        // change mid-game, so newly connected controllers get their
        // valueChangedHandler wired up with the correct slot assignment.
        if RunningGamesTracker.shared.isGameRunning {
            for wc in GameLauncher.shared.allActiveControllers() {
                wc.runner?.setupGamepadInput()
            }
        }
    }

    var keyboardAssignedPlayers: Set<Int> {
        get {
            if let raw = AppSettings.getData(keyboardAssignedPlayersKey),
               let decoded = try? JSONDecoder().decode(Set<Int>.self, from: raw) {
                return decoded
            }
            return [1]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                AppSettings.setData(keyboardAssignedPlayersKey, value: data)
            }
        }
    }

    private func hasControllerAssigned(to slot: Int) -> Bool {
        sessionSlotAssignments.values.contains { $0.contains(slot) }
            || sdlSlotAssignments.values.contains { $0.contains(slot) }
    }

    private func allControllerSlots() -> Set<Int> {
        var slots = Set<Int>()
        for s in sessionSlotAssignments.values { slots.formUnion(s) }
        for s in sdlSlotAssignments.values { slots.formUnion(s) }
        return slots
    }

    // Returns the lowest gap slot, or nil if no gap exists. A "gap" is a
    // free slot that isn't part of the contiguous free tail at the top end
    // (e.g. P3 when P1,P2,P4 are taken, or P1 when P2,P3,P4 are taken).
    // Gaps take precedence over keyboard replacement — we fill them before
    // considering whether the new controller can take a keyboard slot.
    private func firstGapSlot() -> Int? {
        let occupied = allControllerSlots().union(keyboardAssignedPlayers)
        guard occupied.count < 4 else { return nil }
        let maxOccupied = occupied.max() ?? 0
        // The tail is the contiguous free stretch beyond the highest occupied
        // slot. When maxOccupied >= 4 there is no tail (all gaps above are
        // packed in), so tail is empty.
        let tail: Set<Int>
        if maxOccupied < 4 {
            tail = Set((maxOccupied + 1)...4)
        } else {
            tail = []
        }
        let free = Set(1...4).subtracting(occupied)
        let gaps = free.subtracting(tail)
        return gaps.min()
    }

    private func ensureP1Exists() {
        let hasP1 = sessionSlotAssignments.values.contains { $0.contains(1) }
            || sdlSlotAssignments.values.contains { $0.contains(1) }
            || keyboardAssignedPlayers.contains(1)
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
            return
        }
        if sessionSlotAssignments.isEmpty && sdlSlotAssignments.isEmpty {
            keyboardAssignedPlayers = [1]
        }
    }

    // MARK: - Slot Assignment (shared mutation primitives)

    // Shared toggle semantics for a single device's slot set (GC, SDL, or
    // keyboard): remove the slot if present — never leaving the device with
    // zero slots (falls back to P1) — otherwise add it, then guarantee P1 is
    // still assigned somewhere.
    private func togglingSlot(_ slot: Int, in slots: Set<Int>) -> Set<Int> {
        var result = slots
        if result.contains(slot) {
            if result.count == 1 && slot == 1 { return result }
            result.remove(slot)
            if result.isEmpty { result.insert(1) }
        } else {
            result.insert(slot)
        }
        if !result.contains(1) { ensureP1Exists() }
        return result
    }

    // Shared assign logic: move a device's primary slot to `slot`, evicting
    // `slot` from every device in `others` — each falls back to the moving
    // device's old primary slot when it would otherwise be left empty. Applied
    // to both the GC and SDL slot maps.
    private func assigning<Key: Hashable>(key: Key, to slot: Int, map: inout [Key: Set<Int>], others: [Key]) {
        var newSlots = map[key] ?? []
        let oldPrimary = newSlots.min() ?? 1
        newSlots.remove(oldPrimary)
        newSlots.insert(slot)

        for other in others where other != key {
            var otherSlots = map[other] ?? []
            otherSlots.remove(slot)
            if otherSlots.isEmpty { otherSlots.insert(oldPrimary) }
            map[other] = otherSlots
        }

        if !newSlots.contains(1) { ensureP1Exists() }
        map[key] = newSlots
    }

    func assignController(_ controller: GCController, to slot: Int) {
        guard slot >= 1 && slot <= 4 else { return }
        let key = ObjectIdentifier(controller)
        let others = controllersAtSlot(slot).map { ObjectIdentifier($0) }
        assigning(key: key, to: slot, map: &sessionSlotAssignments, others: others)
        refreshConnectedControllers()
    }

    func toggleController(_ controller: GCController, player slot: Int) {
        guard slot >= 1 && slot <= 4 else { return }
        let key = ObjectIdentifier(controller)
        sessionSlotAssignments[key] = togglingSlot(slot, in: sessionSlotAssignments[key] ?? [])
        refreshConnectedControllers()
    }

    func disableController(_ controller: GCController) {
        let key = ObjectIdentifier(controller)
        sessionSlotAssignments[key] = []
        ensureP1Exists()
        refreshConnectedControllers()
    }

    func resetKeyboard() {
        keyboardAssignedPlayers = [1]
        refreshConnectedControllers()
    }

    func toggleKeyboardSlot(_ slot: Int) {
        guard slot >= 1 && slot <= 4 else { return }
        keyboardAssignedPlayers = togglingSlot(slot, in: keyboardAssignedPlayers)
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

    // MARK: - SDL Controller Management

    private static func stableSDLId(for instanceID: Int32) -> UUID {
        let hash = Int(instanceID)
        return UUID(uuid: (
            UInt8(truncatingIfNeeded: hash >> 24), UInt8(truncatingIfNeeded: hash >> 16),
            UInt8(truncatingIfNeeded: hash >> 8), UInt8(truncatingIfNeeded: hash),
            0x02, 0x23, 0x45, 0x67,
            0x89, 0xAB, 0xCD, 0xEF,
            UInt8(truncatingIfNeeded: hash), UInt8(truncatingIfNeeded: hash >> 8),
            UInt8(truncatingIfNeeded: hash >> 16), UInt8(truncatingIfNeeded: hash >> 24)
        ))
    }

    func toggleSDLController(_ instanceID: Int32, player slot: Int) {
        guard slot >= 1 && slot <= 4 else { return }
        sdlSlotAssignments[instanceID] = togglingSlot(slot, in: sdlSlotAssignments[instanceID] ?? [])
        refreshConnectedControllers()
    }

    func disableSDLController(_ instanceID: Int32) {
        sdlSlotAssignments[instanceID] = []
        ensureP1Exists()
        refreshConnectedControllers()
    }

    func assignSDLController(_ instanceID: Int32, to slot: Int) {
        guard slot >= 1 && slot <= 4 else { return }
        let others = Array(sdlSlotAssignments.keys)
        assigning(key: instanceID, to: slot, map: &sdlSlotAssignments, others: others)
        refreshConnectedControllers()
    }

    func assignedSDLSlot(for instanceID: Int32) -> Int? {
        sdlSlotAssignments[instanceID]?.min()
    }

    func updateSDLMapping(for vendorName: String, systemID: String, mapping: SDLControllerMapping) {
        if savedSDLMappings[vendorName] == nil { savedSDLMappings[vendorName] = [:] }
        savedSDLMappings[vendorName]?[systemID] = mapping
        refreshConnectedControllers()
        saveSDLMappings()
    }

    func sdlMapping(for vendorName: String, systemID: String, gameID: String? = nil) -> SDLControllerMapping {
        if let saved = savedSDLMappings[vendorName]?[systemID] { return saved }
        guard systemID != "default" else {
            return savedSDLMappings[vendorName]?["default"]
                ?? SDLControllerMapping.defaults(for: "default")
        }
        let global = savedSDLMappings[vendorName]?["default"]
            ?? SDLControllerMapping.defaults(for: "default")
        return global
    }

    func removeSDLMapping(for vendorName: String, systemID: String) {
        savedSDLMappings[vendorName]?.removeValue(forKey: systemID)
        if savedSDLMappings[vendorName]?.isEmpty == true {
            savedSDLMappings.removeValue(forKey: vendorName)
        }
        refreshConnectedControllers()
        saveSDLMappings()
    }

    private func saveSDLMappings() {
        if let data = try? JSONEncoder().encode(savedSDLMappings) {
            AppSettings.setData(sdlMappingKey, value: data)
        }
    }

    // MARK: - GC Controller Management

    func updateMapping(for vendorName: String, systemID: String, mapping: ControllerGamepadMapping) {
        var cleanedButtons = mapping.buttons
        var seenKeys = Set<String>()
        for (btn, btnMapping) in mapping.buttons {
            let dedupKey = btnMapping.identifier?.rawValue ?? btnMapping.gcElementName ?? UUID().uuidString
            if seenKeys.contains(dedupKey) {
                cleanedButtons.removeValue(forKey: btn)
            } else {
                seenKeys.insert(dedupKey)
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

    // MARK: - Identity-based mappings

    func identityKey(for gc: GCController) -> ControllerIdentityKey {
        let vendor = gc.vendorName ?? "Unknown Apple Controller"
        return ControllerIdentityKey(
            inputSystem: .apple,
            productKey: vendor,
            vendorName: gc.vendorName
        )
    }

    func identityKey(forSDL instanceID: Int32) -> ControllerIdentityKey? {
        let vendor = SDLInputManager.shared.sdlVendorName(for: instanceID)
        if let guid = SDLInputManager.shared.sdlControllerGUID(for: instanceID), !guid.isEmpty {
            return ControllerIdentityKey(inputSystem: .sdl, productKey: guid, vendorName: vendor)
        }
        if let vp = SDLInputManager.shared.sdlVendorProductID(for: instanceID) {
            let product = "v:\(String(format: "%04X", vp.vendor))|p:\(String(format: "%04X", vp.product))"
            return ControllerIdentityKey(inputSystem: .sdl, productKey: product, vendorName: vendor)
        }
        return ControllerIdentityKey(inputSystem: .sdl, productKey: vendor, vendorName: vendor)
    }

    func mapping(forIdentity identity: ControllerIdentityKey, systemID: String, gameID: String? = nil) -> ControllerGamepadMapping {
        if let gid = gameID, let profile = GameMappingStorage.shared.load(for: gid),
           let overrides = profile.gamepadOverrides {
            var base = mapping(forIdentity: identity, systemID: systemID)
            for (btn, btnMapping) in overrides {
                base.buttons[btn] = btnMapping
            }
            return base
        }

        let key = identity.compositeKey
        if let saved = savedIdentityMappings[key]?[systemID] { return saved }
        if let saved = savedIdentityMappings[key]?["default"] {
            return resolveForSystem(saved, vendorName: identity.vendorName ?? "Unknown", systemID: systemID)
        }

        if let vendor = identity.vendorName, let legacy = savedMappings[vendor]?[systemID] {
            return legacy
        }
        if let vendor = identity.vendorName, let legacy = savedMappings[vendor]?["default"] {
            return resolveForSystem(legacy, vendorName: vendor, systemID: systemID)
        }

        if let bundled = bundledGC[key] {
            return resolveForSystem(bundled, vendorName: identity.vendorName ?? "Unknown", systemID: systemID)
        }

        return resolveDefault(vendorName: identity.vendorName ?? "Unknown", systemID: systemID)
    }

    func updateMapping(forIdentity identity: ControllerIdentityKey, systemID: String, mapping: ControllerGamepadMapping) {
        var cleanedButtons = mapping.buttons
        var seenKeys = Set<String>()
        for (btn, btnMapping) in mapping.buttons {
            let dedupKey = btnMapping.identifier?.rawValue ?? btnMapping.gcElementName ?? UUID().uuidString
            if seenKeys.contains(dedupKey) {
                cleanedButtons.removeValue(forKey: btn)
            } else {
                seenKeys.insert(dedupKey)
            }
        }
        var cleaned = mapping
        cleaned.buttons = cleanedButtons
        let key = identity.compositeKey
        if savedIdentityMappings[key] == nil { savedIdentityMappings[key] = [:] }
        savedIdentityMappings[key]?[systemID] = cleaned
        refreshConnectedControllers()
        saveIdentityMappings()
    }

    func sdlMapping(forIdentity identity: ControllerIdentityKey, systemID: String, gameID: String? = nil) -> SDLControllerMapping {
        let key = identity.compositeKey
        if let saved = savedIdentitySDLMappings[key]?[systemID] { return saved }
        if let saved = savedIdentitySDLMappings[key]?["default"] { return saved }
        if let vendor = identity.vendorName, let legacy = savedSDLMappings[vendor]?[systemID] { return legacy }
        if let vendor = identity.vendorName, let legacy = savedSDLMappings[vendor]?["default"] { return legacy }
        if let bundled = bundledSDL[key] { return bundled }
        return SDLControllerMapping.defaults(for: systemID)
    }

    func updateSDLMapping(forIdentity identity: ControllerIdentityKey, systemID: String, mapping: SDLControllerMapping) {
        let key = identity.compositeKey
        if savedIdentitySDLMappings[key] == nil { savedIdentitySDLMappings[key] = [:] }
        savedIdentitySDLMappings[key]?[systemID] = mapping
        refreshConnectedControllers()
        saveIdentitySDLMappings()
    }

    func removeMapping(forIdentity identity: ControllerIdentityKey, systemID: String) {
        let key = identity.compositeKey
        savedIdentityMappings[key]?.removeValue(forKey: systemID)
        if savedIdentityMappings[key]?.isEmpty == true {
            savedIdentityMappings.removeValue(forKey: key)
        }
        refreshConnectedControllers()
        saveIdentityMappings()
    }

    func removeSDLMapping(forIdentity identity: ControllerIdentityKey, systemID: String) {
        let key = identity.compositeKey
        savedIdentitySDLMappings[key]?.removeValue(forKey: systemID)
        if savedIdentitySDLMappings[key]?.isEmpty == true {
            savedIdentitySDLMappings.removeValue(forKey: key)
        }
        refreshConnectedControllers()
        saveIdentitySDLMappings()
    }

    // MARK: - Analog Stick Calibration

    /// Hardware-level stick range calibration for a controller identity. Stored
    /// separately from per-system mappings because it is a physical property of
    /// the controller, not of any system. Missing entries return no-op defaults.
    func calibration(for identity: ControllerIdentityKey) -> ControllerCalibration {
        savedCalibrations[identity.compositeKey] ?? ControllerCalibration()
    }

    func calibration(forGC controller: GCController) -> ControllerCalibration {
        calibration(for: identityKey(for: controller))
    }

    func calibration(forSDL instanceID: Int32) -> ControllerCalibration {
        guard let identity = identityKey(forSDL: instanceID) else {
            return ControllerCalibration()
        }
        return calibration(for: identity)
    }

    func saveCalibration(_ calibration: ControllerCalibration, for identity: ControllerIdentityKey) {
        if calibration.isDefault {
            savedCalibrations.removeValue(forKey: identity.compositeKey)
        } else {
            savedCalibrations[identity.compositeKey] = calibration
        }
        saveCalibrations()
    }

    func clearCalibration(for identity: ControllerIdentityKey) {
        savedCalibrations.removeValue(forKey: identity.compositeKey)
        saveCalibrations()
    }

    private func saveCalibrations() {
        if let data = try? JSONEncoder().encode(savedCalibrations) {
            AppSettings.setData(calibrationKey, value: data)
        }
    }

    private func resolveForSystem(_ globalMapping: ControllerGamepadMapping, vendorName: String, systemID: String) -> ControllerGamepadMapping {
        guard systemID != "default" else { return globalMapping }
        let availableButtons = RetroButton.availableButtons(for: systemID)
        let oldDefaults = ControllerGamepadMapping.defaults(for: vendorName, systemID: systemID, handedness: handedness)

        var retroIDToIdentity: [Int32: RetroButton] = [:]
        for btn in RetroButton.allCases {
            if let rid = CoreButtonOverride.identityID(for: btn) {
                retroIDToIdentity[rid] = btn
            }
        }

        var result = ControllerGamepadMapping(vendorName: vendorName, buttons: [:])
        for btn in availableButtons {
            let rid = btn.retroID(for: systemID)
            if rid >= 0, let identityBtn = retroIDToIdentity[rid],
               let gcMapping = globalMapping.buttons[identityBtn] {
                result.buttons[btn] = gcMapping
            } else if let gcMapping = globalMapping.buttons[btn] {
                result.buttons[btn] = gcMapping
            } else if let gcMapping = oldDefaults.buttons[btn] {
                result.buttons[btn] = gcMapping
            }
        }
        return result
    }

    private func resolveDefault(vendorName: String, systemID: String) -> ControllerGamepadMapping {
        guard systemID != "default" else {
            return ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: handedness)
        }
        let globalDefault = savedMappings[vendorName]?["default"]
            ?? ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: handedness)
        return resolveForSystem(globalDefault, vendorName: vendorName, systemID: systemID)
    }

    private func saveIdentityMappings() {
        if let data = try? JSONEncoder().encode(savedIdentityMappings) {
            AppSettings.setData(identityMappingKey, value: data)
        }
    }

    private func saveIdentitySDLMappings() {
        if let data = try? JSONEncoder().encode(savedIdentitySDLMappings) {
            AppSettings.setData(identitySDLMappingKey, value: data)
        }
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

        if let saved = savedMappings[vendorName]?[systemID] {
            return saved
        }

        guard systemID != "default" else {
            return savedMappings[vendorName]?["default"]
                ?? ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: handedness)
        }

        let globalMapping = savedMappings[vendorName]?["default"]
            ?? ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: handedness)

        let availableButtons = RetroButton.availableButtons(for: systemID)
        let oldDefaults = ControllerGamepadMapping.defaults(for: vendorName, systemID: systemID, handedness: handedness)

        var retroIDToIdentity: [Int32: RetroButton] = [:]
        for btn in RetroButton.allCases {
            if let rid = CoreButtonOverride.identityID(for: btn) {
                retroIDToIdentity[rid] = btn
            }
        }

        var result = ControllerGamepadMapping(vendorName: vendorName, buttons: [:])

        for btn in availableButtons {
            let rid = btn.retroID(for: systemID)
            if rid >= 0, let identityBtn = retroIDToIdentity[rid],
               let gcMapping = globalMapping.buttons[identityBtn] {
                result.buttons[btn] = gcMapping
            } else if let gcMapping = globalMapping.buttons[btn] {
                result.buttons[btn] = gcMapping
            } else if let gcMapping = oldDefaults.buttons[btn] {
                result.buttons[btn] = gcMapping
            }
        }

        return result
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
            migrateStaleGenesisMappings()
        }

        if let data = AppSettings.getData(sdlMappingKey),
           let saved = try? JSONDecoder().decode([String: [String: SDLControllerMapping]].self, from: data) {
            savedSDLMappings = saved
        }

        if let data = AppSettings.getData(identityMappingKey),
           let saved = try? JSONDecoder().decode([String: [String: ControllerGamepadMapping]].self, from: data) {
            savedIdentityMappings = saved
        }

        if let data = AppSettings.getData(identitySDLMappingKey),
           let saved = try? JSONDecoder().decode([String: [String: SDLControllerMapping]].self, from: data) {
            savedIdentitySDLMappings = saved
        }

        if let data = AppSettings.getData(calibrationKey),
           let saved = try? JSONDecoder().decode([String: ControllerCalibration].self, from: data) {
            savedCalibrations = saved
        }

        if let data = AppSettings.getData(kbMappingKey),
           let saved = try? JSONDecoder().decode([String: KeyboardMapping].self, from: data) {
            keyboardMappings = saved
        }

        let bundled = BundledControllerPresets.load()
        bundledGC = bundled.gc
        bundledSDL = bundled.sdl
    }

    private func migrateStaleGenesisMappings() {
        let genesisSystems: Set<String> = ["genesis", "megadrive", "32x"]
        var changed = false
        for (vendor, sysMap) in savedMappings {
            for (sysID, mapping) in sysMap {
                guard genesisSystems.contains(sysID.lowercased()) else { continue }
                let hasCWithoutX = mapping.buttons[.c] != nil && mapping.buttons[.x] == nil
                let hasDuplicateGC = mapping.buttons[.c]?.gcElementName == mapping.buttons[.a]?.gcElementName
                if hasCWithoutX || hasDuplicateGC {
                    savedMappings[vendor]?[sysID] = self.mapping(for: vendor, systemID: sysID)
                    changed = true
                }
            }
        }
        if changed { saveMappings() }
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
