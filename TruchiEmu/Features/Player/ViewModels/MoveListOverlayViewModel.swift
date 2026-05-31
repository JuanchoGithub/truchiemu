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

    let moveListService: MoveListService
    let inputStateTracker: InputStateTracker

    private var cancellables = Set<AnyCancellable>()
    private var moveAttemptCounts: [String: Int] = [:]
    private var directionAttemptCounts: [FightDataDirection: Int] = [:]
    private var lastSequenceLength: Int = 0
    private let storageService = MoveListStorageService.shared

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
        pendingCharacter = moveListService.selectedCharacter
        needsCharacterSelection = true
        isOverlayVisible = false
    }

    func selectPendingCharacter(_ character: FightDataCharacter) {
        pendingCharacter = character
    }

    func confirmPendingCharacter() {
        guard let character = pendingCharacter else { return }
        moveListService.selectCharacter(character)
        pendingCharacter = nil
        needsCharacterSelection = false
        isOverlayVisible = true
        updateFilteredMoves(for: inputStateTracker.inputSequence)
        NotationTokenImageCache.shared.prepareCache(moves: filteredMoves)
    }

    func confirmCharacter(_ character: FightDataCharacter) {
        moveListService.selectCharacter(character)
        pendingCharacter = nil
        needsCharacterSelection = false
        isOverlayVisible = true
        updateFilteredMoves(for: inputStateTracker.inputSequence)
        NotationTokenImageCache.shared.prepareCache(moves: filteredMoves)
    }

    func deactivate() {
        isOverlayVisible = false
        needsCharacterSelection = false
        pendingCharacter = nil
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
        updateFilteredMoves(for: inputStateTracker.inputSequence)
    }

    func selectCharacter(_ character: FightDataCharacter) {
        moveListService.selectCharacter(character)
    }

    func toggleFavorite(moveId: String) {
        guard let gameName = gameName, let charName = selectedCharacterName else { return }
        storageService.toggleFavorite(gameName: gameName, characterName: charName, moveId: moveId)
        updateFilteredMoves(for: inputStateTracker.inputSequence)
    }

    func toggleHidden(moveId: String) {
        guard let gameName = gameName, let charName = selectedCharacterName else { return }
        storageService.toggleHidden(gameName: gameName, characterName: charName, moveId: moveId)
        updateFilteredMoves(for: inputStateTracker.inputSequence)
    }

    func isFavorite(moveId: String) -> Bool {
        guard let gameName = gameName, let charName = selectedCharacterName else { return false }
        return storageService.isFavorite(gameName: gameName, characterName: charName, moveId: moveId)
    }

    func resolveButtonTokenType(for fightDataKey: String) -> ButtonTokenType {
        let controlGroups = moveListService.currentGameData?.controlGroups ?? [:]
        let isPunch = controlGroups["_P"]?.contains(fightDataKey) == true
        let isKick = controlGroups["_K"]?.contains(fightDataKey) == true

        if isPunch {
            let strength = resolveButtonStrength(fightDataKey, inGroup: controlGroups["_P"])
            return .punch(strength: strength)
        }
        if isKick {
            let strength = resolveButtonStrength(fightDataKey, inGroup: controlGroups["_K"])
            return .kick(strength: strength)
        }

        let controls = moveListService.currentGameData?.controls ?? [:]
        let label = (controls[fightDataKey] ?? "").lowercased()
        if label.contains("throw") || label.contains("grapple") {
            return .grapple
        }
        if label.contains("weapon") || label.contains("sword") {
            return .weapon(style: .sword)
        }
        if label.contains("axe") {
            return .weapon(style: .axe)
        }

        let abbr = moveListService.controlAbbreviations[fightDataKey] ?? fightDataKey
        if label.contains("punch") || label.contains("p") {
            return .punch(strength: .low)
        }
        if label.contains("kick") || label.contains("k") {
            return .kick(strength: .low)
        }

        return .generic(label: abbr.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: ""))
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

        var steps: [InputDisplayStep] = []
        var directions: [FightDataDirection] = []
        var directionCharges: [Bool] = []
        var buttons: [Set<String>] = []
        for step in sequence {
            if let dir = step.direction {
                steps.append(.direction(dir, isCharge: step.isCharge))
                directions.append(dir)
                directionCharges.append(step.isCharge)
            }
            if !step.buttons.isEmpty {
                steps.append(.buttons(step.buttons))
                buttons.append(step.buttons)
            }
        }
        inputSteps = steps
        inputDirections = directions
        inputDirectionCharges = directionCharges
        inputButtons = buttons

        if lastSequenceLength >= 2 && sequence.isEmpty {
            recordAttempt(directions: directions, buttons: buttons, character: character)
        }
        lastSequenceLength = sequence.count

        for dir in directions {
            directionAttemptCounts[dir, default: 0] += 1
        }

        var allMoves = collectAllMoves(for: character)
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

        let matching = allMoves.filter { move in
            return matchesInputSequence(move: move, directions: directions, buttons: buttons)
        }

        let nearComplete = allMoves.filter { move in
            guard move.totalSteps >= 5 else { return false }
            let matched = computeMoveMatchedSteps(move: move, directions: directions, buttons: buttons)
            let ratio = Double(matched) / Double(move.totalSteps)
            return ratio >= 0.5 && !matching.contains(where: { $0.id == move.id })
        }

        let combined = matching + nearComplete
        let sorted = combined.sorted { moveRank($0, isFavorite: favoriteIds.contains($0.id), hasInput: true) > moveRank($1, isFavorite: favoriteIds.contains($1.id), hasInput: true) }

        if let exact = sorted.first, isExactMatch(move: exact, directions: directions, buttons: buttons) {
            matchedMoveName = exact.name
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

        let moveById = Dictionary(uniqueKeysWithValues: topCandidates.map { ($0.id, $0) })

        filteredMoves = moveSlotOrder.compactMap { id -> ResolvedMove? in
            guard let move = moveById[id] else { return nil }
            let mSteps = computeMoveMatchedSteps(move: move, directions: directions, buttons: buttons)
            return ResolvedMove(
                id: move.id, name: move.name, categoryLabel: move.categoryLabel,
                notation: move.notation, tokens: move.tokens,
                hitLevels: move.hitLevels, condition: move.condition,
                parsedSteps: move.parsedSteps, isAir: move.isAir, isCharge: move.isCharge,
                isMotion360: move.isMotion360,
                matchCount: move.matchCount, totalSteps: move.totalSteps,
                matchedStepCount: mSteps
            )
        }
    }

    private func computeMoveMatchedSteps(move: ResolvedMove, directions: [FightDataDirection], buttons: [Set<String>]) -> Int {
        let moveDirectionsFlat = move.inputDirections.flatMap { $0 }
        var dirIndex = 0
        var matchedDirs = 0

        for userDir in directions {
            guard dirIndex < moveDirectionsFlat.count else { break }
            if moveDirectionsFlat[dirIndex] == userDir.rawValue {
                matchedDirs += 1
                dirIndex += 1
            }
        }

        let moveButtonsFlat = move.inputButtons
        var btnIndex = 0
        var matchedBtns = 0

        for userBtns in buttons {
            guard btnIndex < moveButtonsFlat.count else { break }
            let moveBtnStep = moveButtonsFlat[btnIndex]
            if buttonSetsMatch(userBtns: userBtns, moveBtns: moveBtnStep) {
                matchedBtns += 1
                btnIndex += 1
            }
        }

        return matchedDirs + matchedBtns
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

        for move in character.moves where move.hasInputData {
            if hiddenMoveIds.contains(move.id) { continue }
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
            for move in commonMoves where move.hasInputData {
                if hiddenMoveIds.contains(move.id) { continue }
                if storageService.getOverride(gameName: gameName, characterName: character.name, moveId: move.id) != nil { continue }
                let resolved = resolveMove(move, categoryLabels: categoryLabels)
                moves.append(resolved)
            }
        }

        let customEntries = storageService.getCustomMoves(gameName: gameName, characterName: character.name)
        for entry in customEntries {
            guard let data = entry.customMoveJSON?.data(using: .utf8),
                  let move = try? JSONDecoder().decode(FightDataMove.self, from: data) else { continue }
            let resolved = resolveMove(move, categoryLabels: categoryLabels)
            moves.append(resolved)
        }

        return moves
    }

    private func resolveMove(_ move: FightDataMove, categoryLabels: [String: String]) -> ResolvedMove {
        let catLabel = moveListService.resolveCategoryLabel(move.category)
        let parsedSteps = InputParser.parse(move.input ?? "")
        let tokens = buildTokens(for: move)
        let notation = move.input?.replacingOccurrences(of: "_", with: "") ?? ""
        let hl = move.hitLevels.map { HitLevel.parse($0) } ?? []

        let isAir = parsedSteps.first?.first?.direction == 8 && parsedSteps.first?.first?.buttons.isEmpty == true
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
        let dirs = steps.compactMap { $0.direction }
        return dirs.contains { ![5].contains($0) } && dirs.count >= 7
    }

    private func buildTokens(for move: FightDataMove) -> [NotationToken] {
        buildTokensFromString(move.input ?? "", hitLevels: move.hitLevels)
    }

    private func buildTokensFromString(_ input: String, hitLevels: String? = nil) -> [NotationToken] {
        if input.isEmpty { return [] }

        var tokens: [NotationToken] = []
        let parsedSequences = InputParser.parse(input)
        let hitLevelList = hitLevels.map { HitLevel.parse($0) } ?? []

        for (seqIndex, sequence) in parsedSequences.enumerated() {
            if seqIndex > 0 {
                tokens.append(.alternative)
            }

            for (stepIndex, step) in sequence.enumerated() {
                if step.isCharge, let dirVal = step.direction, let dir = FightDataDirection(rawValue: dirVal) {
                    tokens.append(.charge(dir))
                } else if step.direction == 8 && step.buttons.isEmpty && tokens.isEmpty {
                    tokens.append(.air)
                } else if let dirVal = step.direction, let dir = FightDataDirection(rawValue: dirVal) {
                    if step.direction != 8 || !tokens.isEmpty {
                        tokens.append(.direction(dir))
                    }
                }

                if !step.buttons.isEmpty {
                    for (i, key) in step.buttons.enumerated() {
                        if i > 0 { tokens.append(.separator) }
                        tokens.append(mapButtonToToken(key))
                    }
                }

                if step.isHold {
                    tokens.append(.holdButton)
                }

                if seqIndex == 0, stepIndex < hitLevelList.count, hitLevelList[stepIndex] != .none {
                    tokens.append(.hitLevel(hitLevelList[stepIndex]))
                }
            }
        }

        return tokens
    }

    private func mapButtonToToken(_ key: String) -> NotationToken {
        let controlGroups = moveListService.currentGameData?.controlGroups ?? [:]
        let controls = moveListService.currentGameData?.controls ?? [:]
        let abbr = moveListService.controlAbbreviations
        let label = controls[key] ?? abbr[key] ?? key

        let isPunchGroupKey = controlGroups["_P"]?.contains(key) == true
        let isKickGroupKey = controlGroups["_K"]?.contains(key) == true

        if isPunchGroupKey {
            let strength = resolveButtonStrength(key, inGroup: controlGroups["_P"])
            return .button(.punch(strength: strength))
        }
        if isKickGroupKey {
            let strength = resolveButtonStrength(key, inGroup: controlGroups["_K"])
            return .button(.kick(strength: strength))
        }

        let lower = label.lowercased()
        if lower.contains("throw") || lower.contains("grapple") {
            return .button(.grapple)
        }
        if lower.contains("weapon") || lower.contains("sword") {
            return .button(.weapon(style: .sword))
        }
        if lower.contains("axe") {
            return .button(.weapon(style: .axe))
        }

        let abbrLabel = abbr[key] ?? key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: "")
        if lower.contains("punch") || lower.contains("p") {
            return .button(.punch(strength: .low))
        }
        if lower.contains("kick") || lower.contains("k") {
            return .button(.kick(strength: .low))
        }

        return .button(.generic(label: abbrLabel))
    }

    private func resolveButtonStrength(_ key: String, inGroup group: [String]?) -> ButtonStrength {
        guard let group, let index = group.firstIndex(of: key) else { return .low }
        switch index {
        case 0: return .low
        case 1: return .medium
        case 2: return .high
        default: return .low
        }
    }

    private func recordAttempt(directions: [FightDataDirection], buttons: [Set<String>], character: FightDataCharacter) {
        let allMoves = collectAllMoves(for: character)
        let bestMatches = allMoves.filter { move in
            return matchesInputSequence(move: move, directions: directions, buttons: buttons)
        }
        for move in bestMatches.prefix(3) {
            moveAttemptCounts[move.id, default: 0] += 1
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

    private func matchesInputSequence(move: ResolvedMove, directions: [FightDataDirection], buttons: [Set<String>]) -> Bool {
        guard let firstSequence = move.parsedSteps.first, !firstSequence.isEmpty else { return false }

        let moveDirInts = move.inputDirections
        var dirIndex = 0

        for userDir in directions {
            guard dirIndex < moveDirInts.count else { return true }
            let moveDirStep = moveDirInts[dirIndex]

            if moveDirStep.contains(userDir.rawValue) {
                dirIndex += 1
            } else if isOppositeDirection(userDir, from: moveDirStep) {
                return false
            }
        }

        if !buttons.isEmpty {
            let moveButtons = move.inputButtons
            var btnIndex = 0

            for userBtns in buttons {
                guard btnIndex < moveButtons.count else { return true }
                let moveBtnStep = moveButtons[btnIndex]

                if buttonSetsMatch(userBtns: userBtns, moveBtns: moveBtnStep) {
                    btnIndex += 1
                }
            }
        }

        return true
    }

    private func isOppositeDirection(_ userDir: FightDataDirection, from expectedStep: [Int]) -> Bool {
        expectedStep.contains { expectedVal in
            guard let expected = FightDataDirection(rawValue: expectedVal) else { return false }
            switch (userDir, expected) {
            case (.up, .down), (.down, .up),
                (.left, .right), (.right, .left),
                (.upLeft, .downRight), (.downRight, .upLeft),
                (.upRight, .downLeft), (.downLeft, .upRight):
                return true
            default:
                return false
            }
        }
    }

    private func isExactMatch(move: ResolvedMove, directions: [FightDataDirection], buttons: [Set<String>]) -> Bool {
        let moveDirInts = move.inputDirections
        var dirIndex = 0

        for userDir in directions {
            guard dirIndex < moveDirInts.count else { return false }
            let moveDirStep = moveDirInts[dirIndex]
            if moveDirStep.contains(userDir.rawValue) {
                dirIndex += 1
            } else {
                return false
            }
        }

        if dirIndex < moveDirInts.count && !moveDirInts[dirIndex].isEmpty {
            return false
        }

        let moveButtons = move.inputButtons
        if !buttons.isEmpty {
            var btnIndex = 0
            for userBtns in buttons {
                guard btnIndex < moveButtons.count else { return false }
                let moveBtnStep = moveButtons[btnIndex]
                if buttonSetsMatch(userBtns: userBtns, moveBtns: moveBtnStep) {
                    btnIndex += 1
                } else {
                    return false
                }
            }
            if btnIndex < moveButtons.count {
                return false
            }
        } else if !moveButtons.isEmpty {
            return false
        }

        return true
    }

    private func buttonSetsMatch(userBtns: Set<String>, moveBtns: [String]) -> Bool {
        let controlGroups = moveListService.currentGameData?.controlGroups ?? [:]
        let userNormalized = Set(userBtns.map { normalizeFightDataKey($0) })

        for moveKey in moveBtns {
            let moveNorm = normalizeFightDataKey(moveKey)
            if userNormalized.contains(moveNorm) {
                return true
            }
            if let members = controlGroups[moveKey] {
                let memberNorms = Set(members.map { normalizeFightDataKey($0) })
                if !userNormalized.isDisjoint(with: memberNorms) {
                    return true
                }
            }
        }

        return false
    }

    private func normalizeFightDataKey(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: "^", with: "")
    }
}
