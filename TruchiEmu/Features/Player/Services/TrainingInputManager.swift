import Foundation
import Combine

@MainActor
class TrainingInputManager {
    private let manager: TrainingModeManager
    private var cancellable: AnyCancellable?
    private var retroIDToButtonMap: [Int: RetroButton] = [:]
    private var frameCounter: Int = 0
    private var lastP1ActiveButtons: Set<RetroButton> = []
    private var blockCombo: String?

    var onP1InputUpdate: ((Set<RetroButton>, Int) -> Void)?

    init(manager: TrainingModeManager) {
        self.manager = manager
    }

    var blockButtonRawValue: String? {
        blockCombo
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
            blockCombo = nil
            return
        }
        let layout = manager.currentArcadeLayout
        let systemID = manager.currentSystemID
        let systemControlMappings = game.systemControlMappings
        let lowerSystemID = systemID.lowercased()

        if (lowerSystemID == "genesis" || lowerSystemID == "megadrive" || lowerSystemID == "32x"),
           layout == .midway6,
           AppSettings.getGenesisControllerType() == .threeButton {
            // Check which button maps to _G (Block) in this game's genesis3 mapping
            if let g3 = game.systemControlMappings?["genesis3"],
               g3["b"] == "_G" {
                blockCombo = "b"
            } else {
                blockCombo = "start"
            }
            return
        }

        // Master System MK1: block = back + punch (b). MK2: block = punch + kick (b,c)
        if lowerSystemID == "sms" || lowerSystemID == "gamegear" {
            if game.romIds.contains("mk2") {
                blockCombo = "b,c"
                return
            }
            if game.romIds.contains("mk") {
                blockCombo = "back,b"
                return
            }
        }

        for (fdKey, label) in game.controls {
            let lower = label.lowercased()
            guard lower.contains("block") || lower.contains("guard") else { continue }
            guard let button = ArcadeButtonMapper.shared.retroButton(
                for: fdKey, layout: layout, systemID: systemID,
                systemControlMappings: systemControlMappings
            ) else { continue }
            if button.isDirectional { continue }
            blockCombo = button.rawValue
            return
        }
        blockCombo = nil
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
}

