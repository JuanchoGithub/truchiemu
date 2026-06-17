import Foundation
import Combine

@MainActor
class InputStateTracker: ObservableObject {
    @Published private(set) var inputSequence: [InputSequenceStep] = []
    @Published private(set) var activeButtons: Set<RetroButton> = []
    @Published private(set) var lastDirection: FightDataDirection? = nil

    private var previousInputState: [Int: Bool] = [:]
    private var previousDirection: FightDataDirection? = nil
    private var timeoutTask: Task<Void, Never>? = nil
    private var cancellable: AnyCancellable? = nil
    private var directionHasGoneNeutral = false
    private var directionHoldStart: Date? = nil
    private var chargeCheckTask: Task<Void, Never>? = nil
    private var lastDirectionStepTime: Date? = nil
    private var residualDirectionTimer: Task<Void, Never>? = nil
    private var pendingResidualDirection: FightDataDirection? = nil
    private var chargeGeneration: UInt = 0
    private(set) var rawDirectionHistory: [FightDataDirection] = []
    @Published private(set) var detectedMotions: [DetectedMotion] = []

    private var inputTimeout: TimeInterval { AppSettings.getDouble("moveListInputTimeout", defaultValue: 1.0) }
    private var chargeThreshold: TimeInterval { AppSettings.getDouble("moveListChargeThreshold", defaultValue: 0.8) }
    private var diagonalMergeWindow: TimeInterval { AppSettings.getDouble("moveListDiagonalMerge", defaultValue: 0.083) }
    private var residualDirectionDelay: TimeInterval { AppSettings.getDouble("moveListResidualDelay", defaultValue: 0.25) }
    private let maxSequenceLength = 10

    var arcadeLayout: ArcadeLayout = .capcom6
    var systemID: String = "snes" {
        didSet { rebuildRetroIDToButton() }
    }
    var systemControlMappings: [String: [String: String]]? = nil

    private var retroIDToButton: [Int: RetroButton] = [:]

    private func rebuildRetroIDToButton() {
        var map: [Int: RetroButton] = [:]
        for button in RetroButton.allCases {
            let id = button.retroID(for: systemID)
            if id >= 0 { map[Int(id)] = button }
        }
        retroIDToButton = map
    }

    init(runner: EmulatorRunner) {
        cancellable = runner.$currentInputState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.processInputState(newState)
            }
    }

    private func processInputState(_ newState: [Int: Bool]) {
        var pressedButtons = Set<RetroButton>()
        var newlyPressed = Set<RetroButton>()
        var newlyReleased = Set<RetroButton>()

        for (retroID, pressed) in newState {
            let wasPressed = previousInputState[retroID] ?? false
            if pressed, let button = retroIDToButton[retroID] {
                pressedButtons.insert(button)
                if !wasPressed {
                    newlyPressed.insert(button)
                }
            } else if !pressed, wasPressed, let button = retroIDToButton[retroID] {
                newlyReleased.insert(button)
            }
        }

        activeButtons = pressedButtons
        previousInputState = newState

        let currentDirection = FightDataDirection.fromRetroButtons(held: pressedButtons)
        let hasNewDirectional = newlyPressed.contains(where: { $0.isDirectional })
        let hasDirectionalRelease = newlyReleased.contains(where: { $0.isDirectional })
        let onlyDirectionalRelease = !hasNewDirectional && hasDirectionalRelease

        let isDiagonalDecomposition = onlyDirectionalRelease
            && previousDirection != nil
            && currentDirection != nil
            && currentDirection != previousDirection
            && currentDirection!.isSubdirection(of: previousDirection!)

        if currentDirection == nil, !inputSequence.isEmpty {
            directionHasGoneNeutral = true
            directionHoldStart = nil
            chargeGeneration &+= 1
            chargeCheckTask?.cancel()
            chargeCheckTask = nil
            residualDirectionTimer?.cancel()
            residualDirectionTimer = nil
            pendingResidualDirection = nil
        }
        lastDirection = currentDirection
        previousDirection = currentDirection

        var stepButtons = Set<String>()
        for button in newlyPressed {
            if !button.isDirectional, !button.isTurbo, button != .start, button != .select {
                if let fdKey = ArcadeButtonMapper.shared.fightDataKey(for: button, layout: arcadeLayout, systemID: systemID, systemControlMappings: systemControlMappings) {
                    stepButtons.insert(fdKey)
                }
            }
        }

    if isDiagonalDecomposition, let residual = currentDirection {
        appendRawDirection(residual)
        pendingResidualDirection = residual
        residualDirectionTimer?.cancel()
        let delay = residualDirectionDelay
        residualDirectionTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.commitResidualDirection()
        }
        updateDetectedMotions()
        return
    }

        if hasNewDirectional {
            residualDirectionTimer?.cancel()
            residualDirectionTimer = nil
            pendingResidualDirection = nil
        }

        let lastStep = inputSequence.last
        let lastStepDir = lastStep?.direction
        let isDirectionRepress = currentDirection != nil && lastStepDir == currentDirection && directionHasGoneNeutral && hasNewDirectional
        let hasDirectionChange = currentDirection != nil && lastStepDir != currentDirection && hasNewDirectional
        let hasButtonPress = !stepButtons.isEmpty

        let withinMergeWindow: Bool = {
            guard let stepTime = lastDirectionStepTime else { return false }
            return Date().timeIntervalSince(stepTime) < diagonalMergeWindow
        }()
        let isDiagonalMerge = hasDirectionChange
            && lastStep != nil
            && lastStep!.buttons.isEmpty
            && lastStepDir != nil
            && currentDirection != nil
            && lastStepDir!.isSubdirection(of: currentDirection!)
            && withinMergeWindow

        if isDiagonalMerge, let dir = currentDirection, !inputSequence.isEmpty {
            inputSequence[inputSequence.count - 1] = InputSequenceStep(direction: dir, buttons: stepButtons)
            if hasButtonPress { lastDirectionStepTime = Date() }
        } else if hasDirectionChange || isDirectionRepress {
            if hasButtonPress {
                if let dir = currentDirection {
                    inputSequence.append(InputSequenceStep(direction: dir, buttons: stepButtons))
                    lastDirectionStepTime = Date()
                }
            } else if let dir = currentDirection {
                inputSequence.append(InputSequenceStep(direction: dir, buttons: []))
                lastDirectionStepTime = Date()
                directionHasGoneNeutral = false
            }
        } else if hasButtonPress {
            if let last = inputSequence.last, last.buttons.isEmpty, last.direction == currentDirection, !inputSequence.isEmpty {
                inputSequence[inputSequence.count - 1] = InputSequenceStep(direction: currentDirection, buttons: stepButtons)
            } else {
                inputSequence.append(InputSequenceStep(direction: currentDirection, buttons: stepButtons))
            }
            lastDirectionStepTime = Date()
        }
        if isDiagonalMerge || hasDirectionChange || isDirectionRepress || hasButtonPress {
            chargeGeneration &+= 1
            chargeCheckTask?.cancel()
            chargeCheckTask = nil
            directionHoldStart = nil
            if inputSequence.count > maxSequenceLength {
                inputSequence.removeFirst(inputSequence.count - maxSequenceLength)
            }
            resetTimeout()
        } else if currentDirection != nil && directionHoldStart == nil {
            directionHoldStart = Date()
            scheduleChargeCheck()
        }

        appendRawDirection(currentDirection)
        updateDetectedMotions()
    }

    private func resetTimeout() {
        timeoutTask?.cancel()
        let timeout = inputTimeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.inputSequence.removeAll()
            self?.lastDirection = nil
            self?.previousDirection = nil
            self?.directionHasGoneNeutral = false
            self?.directionHoldStart = nil
            self?.chargeGeneration &+= 1
            self?.chargeCheckTask?.cancel()
            self?.chargeCheckTask = nil
            self?.lastDirectionStepTime = nil
            self?.rawDirectionHistory.removeAll()
            self?.detectedMotions = []
        }
    }

    private func scheduleChargeCheck() {
        chargeGeneration &+= 1
        chargeCheckTask?.cancel()
        let threshold = chargeThreshold
        let gen = chargeGeneration
        chargeCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(threshold) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.markLastDirectionAsCharge(generation: gen)
        }
    }

    private func markLastDirectionAsCharge(generation: UInt) {
        guard generation == chargeGeneration else { return }
        guard directionHoldStart != nil, let heldDir = lastDirection else { return }
        for i in stride(from: inputSequence.count - 1, through: 0, by: -1) {
            if inputSequence[i].buttons.isEmpty, inputSequence[i].direction == heldDir {
                inputSequence[i].isCharge = true
                break
            }
        }
    }

    private func commitResidualDirection() {
        guard let dir = pendingResidualDirection, lastDirection == dir else {
            pendingResidualDirection = nil
            return
        }
        pendingResidualDirection = nil
        let lastStepDir = inputSequence.last?.direction
        guard dir != lastStepDir else { return }
        inputSequence.append(InputSequenceStep(direction: dir, buttons: []))
        lastDirectionStepTime = Date()
        directionHasGoneNeutral = false
        chargeGeneration &+= 1
        chargeCheckTask?.cancel()
        chargeCheckTask = nil
        directionHoldStart = nil
        if inputSequence.count > maxSequenceLength {
            inputSequence.removeFirst(inputSequence.count - maxSequenceLength)
        }
        resetTimeout()
    }

    func clearSequence() {
        timeoutTask?.cancel()
        residualDirectionTimer?.cancel()
        residualDirectionTimer = nil
        pendingResidualDirection = nil
        inputSequence.removeAll()
        lastDirection = nil
        previousDirection = nil
        directionHasGoneNeutral = false
        directionHoldStart = nil
        chargeGeneration &+= 1
        chargeCheckTask?.cancel()
        chargeCheckTask = nil
        lastDirectionStepTime = nil
        rawDirectionHistory.removeAll()
        detectedMotions = []
    }

    private func appendRawDirection(_ dir: FightDataDirection?) {
        guard let dir else { return }
        if dir != rawDirectionHistory.last {
            rawDirectionHistory.append(dir)
            if rawDirectionHistory.count > 16 {
                rawDirectionHistory.removeFirst(rawDirectionHistory.count - 16)
            }
        }
    }

    private func updateDetectedMotions() {
        let raw = rawDirectionHistory
        detectedMotions = MotionDetector.detect(in: raw)
    }
}

extension RetroButton {
    var isDirectional: Bool {
        switch self {
        case .up, .down, .left, .right,
             .lStickUp, .lStickDown, .lStickLeft, .lStickRight,
             .rStickUp, .rStickDown, .rStickLeft, .rStickRight,
             .cUp, .cDown, .cLeft, .cRight:
            return true
        default:
            return false
        }
    }
}
