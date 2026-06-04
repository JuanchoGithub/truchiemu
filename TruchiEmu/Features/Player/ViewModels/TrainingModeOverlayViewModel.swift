import Foundation
import Combine

@MainActor
class TrainingModeOverlayViewModel: ObservableObject {
    @Published var expandedCharacterId: String? = nil
    @Published var selectedTab: TrainingTab = .dummy
    @Published var p1InputHistory: [InputHistoryEntry] = []
    @Published var p2InputHistory: [InputHistoryEntry] = []
    @Published var activeCardInfo: String? = nil

    private let storageService = MoveListStorageService.shared

    var fmdMonitorText: String? {
        let runner = manager.sequenceRunner
        if runner.isExecuting, let name = runner.activeFMDMoveName {
            if runner.activeFMDTotalFrames > 0 {
                return "\(name) (\(runner.activeFMDFrame + 1)/\(runner.activeFMDTotalFrames))"
            }
            return name
        }
        if runner.waitingForTrigger {
            return "Waiting for trigger..."
        }
        return nil
    }

    static let maxHistoryEntries = 20

    struct InputHistoryEntry: Identifiable {
        let id = UUID()
        let directions: Set<RetroButton>
        let buttons: Set<RetroButton>
        let frameIndex: Int
    }

    let manager = TrainingModeManager.shared

    enum TrainingTab: Int, CaseIterable {
        case dummy = 0
        case sequence = 1
        case recording = 2
        case settings = 3
        case display = 4
        case moves = 5
    }

    var config: TrainingModeConfig { manager.config }

    var isTrainingEnabled: Bool { manager.config.isEnabled }

    var isMenuVisible: Bool { manager.isMenuVisible }

    var onCloseOverlay: (() -> Void)?

    var controlMode: TrainingControlMode {
        get { manager.config.controlMode }
        set { manager.updateConfig { $0.controlMode = newValue } }
    }

    var stance: TrainingStance {
        get { manager.config.stance }
        set { manager.updateConfig { $0.stance = newValue } }
    }

    var guardMode: TrainingGuard {
        get { manager.config.guard }
        set { manager.updateConfig { $0.guard = newValue } }
    }

    var wakeUpTech: TrainingWakeUpTech {
        get { manager.config.wakeUpTech }
        set { manager.updateConfig { $0.wakeUpTech = newValue } }
    }

    var reversalMoveId: String? {
        get { manager.config.reversalMoveId }
        set { manager.updateConfig { $0.reversalMoveId = newValue } }
    }

    var reversalMoveName: String? {
        guard let moveId = manager.config.reversalMoveId else { return nil }
        return findMoveName(moveId)
    }

    var isRecording: Bool { manager.tapeDeck.isRecording }

    var availableMovesForReversal: [FightDataMove] {
        guard let game = manager.currentGameData else { return [] }
        let charName = manager.currentCharacterName
        let character = game.characters.first { $0.name == charName } ?? game.characters.first
        return character?.moves.filter { $0.hasInputData } ?? []
    }

    var healthRegen: TrainingHealthRegen {
        get { manager.config.healthRegen }
        set { manager.updateConfig { $0.healthRegen = newValue } }
    }

    var superMeter: TrainingSuperMeter {
        get { manager.config.superMeter }
        set { manager.updateConfig { $0.superMeter = newValue } }
    }

    var resetPosition: TrainingResetPosition {
        get { manager.config.resetPosition }
        set { manager.updateConfig { $0.resetPosition = newValue } }
    }

    var sequenceTrigger: TrainingSequenceTrigger {
        get { manager.config.sequenceTrigger }
        set {
            manager.updateConfig { $0.sequenceTrigger = newValue }
            manager.sequenceRunner.setTriggerCondition(newValue)
        }
    }

    var autoInvert: Bool {
        get { manager.config.autoInvert }
        set { manager.updateConfig { $0.autoInvert = newValue } }
    }

    var frameProfile: FrameProfile {
        get { manager.config.frameProfile }
        set { manager.updateConfig { $0.frameProfile = newValue } }
    }

    var activeTapeSlot: Int {
        get { manager.config.activeTapeSlot }
        set { manager.updateConfig { $0.activeTapeSlot = newValue } }
    }

    var freezeOnMenu: Bool {
        get { manager.config.freezeOnMenu }
        set { manager.updateConfig { $0.freezeOnMenu = newValue } }
    }

    func toggleTraining() {
        manager.setEnabled(!manager.config.isEnabled)
    }

    var isArcadeSystem: Bool { manager.isArcadeSystem }

    func triggerP2Join() {
        manager.triggerP2Join()
    }

    func performReset() {
        manager.performReset()
    }

    func saveResetPoint() {
        manager.saveCustomResetPoint()
    }

    func saveCornerResetPoint() {
        manager.saveCornerResetPoint(manager.config.resetPosition)
    }

    func addSequenceCard(_ card: SequenceCard) {
        manager.updateConfig { $0.sequenceCards.append(card) }
    }

    func removeSequenceCard(at index: Int) {
        guard index >= 0, index < manager.config.sequenceCards.count else { return }
        manager.updateConfig { $0.sequenceCards.remove(at: index) }
    }

    func moveSequenceCard(from source: IndexSet, to destination: Int) {
        manager.updateConfig { $0.sequenceCards.move(fromOffsets: source, toOffset: destination) }
    }

    func toggleRecording() {
        manager.toggleRecording()
    }

    func clearTapeSlot(_ slot: Int) {
        manager.tapeDeck.clearSlot(slot)
    }

    func toggleMenu() {
        manager.toggleMenu()
    }

    func closeOverlay() {
        manager.toggleMenu()
        onCloseOverlay?()
    }

    var hasGameData: Bool { manager.currentGameData != nil }

    var onSelectCharacterAndShowMoves: (() -> Void)?

    private var gameName: String? { manager.currentGameData?.name }

    func toggleExpandCharacter(_ character: FightDataCharacter) {
        if expandedCharacterId == character.id {
            expandedCharacterId = nil
        } else {
            expandedCharacterId = character.id
        }
    }

    func sectionsForCharacter(_ character: FightDataCharacter) -> [String] {
        var sections: [String] = []
        let categoryKeys = Set(character.moves.map(\.category)).sorted()
        sections.append(contentsOf: categoryKeys)
        if let commonMoves = manager.currentGameData?.commonCommands, !commonMoves.isEmpty {
            sections.append(MoveListStorageService.commonSectionKey)
        }
        return sections
    }

    func sectionLabel(_ section: String) -> String {
        if section == MoveListStorageService.commonSectionKey {
            return LocalizationManager.shared.localized("movelist.commonMoves")
        }
        let gameCategories = manager.currentGameData?.categories ?? [:]
        return MoveListService.shared.resolveCategoryLabel(section, gameCategories: gameCategories)
    }

    func isSectionEnabled(characterName: String, section: String) -> Bool {
        guard let gName = gameName else { return section != MoveListStorageService.commonSectionKey }
        let hasEntry = storageService.hasSectionEntry(gameName: gName, characterName: characterName, section: section)
        if hasEntry {
            return !storageService.isSectionHidden(gameName: gName, characterName: characterName, section: section)
        }
        return section != MoveListStorageService.commonSectionKey
    }

    func toggleSection(characterName: String, section: String) {
        guard let gName = gameName else { return }
        storageService.toggleSectionHidden(gameName: gName, characterName: characterName, section: section)
        objectWillChange.send()
    }

    func enableAllSections(characterName: String, sections: [String]) {
        guard let gName = gameName else { return }
        storageService.setAllSections(gameName: gName, characterName: characterName, sections: sections, hidden: false)
        objectWillChange.send()
    }

    func disableAllSections(characterName: String, sections: [String]) {
        guard let gName = gameName else { return }
        storageService.setAllSections(gameName: gName, characterName: characterName, sections: sections, hidden: true)
        objectWillChange.send()
    }

    func selectCharacterAndShowMoves(_ character: FightDataCharacter) {
        MoveListService.shared.selectCharacter(character)
        expandedCharacterId = nil
        onSelectCharacterAndShowMoves?()
    }

    func selectReversalMove(_ move: FightDataMove) {
        guard let input = move.input else { return }
        let parsed = InputParser.parse(input)
        manager.updateConfig { config in
            config.reversalMoveId = move.id
            config.reversalParsedSteps = parsed
        }
    }

    func addFMDCard(_ move: FightDataMove, characterName: String) {
        guard let input = move.input else { return }
        let parsed = InputParser.parse(input)
        let card = SequenceCard.fmd(
            moveId: move.id,
            moveName: move.name ?? move.input ?? "FMD",
            characterName: characterName,
            parsedSteps: parsed
        )
        manager.updateConfig { $0.sequenceCards.append(card) }
    }

    func clearReversalMove() {
        manager.updateConfig { config in
            config.reversalMoveId = nil
            config.reversalParsedSteps = nil
        }
    }

    private func findMoveName(_ moveId: String) -> String? {
        guard let game = manager.currentGameData else { return nil }
        for character in game.characters {
            if let move = character.moves.first(where: { $0.id == moveId }) {
                return move.name ?? move.input ?? moveId
            }
        }
        return nil
    }
}
