import Foundation
import Combine

@MainActor
class MoveListOverlayViewModel: ObservableObject {
    @Published private(set) var filteredMoves: [ResolvedMove] = []
    @Published private(set) var isOverlayVisible: Bool = false
    @Published private(set) var needsCharacterSelection: Bool = false
    @Published private(set) var hasGameData: Bool = false
    @Published private(set) var matchedMoveName: String? = nil
    @Published private(set) var inputSteps: [InputDisplayStep] = []
    @Published private(set) var inputDirections: [FightDataDirection] = []
    @Published private(set) var inputDirectionCharges: [Bool] = []
    @Published private(set) var inputButtons: [Set<String>] = []
    @Published private(set) var pendingCharacter: FightDataCharacter? = nil
    @Published private(set) var matchedDirectionCount: Int = 0
    @Published private(set) var matchedButtonCount: Int = 0
    @Published private(set) var expandedCharacterId: String? = nil
    @Published private(set) var buttonKeyLabels: [String: String] = [:]
    @Published var enabledCharacterName: String? = nil
    @Published private(set) var showMoveNames: Bool = false

    let moveListService: MoveListService
    let inputStateTracker: InputStateTracker

    private var cancellables = Set<AnyCancellable>()
    private var moveAttemptCounts: [String: Int] = [:]
    private var directionAttemptCounts: [FightDataDirection: Int] = [:]
    private var lastSequenceLength: Int = 0
    private let storageService = MoveListStorageService.shared

    private let moveForest = MoveForest()
    private var lastForestCompleted: [String] = []

    private var maxMovesToShow: Int { AppSettings.getInt("moveListMaxMoves", defaultValue: 5) }
    private var moveSlotOrder: [String] = []

    init(runner: EmulatorRunner) {
        self.moveListService = MoveListService()
        self.inputStateTracker = InputStateTracker(runner: runner)

        inputStateTracker.$inputSequence
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sequence in
                self?.updateFilteredMoves(for: sequence)
            }
            .store(in: &cancellables)

        inputStateTracker.$detectedMotions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateFilteredMoves(for: self.inputStateTracker.inputSequence)
            }
            .store(in: &cancellables)

        moveListService.$selectedCharacter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateFilteredMoves(for: self.inputStateTracker.inputSequence)
            }
            .store(in: &cancellables)

        moveListService.$currentGameData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.hasGameData = data != nil
            }
            .store(in: &cancellables)
    }

    func activate() {
        enabledCharacterName = nil
        pendingCharacter = nil
        needsCharacterSelection = true
        isOverlayVisible = false
        showMoveNames = AppSettings.getBool("moveListShowMoveNames", defaultValue: false)
        computeButtonKeyLabels(systemID: inputStateTracker.systemID)
    }

    func selectPendingCharacter(_ character: FightDataCharacter) {
        pendingCharacter = character
    }

    func toggleCharacter(_ character: FightDataCharacter) {
        if enabledCharacterName == character.name {
            enabledCharacterName = nil
            isOverlayVisible = false
            filteredMoves = []
            inputStateTracker.clearSequence()
            inputSteps = []
            inputDirections = []
            inputDirectionCharges = []
            return
        }
        moveListService.selectCharacter(character)
        enabledCharacterName = character.name
        pendingCharacter = nil
        expandedCharacterId = nil
        needsCharacterSelection = true
        isOverlayVisible = true
        updateFilteredMoves(for: inputStateTracker.inputSequence)
        NotationTokenImageCache.shared.prepareCache(moves: filteredMoves)
    }

    func showCharacterSelection() {
        needsCharacterSelection = true
        isOverlayVisible = false
        expandedCharacterId = nil
    }

    func confirmPendingCharacter() {
        guard let character = pendingCharacter else { return }
        moveListService.selectCharacter(character)
        enabledCharacterName = character.name
        pendingCharacter = nil
        expandedCharacterId = nil
        needsCharacterSelection = false
        isOverlayVisible = true
        updateFilteredMoves(for: inputStateTracker.inputSequence)
        NotationTokenImageCache.shared.prepareCache(moves: filteredMoves)
    }

    func confirmCharacter(_ character: FightDataCharacter) {
        moveListService.selectCharacter(character)
        pendingCharacter = nil
        expandedCharacterId = nil
        enabledCharacterName = character.name
        needsCharacterSelection = false
        isOverlayVisible = true
        updateFilteredMoves(for: inputStateTracker.inputSequence)
        NotationTokenImageCache.shared.prepareCache(moves: filteredMoves)
    }

    func deactivate() {
        isOverlayVisible = false
        needsCharacterSelection = false
        enabledCharacterName = nil
        pendingCharacter = nil
        expandedCharacterId = nil
        inputStateTracker.clearSequence()
        filteredMoves = []
        moveSlotOrder.removeAll()
        inputSteps = []
        inputDirections = []
        inputDirectionCharges = []
        inputButtons = []
        matchedMoveName = nil
        moveAttemptCounts.removeAll()
        directionAttemptCounts.removeAll()
        NotationTokenImageCache.shared.clear()
    }

    func loadForGame(_ rom: ROM) {
        moveListService.loadGameData(for: rom)
        let systemID = rom.systemID ?? "default"
        inputStateTracker.systemID = systemID
        if let game = moveListService.currentGameData {
            inputStateTracker.arcadeLayout = ArcadeButtonMapper.shared.arcadeLayout(for: game)
            inputStateTracker.systemControlMappings = game.systemControlMappings
        }
        computeButtonKeyLabels(systemID: systemID)
        updateFilteredMoves(for: inputStateTracker.inputSequence)
    }

    func refreshButtonKeyLabels() {
        let systemID = inputStateTracker.systemID
        computeButtonKeyLabels(systemID: systemID)
        updateFilteredMoves(for: inputStateTracker.inputSequence)
    }

    var buttonDisplayMode: ButtonDisplayMode {
        ButtonDisplayMode.current
    }

    private func computeButtonKeyLabels(systemID: String) {
        guard let game = moveListService.currentGameData else {
            buttonKeyLabels = [:]
            return
        }
        let layout = ArcadeButtonMapper.shared.arcadeLayout(for: game)
        let controlLabelKeys = Array(moveListService.controlLabels.keys)
        let controlAbbrKeys = Array(moveListService.controlAbbreviations.keys)
        let groupKeys = game.controlGroups.flatMap { Array($0.keys) } ?? []
        let uniqueKeys = Array(Set(controlLabelKeys + controlAbbrKeys + groupKeys))
        switch ButtonDisplayMode.current {
        case .symbol:
            buttonKeyLabels = [:]
        case .consoleButton:
            buttonKeyLabels = ButtonKeyResolver.allConsoleButtonLabels(
                fightDataKeys: uniqueKeys,
                systemID: systemID,
                layout: layout,
                systemControlMappings: game.systemControlMappings
            )
        case .inputKey:
            buttonKeyLabels = ButtonKeyResolver.allKeyLabels(
                fightDataKeys: uniqueKeys,
                systemID: systemID,
                layout: layout,
                systemControlMappings: game.systemControlMappings
            )
        }
    }

    func selectCharacter(_ character: FightDataCharacter) {
        moveListService.selectCharacter(character)
    }

    func toggleFavorite(moveId: String) {
        guard let gameName = gameName else { return }
        let charName = isCommonMoveId(moveId) ? "__common__" : (selectedCharacterName ?? "")
        storageService.toggleFavorite(gameName: gameName, characterName: charName, moveId: moveId)
        updateFilteredMoves(for: inputStateTracker.inputSequence)
    }

    func toggleHidden(moveId: String) {
        guard let gameName = gameName else { return }
        let charName = isCommonMoveId(moveId) ? "__common__" : (selectedCharacterName ?? "")
        storageService.toggleHidden(gameName: gameName, characterName: charName, moveId: moveId)
        updateFilteredMoves(for: inputStateTracker.inputSequence)
    }

    func isFavorite(moveId: String) -> Bool {
        guard let gameName = gameName else { return false }
        let charName = isCommonMoveId(moveId) ? "__common__" : (selectedCharacterName ?? "")
        return storageService.isFavorite(gameName: gameName, characterName: charName, moveId: moveId)
    }

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
        if let commonMoves = moveListService.currentGameData?.commonCommands, !commonMoves.isEmpty {
            sections.append(MoveListStorageService.commonSectionKey)
        }
        return sections
    }

    func sectionLabel(_ section: String) -> String {
        if section == MoveListStorageService.commonSectionKey {
            return LocalizationManager.shared.localized("movelist.commonMoves")
        }
        let gameCategories = moveListService.currentGameData?.categories ?? [:]
        return moveListService.resolveCategoryLabel(section, gameCategories: gameCategories)
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
        if moveListService.selectedCharacter?.name == characterName {
            updateFilteredMoves(for: inputStateTracker.inputSequence)
        }
    }

    func enableAllSections(characterName: String, sections: [String]) {
        guard let gName = gameName else { return }
        storageService.setAllSections(gameName: gName, characterName: characterName, sections: sections, hidden: false)
        objectWillChange.send()
        if moveListService.selectedCharacter?.name == characterName {
            updateFilteredMoves(for: inputStateTracker.inputSequence)
        }
    }

    func disableAllSections(characterName: String, sections: [String]) {
        guard let gName = gameName else { return }
        storageService.setAllSections(gameName: gName, characterName: characterName, sections: sections, hidden: true)
        objectWillChange.send()
        if moveListService.selectedCharacter?.name == characterName {
            updateFilteredMoves(for: inputStateTracker.inputSequence)
        }
    }

    func confirmAndShowOverlay(character: FightDataCharacter) {
        moveListService.selectCharacter(character)
        enabledCharacterName = character.name
        pendingCharacter = nil
        expandedCharacterId = nil
        needsCharacterSelection = false
        isOverlayVisible = true
        updateFilteredMoves(for: inputStateTracker.inputSequence)
        NotationTokenImageCache.shared.prepareCache(moves: filteredMoves)
    }



    var gameName: String? {
        moveListService.currentGameData?.name
    }

    var characters: [FightDataCharacter] {
        moveListService.availableCharacters
    }

    var selectedCharacterName: String? {
        moveListService.selectedCharacter?.name
    }

    var commonNotes: [String] {
        moveListService.commonNotes
    }

    var cheatNotes: [String] {
        moveListService.cheatNotes
    }

    var maxDisplayMoves: Int { maxMovesToShow }

    var hasActiveInput: Bool {
        !inputSteps.isEmpty
    }

    private func updateFilteredMoves(for sequence: [InputSequenceStep]) {
        guard let character = moveListService.selectedCharacter else {
            filteredMoves = []
            return
        }

        showMoveNames = AppSettings.getBool("moveListShowMoveNames", defaultValue: false)
        computeButtonKeyLabels(systemID: inputStateTracker.systemID)

        let rawDirections = inputStateTracker.rawDirectionHistory
        let motions = inputStateTracker.detectedMotions

        var directions: [FightDataDirection] = rawDirections
        var directionCharges: [Bool] = Array(repeating: false, count: rawDirections.count)
        var buttons: [Set<String>] = []
        for step in sequence {
            if !step.buttons.isEmpty {
                buttons.append(step.buttons)
            }
        }

        var steps: [InputDisplayStep] = []
        if !motions.isEmpty {
            let motionRawCounts = motions.map { (motion: DetectedMotion) -> Int in
                switch motion {
                case .quarterCircle: return 3
                case .halfCircle: return 5
                case .fullCircle: return 8
                }
            }
            let totalConsumed = motionRawCounts.reduce(0, +)
            let unconsumedCount = max(0, rawDirections.count - totalConsumed)
            var rawDirsSeen = 0
            var motionTokensInserted = false

            for step in sequence {
                if step.direction != nil {
                    rawDirsSeen += 1
                }
                if rawDirsSeen > unconsumedCount && !motionTokensInserted {
                    for motion in motions {
                        switch motion {
                        case .quarterCircle(let from):
                            steps.append(.motion(.quarterCircle(from: from)))
                        case .halfCircle(let from):
                            steps.append(.motion(.halfCircle(from: from)))
                        case .fullCircle(let direction):
                            steps.append(.motion(.fullCircle(direction: direction)))
                        }
                    }
                    motionTokensInserted = true
                }
                let dirConsumed = step.direction != nil && rawDirsSeen > unconsumedCount
                if !dirConsumed, let dir = step.direction {
                    steps.append(.direction(dir, isCharge: step.isCharge))
                }
                if !step.buttons.isEmpty {
                    steps.append(.buttons(step.buttons))
                }
            }

            if !motionTokensInserted {
                for motion in motions {
                    switch motion {
                    case .quarterCircle(let from):
                        steps.append(.motion(.quarterCircle(from: from)))
                    case .halfCircle(let from):
                        steps.append(.motion(.halfCircle(from: from)))
                    case .fullCircle(let direction):
                        steps.append(.motion(.fullCircle(direction: direction)))
                    }
                }
            }
        } else {
            for step in sequence {
                if let dir = step.direction {
                    steps.append(.direction(dir, isCharge: step.isCharge))
                }
                if !step.buttons.isEmpty {
                    steps.append(.buttons(step.buttons))
                }
            }
        }
        inputSteps = steps
        inputDirections = directions
        inputDirectionCharges = directionCharges
        inputButtons = buttons

        if lastSequenceLength >= 2 && sequence.isEmpty {
            recordAttempt()
        }
        lastSequenceLength = sequence.count

        for dir in directions {
            directionAttemptCounts[dir, default: 0] += 1
        }

        var allMoves = collectAllMoves(for: character)
        moveForest.build(with: allMoves)
        let favoriteIds = Set(storageService.getFavorites(gameName: gameName ?? "", characterName: character.name).map(\.moveId))

        if directions.isEmpty && buttons.isEmpty {
            moveSlotOrder.removeAll()
            allMoves.sort { moveRank($0, isFavorite: favoriteIds.contains($0.id), hasInput: false) > moveRank($1, isFavorite: favoriteIds.contains($1.id), hasInput: false) }
        filteredMoves = allMoves.map { move in
            ResolvedMove(
                id: move.id, name: move.name, categoryLabel: move.categoryLabel,
                notation: move.notation, tokens: move.tokens,
                hitLevels: move.hitLevels, condition: move.condition,
                parsedSteps: move.parsedSteps, isAir: move.isAir, isCharge: move.isCharge,
                isMotion360: move.isMotion360,
                matchCount: 0, totalSteps: move.totalSteps, matchedStepCount: 0
            )
            }.prefix(maxMovesToShow).map { $0 }
            matchedMoveName = nil
            matchedDirectionCount = 0
            matchedButtonCount = 0
            return
        }

        let forestResult = moveForest.evaluate(inputs: sequence, controlGroups: moveListService.currentGameData?.controlGroups ?? [:])
        let inProgress = forestResult.inProgress
        let completedMoves = forestResult.completed
        lastForestCompleted = completedMoves

        let candidateIds = Set(inProgress.keys)
        let matching = allMoves.filter { candidateIds.contains($0.id) }
        let sorted = matching.sorted { moveRank($0, isFavorite: favoriteIds.contains($0.id), hasInput: true) > moveRank($1, isFavorite: favoriteIds.contains($1.id), hasInput: true) }

        if let longest = allMoves.filter({ completedMoves.contains($0.id) }).max(by: { $0.totalSteps < $1.totalSteps }) {
            matchedMoveName = longest.name
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.matchedMoveName = nil
                self?.inputStateTracker.clearSequence()
            }
        } else {
            matchedMoveName = nil
        }

        let dirMatched = computeMatchedDirectionCount(directions: directions)
        let btnMatched = computeMatchedButtonCount(buttons: buttons)
        matchedDirectionCount = dirMatched
        matchedButtonCount = btnMatched

        let topCandidates = Array(sorted.prefix(maxMovesToShow))
        let topIds = Set(topCandidates.map(\.id))

        moveSlotOrder = moveSlotOrder.filter { topIds.contains($0) }
        let existingIds = Set(moveSlotOrder)
        let newMoves = topCandidates.filter { !existingIds.contains($0.id) }
            .sorted { $0.totalSteps < $1.totalSteps }
        moveSlotOrder.append(contentsOf: newMoves.map(\.id))
        if moveSlotOrder.count > maxMovesToShow {
            moveSlotOrder = Array(moveSlotOrder.prefix(maxMovesToShow))
        }

        var moveById: [String: ResolvedMove] = [:]
        for move in topCandidates {
            moveById[move.id] = move
        }

        filteredMoves = moveSlotOrder.compactMap { id -> ResolvedMove? in
            guard let move = moveById[id] else { return nil }
            let matched = inProgress[move.id]?.matched ?? 0
            return ResolvedMove(
                id: move.id, name: move.name, categoryLabel: move.categoryLabel,
                notation: move.notation, tokens: move.tokens,
                hitLevels: move.hitLevels, condition: move.condition,
                parsedSteps: move.parsedSteps, isAir: move.isAir, isCharge: move.isCharge,
                isMotion360: move.isMotion360,
                matchCount: move.matchCount, totalSteps: move.totalSteps,
                matchedStepCount: matched
            )
        }
    }

    private func computeMatchedDirectionCount(directions: [FightDataDirection]) -> Int {
        guard !filteredMoves.isEmpty else { return 0 }
        return directions.count
    }

    private func computeMatchedButtonCount(buttons: [Set<String>]) -> Int {
        guard !filteredMoves.isEmpty else { return 0 }
        return buttons.count
    }

    private func collectAllMoves(for character: FightDataCharacter) -> [ResolvedMove] {
        guard let gameName = gameName else { return [] }
        var moves: [ResolvedMove] = []
        let categoryLabels = moveListService.categoryLabels
        let hiddenMoveIds = Set(storageService.getHidden(gameName: gameName, characterName: character.name).map(\.moveId))

        let charSections = sectionsForCharacter(character)
        let disabledSections = Set(charSections.filter { !isSectionEnabled(characterName: character.name, section: $0) })

        for move in character.moves where move.hasInputData {
            if hiddenMoveIds.contains(move.id) { continue }
            if disabledSections.contains(move.category) { continue }
            let resolved: ResolvedMove
            if let overrideEntry = storageService.getOverride(gameName: gameName, characterName: character.name, moveId: move.id),
               let overrideData = overrideEntry.overrideJSON?.data(using: .utf8),
               let overrideMove = try? JSONDecoder().decode(FightDataMove.self, from: overrideData) {
                resolved = resolveMove(overrideMove, categoryLabels: categoryLabels)
            } else {
                resolved = resolveMove(move, categoryLabels: categoryLabels)
            }
            moves.append(resolved)
        }

        if let commonMoves = moveListService.currentGameData?.commonCommands {
            let commonSectionEnabled = !disabledSections.contains(MoveListStorageService.commonSectionKey)
            if commonSectionEnabled {
                let commonHiddenMoveIds = Set(storageService.getHidden(gameName: gameName, characterName: "__common__").map(\.moveId))
                for move in commonMoves where move.hasInputData {
                    if commonHiddenMoveIds.contains(move.id) { continue }
                    let resolved: ResolvedMove
                    if let overrideEntry = storageService.getOverride(gameName: gameName, characterName: "__common__", moveId: move.id),
                       let overrideData = overrideEntry.overrideJSON?.data(using: .utf8),
                       let overrideMove = try? JSONDecoder().decode(FightDataMove.self, from: overrideData) {
                        resolved = resolveMove(overrideMove, categoryLabels: categoryLabels)
                    } else {
                        resolved = resolveMove(move, categoryLabels: categoryLabels)
                    }
                    moves.append(resolved)
                }
            }
        }

        let customEntries = storageService.getCustomMoves(gameName: gameName, characterName: character.name)
        for entry in customEntries {
            guard let data = entry.customMoveJSON?.data(using: .utf8),
                  let move = try? JSONDecoder().decode(FightDataMove.self, from: data) else { continue }
            if disabledSections.contains(move.category) { continue }
            let resolved = resolveMove(move, categoryLabels: categoryLabels)
            moves.append(resolved)
        }

        let commonSectionEnabled = !disabledSections.contains(MoveListStorageService.commonSectionKey)
        if commonSectionEnabled {
            let commonCustomEntries = storageService.getCustomMoves(gameName: gameName, characterName: "__common__")
            for entry in commonCustomEntries {
                guard let data = entry.customMoveJSON?.data(using: .utf8),
                      let move = try? JSONDecoder().decode(FightDataMove.self, from: data) else { continue }
                let resolved = resolveMove(move, categoryLabels: categoryLabels)
                moves.append(resolved)
            }
        }

        return moves
    }

    private func resolveMove(_ move: FightDataMove, categoryLabels: [String: String]) -> ResolvedMove {
        let catLabel = moveListService.resolveCategoryLabel(move.category)
        let parsedSteps = InputParser.parse(move.input ?? "")
        let tokens = buildTokens(for: move)
        let notation = move.input?.replacingOccurrences(of: "_", with: "") ?? ""
        let hl = move.hitLevels.map { HitLevel.parse($0) } ?? []

        let isAir = parsedSteps.first?.first?.isAirStep == true
        let isCharge = parsedSteps.first?.contains(where: { $0.isCharge }) ?? false
        let isMotion360 = detectMotion360(parsedSteps)
        let totalSteps = parsedSteps.first?.count ?? 0

        return ResolvedMove(
            id: move.id, name: move.name ?? move.input ?? "", categoryLabel: catLabel,
            notation: notation, tokens: tokens,
            hitLevels: hl, condition: move.condition,
            parsedSteps: parsedSteps,
            isAir: isAir, isCharge: isCharge, isMotion360: isMotion360,
            matchCount: 0, totalSteps: totalSteps, matchedStepCount: 0
        )
    }

    private func detectMotion360(_ stepSequences: [[ParsedStep]]) -> Bool {
        guard let steps = stepSequences.first else { return false }
        if steps.contains(where: { $0.isMotion360 }) { return true }
        let dirs = steps.compactMap { $0.direction }
        return dirs.contains { ![5].contains($0) } && dirs.count >= 7
    }

    private func buildTokens(for move: FightDataMove) -> [NotationToken] {
        buildTokensFromString(move.input ?? "", hitLevels: move.hitLevels)
    }

    private func buildTokensFromString(_ input: String, hitLevels: String? = nil) -> [NotationToken] {
        let gameData = moveListService.currentGameData
        return MoveNotationRenderer.renderSteps(
            InputParser.parse(input),
            hitLevels: hitLevels.map { HitLevel.parse($0) },
            controls: gameData?.controls ?? [:],
            controlAbbr: moveListService.controlAbbreviations,
            controlGroups: gameData?.controlGroups ?? [:],
            keyLabels: buttonKeyLabels
        )
    }

    private func recordAttempt() {
        for moveId in lastForestCompleted.prefix(3) {
            moveAttemptCounts[moveId, default: 0] += 1
        }
    }

    private func moveRank(_ move: ResolvedMove, isFavorite: Bool, hasInput: Bool) -> Int {
        var rank = 0

        if isFavorite { rank += 100 }

        let attempts = moveAttemptCounts[move.id] ?? 0
        rank += attempts * 10

        if move.totalSteps >= 4 {
            rank += 8
        }

        if let firstDir = move.parsedSteps.first?.first?.direction,
               let startingDir = FightDataDirection(rawValue: firstDir) {
            let dirAttempts = directionAttemptCounts[startingDir] ?? 0
            let totalDirAttempts = directionAttemptCounts.values.reduce(0, +)
            if totalDirAttempts > 0 {
                let dirRatio = Double(dirAttempts) / Double(totalDirAttempts)
                if dirRatio >= 0.3 {
                    rank += 6
                }
            }
        }

        if move.categoryLabel.contains("Super") { rank += 3 }
        if move.categoryLabel.contains("Special") { rank += 2 }
        if move.categoryLabel.contains("Command") { rank += 1 }
        if move.isCharge { rank += 1 }

        return rank
    }

    private func isCommonMoveId(_ moveId: String) -> Bool {
        guard let commonMoves = moveListService.currentGameData?.commonCommands else { return false }
        return commonMoves.contains(where: { $0.id == moveId })
    }
}
