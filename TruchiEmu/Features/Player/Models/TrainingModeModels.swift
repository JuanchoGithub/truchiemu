import Foundation

enum TrainingControlMode: String, Codable, CaseIterable {
    case standby
    case human
    case stanceGuard
    case fmdSequence
}

enum TrainingStance: String, Codable, CaseIterable {
    case stand
    case crouch
    case jump
}

enum TrainingGuard: String, Codable, CaseIterable {
    case noBlock
    case allBlock
    case randomBlock
    case firstHitBlock
}

enum TrainingWakeUpTech: String, Codable, CaseIterable {
    case none
    case quickRecovery
    case backRoll
}

enum TrainingHealthRegen: String, Codable, CaseIterable {
    case instantRefill
    case linearRegen
    case normal
}

enum TrainingSuperMeter: String, Codable, CaseIterable {
    case alwaysMaxed
    case keepCurrent
    case empty
}

enum TrainingSequenceTrigger: String, Codable, CaseIterable {
    case continuousLoop
    case onBlock
    case onHit
}

enum TrainingResetPosition: String, Codable, CaseIterable {
    case roundStart
    case leftCorner
    case rightCorner
    case custom
}

enum FrameProfile: Int, Codable, CaseIterable {
    case strict = 1
    case moderate = 2
    case standard = 3
    case lenient = 4
    case veryLenient = 5
}

enum SequenceCardType: String, Codable {
    case fmd
    case delay
    case tape
}

struct SequenceCard: Identifiable, Codable, Equatable {
    let id: UUID
    var cardType: SequenceCardType
    var fmdMoveId: String?
    var fmdMoveName: String?
    var fmdCharacterName: String?
    var fmdParsedSteps: [[ParsedStep]]?
    var delayFrames: Int
    var tapeSlot: Int

    init(cardType: SequenceCardType,
         fmdMoveId: String? = nil,
         fmdMoveName: String? = nil,
         fmdCharacterName: String? = nil,
         fmdParsedSteps: [[ParsedStep]]? = nil,
         delayFrames: Int = 0,
         tapeSlot: Int = 0) {
        self.id = UUID()
        self.cardType = cardType
        self.fmdMoveId = fmdMoveId
        self.fmdMoveName = fmdMoveName
        self.fmdCharacterName = fmdCharacterName
        self.fmdParsedSteps = fmdParsedSteps
        self.delayFrames = delayFrames
        self.tapeSlot = tapeSlot
    }

    static func fmd(moveId: String, moveName: String, characterName: String, parsedSteps: [[ParsedStep]]) -> SequenceCard {
        SequenceCard(cardType: .fmd, fmdMoveId: moveId, fmdMoveName: moveName, fmdCharacterName: characterName, fmdParsedSteps: parsedSteps)
    }

    static func delay(frames: Int) -> SequenceCard {
        SequenceCard(cardType: .delay, delayFrames: frames)
    }

    static func tape(slot: Int) -> SequenceCard {
        SequenceCard(cardType: .tape, tapeSlot: slot)
    }
}

struct TapeRecording: Codable {
    var frames: [[Int: Bool]]
    let createdAt: Date

    static let maxFrames = 600

    init(frames: [[Int: Bool]] = []) {
        self.frames = frames
        self.createdAt = Date()
    }
}

struct TrainingModeConfig: Codable {
    var isEnabled: Bool = false
    var freezeOnMenu: Bool = false
    var controlMode: TrainingControlMode = .standby
    var stance: TrainingStance = .stand
    var `guard`: TrainingGuard = .allBlock
    var p2FacesRight: Bool = false
    var genesisThreeButtonMode: Bool = false
    var wakeUpTech: TrainingWakeUpTech = .none
    var reversalMoveId: String? = nil
    var reversalParsedSteps: [[ParsedStep]]? = nil
    var healthRegen: TrainingHealthRegen = .instantRefill
    var superMeter: TrainingSuperMeter = .keepCurrent
    var resetPosition: TrainingResetPosition = .roundStart
    var customResetState: Data? = nil
    var leftCornerState: Data? = nil
    var rightCornerState: Data? = nil
    var sequenceCards: [SequenceCard] = []
    var sequenceTrigger: TrainingSequenceTrigger = .continuousLoop
    var autoInvert: Bool = true
    var frameProfile: FrameProfile = .standard
    var activeTapeSlot: Int = 0
    var hotkeyReset: [UInt16] = []
    var hotkeyRecord: [UInt16] = []
    var hotkeyPlayback: [UInt16] = []
}

struct FrameInput: Equatable {
    let directions: Set<RetroButton>
    let buttons: Set<RetroButton>

    static let empty = FrameInput(directions: [], buttons: [])

    var allPressed: Set<RetroButton> {
        directions.union(buttons)
    }
}
