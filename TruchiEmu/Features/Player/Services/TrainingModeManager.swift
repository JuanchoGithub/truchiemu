import Foundation
import Combine

@MainActor
class TrainingModeManager: ObservableObject {
    static let shared = TrainingModeManager()

    @Published var config: TrainingModeConfig = TrainingModeConfig()
    @Published var isMenuVisible: Bool = false
    @Published var selectedTab: Int = 0

    let sequenceRunner = SequenceRunner()
    let tapeDeck = TapeDeck()
    lazy var inputManager: TrainingInputManager = TrainingInputManager(manager: self)
    let frameDriver = TrainingFramePollDriver()

    var tapeRunnerFrameIndex: Int = 0
    var lastP1InputState: [Int: Bool] = [:]
    @Published var currentGameData: FightDataGame? = nil
    var currentCharacterName: String? { MoveListService.shared.selectedCharacter?.name }
    var currentArcadeLayout: ArcadeLayout = .capcom6
    var currentSystemID: String = "" {
        didSet { frameDriver.systemID = currentSystemID }
    }

    var isArcadeSystem: Bool {
        TrainingFramePollDriver.arcadeSystemIDs.contains(currentSystemID.lowercased())
    }

    private var framePollCallback: (@convention(c) () -> Void)?
    private var xpcModeTimer: DispatchSourceTimer?

    func activate(for game: FightDataGame?, systemID: String, layout: ArcadeLayout) {
        currentGameData = game
        currentSystemID = systemID
        currentArcadeLayout = layout

        sequenceRunner.setExpansionContext(SequenceRunner.ExpansionContext(
            layout: layout,
            systemID: systemID,
            systemControlMappings: game?.systemControlMappings,
            frameProfile: config.frameProfile
        ))

        sequenceRunner.loadCards(config.sequenceCards)
        tapeRunnerFrameIndex = 0
        inputManager.rebuildRetroIDMap()
        syncFrameDriver()
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled && config.isEnabled {
            let callers = Thread.callStackSymbols.prefix(12)
            LoggerService.warning(category: "TrainingP2", "setEnabled(FALSE) called while training was ON! Stack:\n\(callers.joined(separator: "\n"))")
        }
        config.isEnabled = enabled
        if enabled {
            if config.controlMode == .standby {
                config.controlMode = .stanceGuard
                LoggerService.debug(category: "TrainingP2", "Auto-switched controlMode from standby to stanceGuard")
            }
            syncFrameDriver()
            installFramePollDriver()
            if !frameDriver.hasP2Joined {
                LoggerService.debug(category: "TrainingP2", "Training enabled — P2 not yet joined, starting P2 join sequence")
                triggerP2Join()
            }
        } else {
            removeFramePollDriver()
            frameDriver.clearP2Input()
            frameDriver.stopCountdown()
            frameDriver.resetP2JoinState()
            sequenceRunner.reset()
            tapeDeck.stopRecording()
            tapeDeck.stopCountdown()
        }
        persistConfig()
    }

    func toggleMenu() {
        isMenuVisible.toggle()
        if config.freezeOnMenu && isMenuVisible {
            XPCBridgeAdapter.shared.setPaused(true)
        } else if config.freezeOnMenu && !isMenuVisible {
            XPCBridgeAdapter.shared.setPaused(false)
        }
    }

    func updateConfig(_ update: (inout TrainingModeConfig) -> Void) {
        update(&config)
        sequenceRunner.setExpansionContext(SequenceRunner.ExpansionContext(
            layout: currentArcadeLayout,
            systemID: currentSystemID,
            systemControlMappings: currentGameData?.systemControlMappings,
            frameProfile: config.frameProfile
        ))
        if config.controlMode == .fmdSequence {
            sequenceRunner.loadCards(config.sequenceCards)
        }
        syncFrameDriver()
        persistConfig()
    }

    func triggerP2Join() {
        let wasEnabled = config.isEnabled
        LoggerService.debug(category: "TrainingP2", "triggerP2Join: isEnabled=\(wasEnabled), isArcade=\(isArcadeSystem), systemID=\(currentSystemID)")
        frameDriver.startP2Join()
        if !wasEnabled {
            frameDriver.onP2JoinComplete = { [weak self] in
                Task { @MainActor in
                    LoggerService.debug(category: "TrainingP2", "P2 join complete callback (training was not enabled) — removing frame poll")
                    self?.removeFramePollDriver()
                }
            }
            installFramePollDriver()
            LoggerService.debug(category: "TrainingP2", "Installed frame poll driver for P2 join only (training was not enabled)")
        } else {
            LoggerService.debug(category: "TrainingP2", "Training already enabled, frame poll already active — P2 join will run on existing timer")
        }
    }

    func performReset() {
        switch config.resetPosition {
        case .roundStart:
            XPCBridgeAdapter.shared.resetGame()
        case .leftCorner:
            if let stateData = config.leftCornerState {
                _ = XPCBridgeAdapter.shared.unserializeState(stateData)
            } else {
                XPCBridgeAdapter.shared.resetGame()
            }
        case .rightCorner:
            if let stateData = config.rightCornerState {
                _ = XPCBridgeAdapter.shared.unserializeState(stateData)
            } else {
                XPCBridgeAdapter.shared.resetGame()
            }
        case .custom:
            if let stateData = config.customResetState {
                _ = XPCBridgeAdapter.shared.unserializeState(stateData)
            } else {
                XPCBridgeAdapter.shared.resetGame()
            }
        }
        sequenceRunner.reset()
        tapeRunnerFrameIndex = 0
        syncFrameDriver()
    }

    func saveCustomResetPoint() {
        config.customResetState = XPCBridgeAdapter.shared.serializeState()
        persistConfig()
    }

    func saveCornerResetPoint(_ corner: TrainingResetPosition) {
        let stateData = XPCBridgeAdapter.shared.serializeState()
        switch corner {
        case .leftCorner: config.leftCornerState = stateData
        case .rightCorner: config.rightCornerState = stateData
        default: return
        }
        persistConfig()
    }

    func toggleRecording() {
        if tapeDeck.isRecording {
            tapeDeck.stopRecording()
        } else if tapeDeck.isCountingDown {
            tapeDeck.stopCountdown()
            frameDriver.stopCountdown()
        } else {
            tapeDeck.startRecording(slot: config.activeTapeSlot)
            frameDriver.startCountdown()
        }
    }

    func startTapePlayback() {
        let slot = config.activeTapeSlot
        guard tapeDeck.slots[slot] != nil else { return }
        tapeRunnerFrameIndex = 0
    }

    func syncFrameDriver() {
        let preExpandedCards = preExpandAllCards()
        frameDriver.syncFrom(
            config: config,
            cards: sequenceRunner.cards,
            preExpandedCards: preExpandedCards,
            currentIndex: sequenceRunner.currentIndex,
            currentFrameInCard: sequenceRunner.currentFrameInCard,
            isExecuting: sequenceRunner.isExecuting,
            triggerCondition: sequenceRunner.triggerCondition,
            autoInvert: sequenceRunner.autoInvert
        )
    }

    private func preExpandAllCards() -> [Int: [FrameInput]] {
        guard let ctx = sequenceRunner.expansionContext else { return [:] }
        var result: [Int: [FrameInput]] = [:]
        for (index, card) in sequenceRunner.cards.enumerated() {
            if card.cardType == .fmd, let parsedSteps = card.fmdParsedSteps, let firstAlt = parsedSteps.first {
                let expander = FrameExpander(
                    steps: firstAlt,
                    frameProfile: ctx.frameProfile,
                    layout: ctx.layout,
                    systemID: ctx.systemID,
                    systemControlMappings: ctx.systemControlMappings
                )
                result[index] = expander.expand()
            }
        }
        return result
    }

    private func installFramePollDriver() {
        if XPCBridgeAdapter.shared.isActive {
            installXPCTimer()
        } else {
            installInProcessCallback()
        }
    }

    private func removeFramePollDriver() {
        LoggerService.debug(category: "TrainingP2", "removeFramePollDriver called — xpcTimer=\(xpcModeTimer != nil), callback=\(framePollCallback != nil)")
        removeXPCTimer()
        removeInProcessCallback()
    }

    private func installInProcessCallback() {
        TrainingFramePollDriver.activeInstance = frameDriver
        let callback: @convention(c) () -> Void = {
            TrainingFramePollDriver.activeInstance?.tick()
        }
        framePollCallback = callback
        LibretroBridgeSwift.setFramePollCallback(callback)
        LoggerService.debug(category: "TrainingP2", "In-process frame poll callback installed")
    }

    private func removeInProcessCallback() {
        LibretroBridgeSwift.setFramePollCallback(nil)
        framePollCallback = nil
        if !XPCBridgeAdapter.shared.isActive {
            TrainingFramePollDriver.activeInstance = nil
        }
        LoggerService.debug(category: "TrainingP2", "In-process frame poll callback removed")
    }

    private func installXPCTimer() {
        guard xpcModeTimer == nil else { return }
        let queue = DispatchQueue(label: "truchiemu.trainingframepoll", qos: .userInteractive)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            self?.frameDriver.tick()
        }
        timer.resume()
        xpcModeTimer = timer
        TrainingFramePollDriver.activeInstance = frameDriver
        LoggerService.debug(category: "TrainingP2", "XPC timer-based frame poll installed (16ms interval)")
    }

    private func removeXPCTimer() {
        xpcModeTimer?.cancel()
        xpcModeTimer = nil
        if XPCBridgeAdapter.shared.isActive {
            TrainingFramePollDriver.activeInstance = nil
        }
        LoggerService.debug(category: "TrainingP2", "XPC timer-based frame poll removed")
    }

    private func clearAllP2Input() {
        for retroID in 0..<32 {
            XPCBridgeAdapter.shared.setKeyState(retroID: retroID, player: 1, pressed: false)
        }
    }

    private func persistConfig() {
        do {
            let data = try JSONEncoder().encode(config)
            AppSettings.setData("trainingModeConfig", value: data)
        } catch {
            LoggerService.debug(category: "TrainingMode", "Failed to persist config: \(error)")
        }
    }

    private func loadConfig() {
        guard let data = AppSettings.getData("trainingModeConfig") else { return }
        do {
            config = try JSONDecoder().decode(TrainingModeConfig.self, from: data)
        } catch {
            LoggerService.debug(category: "TrainingMode", "Failed to load config: \(error)")
        }
    }
}

final class TrainingFramePollDriver: @unchecked Sendable {
    private let lock = NSLock()

    static nonisolated(unsafe) var activeInstance: TrainingFramePollDriver?

    private var isEnabled: Bool = false
    private var controlMode: TrainingControlMode = .standby
    private var stance: TrainingStance = .stand
    private var guardMode: TrainingGuard = .noBlock
    nonisolated(unsafe) var systemID: String = ""
    private var cards: [SequenceCard] = []
    private var preExpandedCards: [Int: [FrameInput]] = [:]
    private var currentCardIndex: Int = 0
    private var currentFrameInCard: Int = 0
    private var isExecuting: Bool = false
    private var triggerCondition: TrainingSequenceTrigger = .continuousLoop
    private var autoInvert: Bool = true
    private var p2FacesRight: Bool = true
    private var expandedFrames: [FrameInput] = []
    private var delayRemaining: Int = 0
    private var jumpCooldown: Int = 0
    private var isCountingDown: Bool = false
    private var countdownRemaining: Int = 0
    private var p2JoinPhase: Int = 0
    private var p2JoinFrame: Int = 0
    private var p2JoinOnly: Bool = false
    private var p2JoinLoggedStart: Bool = false
    private var _hasP2Joined: Bool = false
    private var loggedStanceGuardTick: Bool = false
    private var tickCount: Int = 0
    var hasP2Joined: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _hasP2Joined
    }
    var onCountdownComplete: (() -> Void)?
    var onP2JoinComplete: (() -> Void)?

    static let arcadeSystemIDs: Set<String> = ["mame", "fba", "fbneo", "arcade", "mame078", "mame2010", "mame2016"]
    private static let coinHoldFrames = 10
    private static let startHoldFrames = 10
    private static let joinPauseFrames = 5
    private static let charSelectPauseFrames = 180
    private static let charSelectHoldFrames = 5
    private static let coin2RetroID: Int32 = 2
    private static let start2RetroID: Int32 = 3

    var isTapeCountingDown: Bool { isCountingDown }
    var tapeCountdownValue: Int { countdownRemaining }

    private var isArcadeSystem: Bool {
        Self.arcadeSystemIDs.contains(systemID.lowercased())
    }

    func syncFrom(
        config: TrainingModeConfig,
        cards: [SequenceCard],
        preExpandedCards: [Int: [FrameInput]],
        currentIndex: Int,
        currentFrameInCard: Int,
        isExecuting: Bool,
        triggerCondition: TrainingSequenceTrigger,
        autoInvert: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }
        let wasEnabled = isEnabled
        isEnabled = config.isEnabled
        controlMode = config.controlMode
        stance = config.stance
        guardMode = config.guard
        self.cards = cards
        self.preExpandedCards = preExpandedCards
        self.currentCardIndex = currentIndex
        self.currentFrameInCard = currentFrameInCard
        self.isExecuting = isExecuting
        self.triggerCondition = triggerCondition
        self.autoInvert = autoInvert
        if !wasEnabled && isEnabled && isArcadeSystem && !_hasP2Joined {
            p2JoinPhase = 1
            p2JoinFrame = 0
        }
        prepareCurrentCardLocked()
    }

    func tick() {
        lock.lock()
        tickCount += 1
        if tickCount % 60 == 1 {
            LoggerService.debug(category: "TrainingP2", "tick() heartbeat #\(tickCount): isEnabled=\(isEnabled) controlMode=\(controlMode.rawValue) p2JoinPhase=\(p2JoinPhase) hasP2Joined=\(_hasP2Joined) stance=\(stance.rawValue) guard=\(guardMode.rawValue)")
        }

        if isCountingDown {
            countdownRemaining -= 1
            if countdownRemaining <= 0 {
                isCountingDown = false
                lock.unlock()
                onCountdownComplete?()
                return
            }
            lock.unlock()
            return
        }

        if p2JoinPhase > 0 {
            if !p2JoinLoggedStart {
                p2JoinLoggedStart = true
                LoggerService.debug(category: "TrainingP2", "tick() — P2 join active, phase=\(p2JoinPhase), frame=\(p2JoinFrame), isArcade=\(isArcadeSystem)")
            }
            tickP2JoinLocked()
            return
        }

        guard isEnabled, controlMode != .human, controlMode != .standby else {
            let reason = !isEnabled ? "disabled" : (controlMode == .human ? "human" : (controlMode == .standby ? "standby" : "unknown"))
            LoggerService.extreme(category: "TrainingP2", "tick() guard failed: \(reason)")
            lock.unlock()
            return
        }

        let adapter = XPCBridgeAdapter.shared

        switch controlMode {
        case .fmdSequence:
            tickSequenceLocked(adapter: adapter)
        case .stanceGuard:
            let cfgStance = stance
            let cfgGuard = guardMode
            let cfgSysID = systemID
            if !loggedStanceGuardTick {
                loggedStanceGuardTick = true
                LoggerService.debug(category: "TrainingP2", "stanceGuard tick FIRST: stance=\(cfgStance.rawValue) guard=\(cfgGuard.rawValue) sysID=\(cfgSysID) isEnabled=\(isEnabled)")
            }
            jumpCooldown -= (jumpCooldown > 0 ? 1 : 0)
            let currentCooldown = jumpCooldown
            lock.unlock()

            clearP2Input(adapter)

            if cfgStance != .stand || cfgGuard != .noBlock {
                LoggerService.extreme(category: "TrainingP2", "stanceGuard tick: stance=\(cfgStance.rawValue) guard=\(cfgGuard.rawValue) sysID=\(cfgSysID)")
            }

            switch cfgStance {
            case .stand: break
            case .crouch:
                pressP2(.down, systemID: cfgSysID, adapter: adapter)
            case .jump:
                if currentCooldown <= 0 {
                    pressP2(.up, systemID: cfgSysID, adapter: adapter)
                    lock.lock()
                    jumpCooldown = 4
                    lock.unlock()
                }
            }

            switch cfgGuard {
            case .noBlock: break
            case .allBlock:
                if cfgStance == .crouch {
                    pressP2(.down, systemID: cfgSysID, adapter: adapter)
                    pressP2(.left, systemID: cfgSysID, adapter: adapter)
                } else {
                    pressP2(.left, systemID: cfgSysID, adapter: adapter)
                }
            case .randomBlock:
                if Bool.random() {
                    pressP2(.left, systemID: cfgSysID, adapter: adapter)
                }
            case .firstHitBlock:
                pressP2(.left, systemID: cfgSysID, adapter: adapter)
            }
        case .standby, .human:
            break
        }
    }

    private func tickSequenceLocked(adapter: XPCBridgeAdapter) {
        clearP2Input(adapter)

        guard isExecuting, currentCardIndex < cards.count else {
            lock.unlock()
            return
        }

        let card = cards[currentCardIndex]
        switch card.cardType {
        case .fmd:
            tickFMDLocked(adapter: adapter)
        case .delay:
            tickDelayLocked(adapter: adapter)
        case .tape:
            lock.unlock()
        }
    }

    private func tickFMDLocked(adapter: XPCBridgeAdapter) {
        guard currentFrameInCard < expandedFrames.count else {
            advanceCardLocked(adapter: adapter)
            lock.unlock()
            return
        }

        let frame = expandedFrames[currentFrameInCard]
        let invert = autoInvert && !p2FacesRight
        let sysID = systemID

        for button in frame.allPressed {
            let mapped: RetroButton
            if invert {
                switch button {
                case .left: mapped = .right
                case .right: mapped = .left
                default: mapped = button
                }
            } else {
                mapped = button
            }
            let retroID = Int(mapped.retroID(for: sysID))
            if retroID >= 0 {
                adapter.setKeyState(retroID: retroID, player: 1, pressed: true)
            }
        }

        currentFrameInCard += 1

        if currentFrameInCard >= expandedFrames.count {
            advanceCardLocked(adapter: adapter)
        }

        lock.unlock()
    }

    private func tickDelayLocked(adapter: XPCBridgeAdapter) {
        guard delayRemaining > 0 else {
            advanceCardLocked(adapter: adapter)
            lock.unlock()
            return
        }

        delayRemaining -= 1
        if delayRemaining <= 0 {
            advanceCardLocked(adapter: adapter)
        }

        lock.unlock()
    }

    private func advanceCardLocked(adapter: XPCBridgeAdapter) {
        currentCardIndex += 1
        currentFrameInCard = 0
        expandedFrames = []
        delayRemaining = 0

        if currentCardIndex >= cards.count {
            if triggerCondition == .continuousLoop {
                currentCardIndex = 0
                prepareCurrentCardLocked()
            } else {
                isExecuting = false
                clearP2Input(adapter)
            }
        } else {
            prepareCurrentCardLocked()
        }
    }

    private func prepareCurrentCardLocked() {
        guard currentCardIndex < cards.count else { return }
        let card = cards[currentCardIndex]

        switch card.cardType {
        case .fmd:
            expandedFrames = preExpandedCards[currentCardIndex] ?? []
        case .delay:
            delayRemaining = card.delayFrames
        case .tape:
            break
        }
    }

    private func pressP2(_ button: RetroButton, systemID: String, adapter: XPCBridgeAdapter) {
        let retroID = Int(button.retroID(for: systemID))
        guard retroID >= 0 else { return }
        adapter.setKeyState(retroID: retroID, player: 1, pressed: true)
    }

    func clearP2Input() {
        let adapter = XPCBridgeAdapter.shared
        clearP2Input(adapter)
    }

    func resetP2JoinState() {
        lock.lock()
        _hasP2Joined = false
        p2JoinPhase = 0
        p2JoinFrame = 0
        p2JoinOnly = false
        p2JoinLoggedStart = false
        lock.unlock()
    }

    func startCountdown() {
        lock.lock()
        isCountingDown = true
        countdownRemaining = TapeDeck.countdownFrames
        lock.unlock()
    }

    func stopCountdown() {
        lock.lock()
        isCountingDown = false
        countdownRemaining = 0
        lock.unlock()
    }

    func startP2Join() {
        lock.lock()
        if p2JoinPhase == 0 {
            p2JoinPhase = 1
            p2JoinFrame = 0
            p2JoinOnly = !isEnabled
            LoggerService.debug(category: "TrainingP2", "startP2Join: phase=1, isArcade=\(isArcadeSystem), p2JoinOnly=\(p2JoinOnly), isEnabled=\(isEnabled)")
        } else {
            LoggerService.debug(category: "TrainingP2", "startP2Join: SKIPPED — p2JoinPhase already \(p2JoinPhase)")
        }
        lock.unlock()
    }

    private func finishP2JoinLocked() {
        let wasJoinOnly = p2JoinOnly
        _hasP2Joined = true
        p2JoinPhase = 0
        p2JoinFrame = 0
        p2JoinOnly = false
        p2JoinLoggedStart = false
        loggedStanceGuardTick = false
        LoggerService.debug(category: "TrainingP2", "P2 join sequence COMPLETE, hasP2Joined=true, wasJoinOnly=\(wasJoinOnly), controlMode=\(controlMode.rawValue), isEnabled=\(isEnabled)")
        lock.unlock()
        if wasJoinOnly {
            onP2JoinComplete?()
        }
    }

    private func tickP2JoinLocked() {
        let adapter = XPCBridgeAdapter.shared
        p2JoinFrame += 1

        if !isArcadeSystem {
            switch p2JoinPhase {
            case 1:
                adapter.setKeyState(retroID: 3, player: 1, pressed: true)
                if p2JoinFrame >= Self.startHoldFrames {
                    adapter.setKeyState(retroID: 3, player: 1, pressed: false)
                    LoggerService.debug(category: "TrainingP2", "Non-arcade: phase 1→2 (Start held \(p2JoinFrame) frames)")
                    p2JoinPhase = 2
                    p2JoinFrame = 0
                }
            case 2:
                if p2JoinFrame >= Self.charSelectPauseFrames {
                    LoggerService.debug(category: "TrainingP2", "Non-arcade: phase 2→3 (char select pause done)")
                    p2JoinPhase = 3
                    p2JoinFrame = 0
                }
            case 3:
                adapter.setKeyState(retroID: 0, player: 1, pressed: true)
                if p2JoinFrame >= Self.charSelectHoldFrames {
                    adapter.setKeyState(retroID: 0, player: 1, pressed: false)
                    LoggerService.debug(category: "TrainingP2", "Non-arcade: phase 3 COMPLETE (A press to pick char)")
                    p2JoinLoggedStart = false
                    finishP2JoinLocked()
                    return
                }
            default:
                p2JoinPhase = 0
            }
            lock.unlock()
            return
        }

        switch p2JoinPhase {
        case 1:
            adapter.setKeyState(retroID: Int(Self.coin2RetroID), player: 1, pressed: true)
            if p2JoinFrame >= Self.coinHoldFrames {
                p2JoinPhase = 2
                p2JoinFrame = 0
                LoggerService.debug(category: "TrainingP2", "Arcade: phase 1→2 (Coin held \(p2JoinFrame) frames)")
            }
        case 2:
            adapter.setKeyState(retroID: Int(Self.coin2RetroID), player: 1, pressed: false)
            if p2JoinFrame >= Self.joinPauseFrames {
                p2JoinPhase = 3
                p2JoinFrame = 0
                LoggerService.debug(category: "TrainingP2", "Arcade: phase 2→3 (Coin release pause)")
            }
        case 3:
            adapter.setKeyState(retroID: Int(Self.start2RetroID), player: 1, pressed: true)
            if p2JoinFrame >= Self.startHoldFrames {
                adapter.setKeyState(retroID: Int(Self.start2RetroID), player: 1, pressed: false)
                p2JoinPhase = 4
                p2JoinFrame = 0
                LoggerService.debug(category: "TrainingP2", "Arcade: phase 3→4 (Start held \(p2JoinFrame) frames)")
            }
        case 4:
            if p2JoinFrame >= Self.charSelectPauseFrames {
                p2JoinPhase = 5
                p2JoinFrame = 0
                LoggerService.debug(category: "TrainingP2", "Arcade: phase 4→5 (char select pause done)")
            }
        case 5:
            adapter.setKeyState(retroID: 0, player: 1, pressed: true)
            if p2JoinFrame >= Self.charSelectHoldFrames {
                adapter.setKeyState(retroID: 0, player: 1, pressed: false)
                LoggerService.debug(category: "TrainingP2", "Arcade: phase 5 COMPLETE (A press to pick char)")
                p2JoinLoggedStart = false
                finishP2JoinLocked()
                return
            }
        default:
            p2JoinPhase = 0
        }

        lock.unlock()
    }

    private func clearP2Input(_ adapter: XPCBridgeAdapter) {
        for retroID in 0..<32 {
            adapter.setKeyState(retroID: retroID, player: 1, pressed: false)
        }
    }
}
