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

    private var p2FacesRight: Bool = true

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
        waitingForTrigger = false
        activeFMDMoveName = nil
        activeFMDFrame = 0
        activeFMDTotalFrames = 0
        isExecuting = !cards.isEmpty
    }

    func setOrientation(facesRight: Bool) {
        p2FacesRight = facesRight
    }
}
