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

    private var inputTimeout: TimeInterval { AppSettings.getDouble("moveListInputTimeout", defaultValue: 1.0) }
    private var chargeThreshold: TimeInterval { AppSettings.getDouble("moveListChargeThreshold", defaultValue: 0.8) }
    private var diagonalMergeWindow: TimeInterval { AppSettings.getDouble("moveListDiagonalMerge", defaultValue: 0.083) }
    private var residualDirectionDelay: TimeInterval { AppSettings.getDouble("moveListResidualDelay", defaultValue: 0.25) }
    private let maxSequenceLength = 10

    var arcadeLayout: ArcadeLayout = .capcom6
    var systemID: String = "snes"

    private let retroIDToButton: [Int: RetroButton] = [
        0: .b, 1: .y, 2: .select, 3: .start,
        4: .up, 5: .down, 6: .left, 7: .right,
        8: .a, 9: .x, 10: .l1, 11: .r1,
        12: .l2, 13: .r2, 14: .l3, 15: .r3
    ]

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
                if let fdKey = ArcadeButtonMapper.shared.fightDataKey(for: button, layout: arcadeLayout, systemID: systemID) {
                    stepButtons.insert(fdKey)
                } else {
                    stepButtons.insert(button.rawValue)
                }
            }
        }

    if isDiagonalDecomposition, let residual = currentDirection {
        pendingResidualDirection = residual
        residualDirectionTimer?.cancel()
        let delay = residualDirectionDelay
        residualDirectionTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.commitResidualDirection()
        }
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
            inputSequence[inputSequence.count - 1] = InputSequenceStep(direction: dir, buttons: [])
        } else if hasDirectionChange || isDirectionRepress {
            if let dir = currentDirection {
                inputSequence.append(InputSequenceStep(direction: dir, buttons: []))
                lastDirectionStepTime = Date()
                directionHasGoneNeutral = false
            }
        }

        if hasButtonPress {
            inputSequence.append(InputSequenceStep(direction: currentDirection, buttons: stepButtons))
            lastDirectionStepTime = Date()
        }
        if isDiagonalMerge || hasDirectionChange || isDirectionRepress || hasButtonPress {
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
            self?.chargeCheckTask?.cancel()
            self?.chargeCheckTask = nil
            self?.lastDirectionStepTime = nil
        }
    }

    private func scheduleChargeCheck() {
        chargeCheckTask?.cancel()
        let threshold = chargeThreshold
        chargeCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(threshold) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.markLastDirectionAsCharge()
        }
    }

    private func markLastDirectionAsCharge() {
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
        chargeCheckTask?.cancel()
        chargeCheckTask = nil
        lastDirectionStepTime = nil
    }
}

private extension RetroButton {
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
