import Foundation

@MainActor
class SequenceRunner: ObservableObject {
    @Published var cards: [SequenceCard] = []
    @Published var triggerCondition: TrainingSequenceTrigger = .continuousLoop
    @Published var autoInvert: Bool = true
    @Published var currentIndex: Int = 0
    @Published var currentFrameInCard: Int = 0
    @Published var isExecuting: Bool = false
    @Published var activeFMDMoveName: String? = nil
    @Published var activeFMDFrame: Int = 0
    @Published var activeFMDTotalFrames: Int = 0
    @Published var waitingForTrigger: Bool = false

    private var expandedFrames: [FrameInput] = []
    private var delayRemaining: Int = 0
    private var tapeSlot: Int = 0
    private var p2FacesRight: Bool = true

    private let p2Player = 1

    struct ExpansionContext {
        let layout: ArcadeLayout
        let systemID: String
        let systemControlMappings: [String: [String: String]]?
        let frameProfile: FrameProfile
    }

    private(set) var expansionContext: ExpansionContext?

    func setExpansionContext(_ context: ExpansionContext) {
        expansionContext = context
    }

    func loadCards(_ newCards: [SequenceCard]) {
        cards = newCards
        reset()
    }

    func setTriggerCondition(_ condition: TrainingSequenceTrigger) {
        triggerCondition = condition
    }

    func reset() {
        currentIndex = 0
        currentFrameInCard = 0
        expandedFrames = []
        delayRemaining = 0
        waitingForTrigger = false
        activeFMDMoveName = nil
        activeFMDFrame = 0
        activeFMDTotalFrames = 0
        isExecuting = !cards.isEmpty
        if !cards.isEmpty {
            prepareCurrentCard()
        }
    }

    func notifyP1Attack(p2IsGuarding: Bool) {
        guard waitingForTrigger else { return }
        switch triggerCondition {
        case .onBlock where p2IsGuarding:
            waitingForTrigger = false
            isExecuting = true
            prepareCurrentCard()
        case .onHit where !p2IsGuarding:
            waitingForTrigger = false
            isExecuting = true
            prepareCurrentCard()
        default:
            break
        }
    }

    func setOrientation(facesRight: Bool) {
        p2FacesRight = facesRight
    }

    func advanceFrame(adapter: XPCBridgeAdapter) -> Bool {
        guard isExecuting, currentIndex < cards.count else {
            clearP2Input(adapter: adapter)
            return false
        }

        let card = cards[currentIndex]

        switch card.cardType {
        case .fmd:
            return advanceFMDCard(adapter: adapter)
        case .delay:
            return advanceDelayCard(adapter: adapter)
        case .tape:
            return true
        }
    }

    func currentTapeSlot() -> Int? {
        guard isExecuting, currentIndex < cards.count else { return nil }
        let card = cards[currentIndex]
        return card.cardType == .tape ? card.tapeSlot : nil
    }

    private func advanceFMDCard(adapter: XPCBridgeAdapter) -> Bool {
        guard currentFrameInCard < expandedFrames.count else {
            advanceToNextCard(adapter: adapter)
            return isExecuting
        }

        let frame = expandedFrames[currentFrameInCard]
        applyFrameInput(frame, adapter: adapter)

        activeFMDFrame = currentFrameInCard
        currentFrameInCard += 1

        if currentFrameInCard >= expandedFrames.count {
            advanceToNextCard(adapter: adapter)
        }

        return true
    }

    private func advanceDelayCard(adapter: XPCBridgeAdapter) -> Bool {
        guard delayRemaining > 0 else {
            advanceToNextCard(adapter: adapter)
            return isExecuting
        }

        clearP2Input(adapter: adapter)
        delayRemaining -= 1

        if delayRemaining <= 0 {
            advanceToNextCard(adapter: adapter)
        }

        return true
    }

    func advanceToNextCard(adapter: XPCBridgeAdapter) {
        currentIndex += 1
        currentFrameInCard = 0
        expandedFrames = []
        delayRemaining = 0
        activeFMDMoveName = nil

        if currentIndex >= cards.count {
            if triggerCondition == .continuousLoop {
                currentIndex = 0
                prepareCurrentCard()
            } else {
                isExecuting = false
                waitingForTrigger = true
                clearP2Input(adapter: adapter)
            }
        } else {
            prepareCurrentCard()
        }
    }

    private func prepareCurrentCard() {
        guard currentIndex < cards.count else { return }
        let card = cards[currentIndex]

        switch card.cardType {
        case .fmd:
            if let parsedSteps = card.fmdParsedSteps, let firstAlt = parsedSteps.first, let ctx = expansionContext {
                let expander = FrameExpander(
                    steps: firstAlt,
                    frameProfile: ctx.frameProfile,
                    layout: ctx.layout,
                    systemID: ctx.systemID,
                    systemControlMappings: ctx.systemControlMappings
                )
                expandedFrames = expander.expand()
                activeFMDTotalFrames = expandedFrames.count
            } else {
                expandedFrames = []
                activeFMDTotalFrames = 0
            }
            activeFMDMoveName = card.fmdMoveName
            activeFMDFrame = 0

        case .delay:
            delayRemaining = card.delayFrames

        case .tape:
            tapeSlot = card.tapeSlot
        }
    }

    private func applyFrameInput(_ frame: FrameInput, adapter: XPCBridgeAdapter) {
        clearP2Input(adapter: adapter)

        let systemID = expansionContext?.systemID ?? ""
        let invert = autoInvert && !p2FacesRight
        let allButtons = frame.allPressed

        for button in allButtons {
            let mappedButton: RetroButton
            if invert {
                switch button {
                case .left: mappedButton = .right
                case .right: mappedButton = .left
                default: mappedButton = button
                }
            } else {
                mappedButton = button
            }

            let retroID = Int(mappedButton.retroID(for: systemID))
            if retroID >= 0 {
                adapter.setKeyState(retroID: retroID, player: p2Player, pressed: true)
            }
        }
    }

    private func clearP2Input(adapter: XPCBridgeAdapter) {
        for retroID in 0..<32 {
            adapter.setKeyState(retroID: retroID, player: p2Player, pressed: false)
        }
    }
}
