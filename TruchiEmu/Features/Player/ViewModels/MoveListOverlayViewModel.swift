import Foundation
import Combine

@MainActor
class MoveListOverlayViewModel: ObservableObject {
    @Published private(set) var filteredMoves: [ResolvedMove] = []
    @Published private(set) var isOverlayVisible: Bool = false
    @Published private(set) var needsCharacterSelection: Bool = false
    @Published private(set) var hasGameData: Bool = false
    @Published private(set) var matchedMoveName: String? = nil
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
    }

    func confirmCharacter(_ character: FightDataCharacter) {
        moveListService.selectCharacter(character)
        pendingCharacter = nil
        needsCharacterSelection = false
        isOverlayVisible = true
        updateFilteredMoves(for: inputStateTracker.inputSequence)
    }

    func deactivate() {
        isOverlayVisible = false
        needsCharacterSelection = false
        pendingCharacter = nil
        inputStateTracker.clearSequence()
        filteredMoves = []
        inputDirections = []
        inputDirectionCharges = []
        inputButtons = []
        matchedMoveName = nil
        moveAttemptCounts.removeAll()
        directionAttemptCounts.removeAll()
    }

    func loadForGame(_ rom: ROM) {
        moveListService.loadGameData(for: rom)
        let systemID = rom.systemID ?? "default"
        inputStateTracker.systemID = systemID
        if let game = moveListService.currentGameData {
            inputStateTracker.arcadeLayout = ArcadeButtonMapper.shared.arcadeLayout(for: game)
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

    private func updateFilteredMoves(for sequence: [InputSequenceStep]) {
        guard let character = moveListService.selectedCharacter else {
            filteredMoves = []
            return
        }

        var directions: [FightDataDirection] = []
        var directionCharges: [Bool] = []
        var buttons: [Set<String>] = []
        for step in sequence {
            if !step.buttons.isEmpty {
                buttons.append(step.buttons)
            } else if let dir = step.direction {
                directions.append(dir)
                directionCharges.append(step.isCharge)
            }
        }
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
            allMoves.sort { moveRank($0, isFavorite: favoriteIds.contains($0.id), hasInput: false) > moveRank($1, isFavorite: favoriteIds.contains($1.id), hasInput: false) }
            filteredMoves = allMoves.map { move in
                ResolvedMove(
                    id: move.id, name: move.name, categoryLabel: move.categoryLabel,
                    notation: move.notation, inputDirections: move.inputDirections,
                    inputButtons: move.inputButtons, isAir: move.isAir, isCharge: move.isCharge,
                    isMotion360: move.isMotion360,
                    matchCount: 0, totalSteps: move.totalSteps,
                    matchedStepCount: 0
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

        filteredMoves = sorted.map { move in
            let mSteps = computeMoveMatchedSteps(move: move, directions: directions, buttons: buttons)
            return ResolvedMove(
                id: move.id, name: move.name, categoryLabel: move.categoryLabel,
                notation: move.notation, inputDirections: move.inputDirections,
                inputButtons: move.inputButtons, isAir: move.isAir, isCharge: move.isCharge,
                isMotion360: move.isMotion360,
                matchCount: move.matchCount, totalSteps: move.totalSteps,
                matchedStepCount: mSteps
            )
        }.prefix(maxMovesToShow).map { $0 }
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
        let catLabel = categoryLabels[move.category] ?? move.category
        let notation = renderNotation(for: move)

        return ResolvedMove(
            id: move.id, name: move.name, categoryLabel: catLabel,
            notation: notation, inputDirections: move.inputDirections,
            inputButtons: move.inputButtons, isAir: move.isAir, isCharge: move.isCharge,
            isMotion360: move.isMotion360,
            matchCount: 0, totalSteps: move.inputDirections.count + move.inputButtons.count,
            matchedStepCount: 0
        )
    }

    private func renderNotation(for move: FightDataMove) -> String {
        if let pi = move.parsedInput, !pi.directions.isEmpty || !pi.buttons.isEmpty {
            return renderFromParsedInput(pi)
        }
        return renderFromString(move.input ?? "")
    }

    private func renderFromParsedInput(_ pi: ParsedInput) -> String {
        let abbr = moveListService.controlAbbreviations
        let dirMap: [Int: String] = [1: "↙", 2: "↓", 3: "↘", 4: "←", 5: "●", 6: "→", 7: "↖", 8: "↑", 9: "↗"]
        var parts: [String] = []

        if pi.air { parts.append("↑") }

        if pi.charge, let cd = pi.chargeDirection, let arrow = dirMap[cd] {
            parts.append("⏳\(arrow)")
        } else if pi.charge {
            parts.append("⏳")
        }

        for dirStep in pi.directions {
            for d in dirStep {
                if let arrow = dirMap[d] { parts.append(arrow) }
            }
        }

        for btnStep in pi.buttons {
            let btnLabels = btnStep.map { key -> String in
                if let a = abbr[key] { return a }
                return key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: "")
            }
            if !btnLabels.isEmpty {
                let joined = btnLabels.joined(separator: "+")
                parts.append(pi.holdButton ? "⏳\(joined)" : joined)
            }
        }

        if pi.rapidPress, let last = parts.last {
            parts[parts.count - 1] = last + "⚡"
        }

        if pi.neutral {
            parts.append("●")
        }

        return parts.joined(separator: " ")
    }

    private func renderFromString(_ input: String) -> String {
        var result = input

        result = result.replacingOccurrences(of: "_O", with: "⏳")
        result = result.replacingOccurrences(of: "_^", with: "↑")

        for (key, abbr) in moveListService.controlAbbreviations.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: key, with: abbr)
        }
        for (key, label) in moveListService.controlLabels.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: key, with: label)
        }

        result = result.replacingOccurrences(of: "_1", with: "↙")
        result = result.replacingOccurrences(of: "_2", with: "↓")
        result = result.replacingOccurrences(of: "_3", with: "↘")
        result = result.replacingOccurrences(of: "_4", with: "←")
        result = result.replacingOccurrences(of: "_5", with: "●")
        result = result.replacingOccurrences(of: "_6", with: "→")
        result = result.replacingOccurrences(of: "_7", with: "↖")
        result = result.replacingOccurrences(of: "_8", with: "↑")
        result = result.replacingOccurrences(of: "_9", with: "↗")
        result = result.replacingOccurrences(of: "_+", with: "+")
        result = result.replacingOccurrences(of: "_", with: "")

        result = result.replacingOccurrences(of: "^1", with: "⏳↙")
        result = result.replacingOccurrences(of: "^2", with: "⏳↓")
        result = result.replacingOccurrences(of: "^3", with: "⏳↘")
        result = result.replacingOccurrences(of: "^4", with: "⏳←")
        result = result.replacingOccurrences(of: "^6", with: "⏳→")
        result = result.replacingOccurrences(of: "^7", with: "⏳↖")
        result = result.replacingOccurrences(of: "^8", with: "⏳↑")
        result = result.replacingOccurrences(of: "^9", with: "⏳↗")

        return result
    }

    private func renderNotation(input: String, controls: [String: String]) -> String {
        var result = input
        for (key, label) in controls.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: key, with: label)
        }

        result = result.replacingOccurrences(of: "_1", with: "↙")
        result = result.replacingOccurrences(of: "_2", with: "↓")
        result = result.replacingOccurrences(of: "_3", with: "↘")
        result = result.replacingOccurrences(of: "_4", with: "←")
        result = result.replacingOccurrences(of: "_5", with: "●")
        result = result.replacingOccurrences(of: "_6", with: "→")
        result = result.replacingOccurrences(of: "_7", with: "↖")
        result = result.replacingOccurrences(of: "_8", with: "↑")
        result = result.replacingOccurrences(of: "_9", with: "↗")
        result = result.replacingOccurrences(of: "_+", with: " + ")
        result = result.replacingOccurrences(of: "_", with: "")

        return result
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

        if let firstDir = move.inputDirections.first,
           let firstVal = firstDir.first,
           let startingDir = FightDataDirection(rawValue: firstVal) {
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
        guard !move.inputDirections.isEmpty else { return false }

        let moveDirInts = move.inputDirections
        var dirIndex = 0

        for userDir in directions {
            guard dirIndex < moveDirInts.count else { return true }
            let moveDirStep = moveDirInts[dirIndex]

            if moveDirStep.contains(userDir.rawValue) {
                dirIndex += 1
            } else if dirIndex == 0 {
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
