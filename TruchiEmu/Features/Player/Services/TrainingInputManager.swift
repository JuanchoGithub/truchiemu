import Foundation
import Combine

@MainActor
class TrainingInputManager {
    private let manager: TrainingModeManager
    private var cancellable: AnyCancellable?
    private var lastP1AttackState: Bool = false
    private var firstHitBlocked: Bool = false
    private var jumpCooldown: Int = 0
    private var retroIDToButtonMap: [Int: RetroButton] = [:]
    private var frameCounter: Int = 0
    private var lastP1ActiveButtons: Set<RetroButton> = []
    private var blockButton: RetroButton?

    private let p2Player = 1

    var onP1InputUpdate: ((Set<RetroButton>, Int) -> Void)?

    init(manager: TrainingModeManager) {
        self.manager = manager
    }

    var blockButtonRawValue: String? {
        blockButton?.rawValue
    }

    func detachFromRunner() {
        cancellable?.cancel()
        cancellable = nil
    }

    func resolveBlockButtonIfNeeded() {
        resolveBlockButton()
    }

    func attachToRunner(_ runner: EmulatorRunner) {
        cancellable = runner.$currentInputState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.manager.lastP1InputState = state
                self?.recordP1Input(state)
            }
        rebuildRetroIDMap()
        resolveBlockButton()
    }

    private func resolveBlockButton() {
        guard let game = manager.currentGameData else {
            blockButton = nil
            return
        }
        let layout = manager.currentArcadeLayout
        let systemID = manager.currentSystemID
        let systemControlMappings = game.systemControlMappings
        let lowerSystemID = systemID.lowercased()

        if (lowerSystemID == "genesis" || lowerSystemID == "megadrive" || lowerSystemID == "32x"),
           layout == .midway6,
           AppSettings.getGenesisControllerType() == .threeButton {
            blockButton = .start
            return
        }

        for (fdKey, label) in game.controls {
            let lower = label.lowercased()
            guard lower.contains("block") || lower.contains("guard") else { continue }
            guard let button = ArcadeButtonMapper.shared.retroButton(
                for: fdKey, layout: layout, systemID: systemID,
                systemControlMappings: systemControlMappings
            ) else { continue }
            if button.isDirectional { continue }
            blockButton = button
            return
        }
        blockButton = nil
    }

    private func recordP1Input(_ state: [Int: Bool]) {
        var activeButtons = Set<RetroButton>()
        for (retroID, pressed) in state where pressed {
            if let button = retroIDToButtonMap[retroID] {
                activeButtons.insert(button)
            }
        }

        if activeButtons != lastP1ActiveButtons {
            lastP1ActiveButtons = activeButtons
            frameCounter += 1
            onP1InputUpdate?(activeButtons, frameCounter)
        }
    }

    func rebuildRetroIDMap() {
        let systemID = manager.currentSystemID
        let coreID = SystemDatabaseWrapper.shared.system(forID: systemID)?.defaultCoreID
        var map: [Int: RetroButton] = [:]
        for button in RetroButton.allCases {
            let id = button.retroID(for: systemID, coreID: coreID)
            if id >= 0 {
                map[Int(id)] = button
            }
        }
        retroIDToButtonMap = map
    }

    func perFrameTick() {
        guard manager.config.isEnabled else { return }

        let config = manager.config
        let adapter = XPCBridgeAdapter.shared

        if config.controlMode == .human {
            return
        }

        if config.controlMode == .standby {
            return
        }

        clearP2Input(adapter)

        if config.controlMode == .fmdSequence {
            applySequenceFrame(adapter: adapter)
            return
        }

        applyStance(config: config, adapter: adapter)
        applyGuard(config: config, adapter: adapter)

        if let tapeSlot = manager.sequenceRunner.currentTapeSlot() {
            let _ = manager.tapeDeck.playbackFrame(
                at: manager.tapeRunnerFrameIndex,
                slot: tapeSlot,
                adapter: adapter
            )
            manager.tapeRunnerFrameIndex += 1
            if let recording = manager.tapeDeck.slots[tapeSlot],
               manager.tapeRunnerFrameIndex >= recording.frames.count {
                manager.sequenceRunner.advanceToNextCard(adapter: adapter)
                manager.tapeRunnerFrameIndex = 0
            }
        }
    }

    private var backDirection: RetroButton {
        manager.config.p2FacesRight ? .left : .right
    }

    private func applyStance(config: TrainingModeConfig, adapter: XPCBridgeAdapter) {
        switch config.stance {
        case .stand:
            break
        case .crouch:
            pressP2Button(.down, adapter: adapter)
        case .jump:
            if jumpCooldown <= 0 {
                pressP2Button(.up, adapter: adapter)
                jumpCooldown = 4
            } else {
                jumpCooldown -= 1
            }
        }
    }

    private func applyGuard(config: TrainingModeConfig, adapter: XPCBridgeAdapter) {
        let isP1Attacking = detectP1Attack()
        let systemID = manager.currentSystemID

        switch config.guard {
        case .noBlock:
            break

        case .allBlock:
            applyBlockDirection(adapter: adapter, crouching: config.stance == .crouch)

        case .randomBlock:
            if isP1Attacking && !lastP1AttackState {
                if Bool.random() {
                    applyBlockDirection(adapter: adapter, crouching: false)
                }
            }

        case .firstHitBlock:
            if isP1Attacking && !lastP1AttackState {
                if !firstHitBlocked {
                    firstHitBlocked = true
                } else {
                    applyBlockDirection(adapter: adapter, crouching: config.stance == .crouch)
                }
            } else if !isP1Attacking && lastP1AttackState {
                firstHitBlocked = false
            }
        }

        if isP1Attacking {
            let isGuarding: Bool
            switch config.guard {
            case .allBlock: isGuarding = true
            case .randomBlock: isGuarding = true
            case .firstHitBlock: isGuarding = firstHitBlocked
            case .noBlock: isGuarding = false
            }
            manager.sequenceRunner.notifyP1Attack(p2IsGuarding: isGuarding)
        }

        lastP1AttackState = isP1Attacking
    }

    private func applyBlockDirection(adapter: XPCBridgeAdapter, crouching: Bool) {
        if let block = blockButton {
            if crouching {
                pressP2Button(.down, adapter: adapter)
            }
            pressP2Button(block, adapter: adapter)
        } else {
            if crouching {
                pressP2Button(.down, adapter: adapter)
            }
            pressP2Button(backDirection, adapter: adapter)
        }
    }

    private func detectP1Attack() -> Bool {
        let p1State = manager.lastP1InputState
        guard !p1State.isEmpty else { return false }

        let game = manager.currentGameData
        let layout = manager.currentArcadeLayout
        let systemID = manager.currentSystemID
        let systemControlMappings = game?.systemControlMappings

        for (retroID, pressed) in p1State where pressed {
            guard let button = retroIDToButtonMap[retroID], !button.isDirectional else { continue }
            if let fdKey = ArcadeButtonMapper.shared.fightDataKey(
                for: button,
                layout: layout,
                systemID: systemID,
                systemControlMappings: systemControlMappings
            ) {
                if game?.controlGroups?["_P"]?.contains(fdKey) == true { return true }
                if game?.controlGroups?["_K"]?.contains(fdKey) == true { return true }
            }
        }

        return false
    }

    private func applySequenceFrame(adapter: XPCBridgeAdapter) {
        _ = manager.sequenceRunner.advanceFrame(adapter: adapter)

        let config = manager.config
        if config.guard != .noBlock && manager.sequenceRunner.waitingForTrigger {
            applyStance(config: config, adapter: adapter)
            applyGuard(config: config, adapter: adapter)
        }
    }

    private func pressP2Button(_ button: RetroButton, adapter: XPCBridgeAdapter) {
        let retroID = Int(button.retroID(for: manager.currentSystemID))
        guard retroID >= 0 else { return }
        adapter.setKeyState(retroID: retroID, player: p2Player, pressed: true)
    }

    private func clearP2Input(_ adapter: XPCBridgeAdapter) {
        for retroID in 0..<32 {
            adapter.setKeyState(retroID: retroID, player: p2Player, pressed: false)
        }
    }
}

