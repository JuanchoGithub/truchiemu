import Foundation

struct FightDataGame: Codable {
    let schemaVersion: Int
    let romIds: [String]
    let name: String
    let year: Int?
    let manufacturer: String?
    let credits: String?
    let controls: [String: String]
    let controlAbbr: [String: String]?
    let controlGroups: [String: [String]]?
    let categories: [String: String]
    let commonCommands: [FightDataMove]?
    let commonNotes: [String]?
    let cheatNotes: [String]?
    let howToPlayNotes: [String]?
    let characters: [FightDataCharacter]
    let systemControlMappings: [String: [String: String]]?
}

struct FightDataIndex: Codable {
    let schemaVersion: Int
    let games: [FightDataIndexEntry]
}

struct FightDataIndexEntry: Codable {
    let name: String
    let cleanName: String
    let normalizedName: String
    let file: String
    let romIds: [String]
    let aliases: [String]
    let year: Int?
    let manufacturer: String?
}

struct FightDataCharacter: Codable, Identifiable {
    var id: String { name }
    let name: String
    let moves: [FightDataMove]
    let notes: [String]?
    let combos: [String]?
}

struct FightDataMove: Codable, Identifiable {
    var id: String { "\(category)_\(name ?? "")_\(input ?? "")" }
    let category: String
    let name: String?
    let input: String?
    let hitLevels: String?
    let condition: String?

    var hasInputData: Bool { input != nil && !input!.isEmpty }
}

enum HitLevel: String, Equatable, CaseIterable {
    case high = "h"
    case mid = "m"
    case low = "l"
    case midCrouching = "M"
    case lowCrouching = "L"
    case ground = "g"
    case unblockable = "!"
    case none = "-"

    var color: String {
        switch self {
        case .high: return "red"
        case .mid: return "blue"
        case .low: return "green"
        case .midCrouching: return "purple"
        case .lowCrouching: return "teal"
        case .ground: return "brown"
        case .unblockable: return "orange"
        case .none: return "gray"
        }
    }

    var label: String {
        switch self {
        case .high: return "H"
        case .mid: return "M"
        case .low: return "L"
        case .midCrouching: return "MC"
        case .lowCrouching: return "LC"
        case .ground: return "G"
        case .unblockable: return "U"
        case .none: return "-"
        }
    }

    static func parse(_ string: String) -> [HitLevel] {
        string.compactMap { HitLevel(rawValue: String($0)) }
    }
}

struct ParsedStep: Equatable, Codable {
    var direction: Int?
    let buttons: [String]
    let isCharge: Bool
    let isHold: Bool
    let isRelease: Bool
    let isRapid: Bool
    let isAirStep: Bool
    let isMotion360: Bool
    let isCloseRange: Bool

    static func == (lhs: ParsedStep, rhs: ParsedStep) -> Bool {
        lhs.direction == rhs.direction && lhs.buttons == rhs.buttons && lhs.isCharge == rhs.isCharge && lhs.isHold == rhs.isHold && lhs.isRelease == rhs.isRelease && lhs.isRapid == rhs.isRapid && lhs.isAirStep == rhs.isAirStep && lhs.isMotion360 == rhs.isMotion360 && lhs.isCloseRange == rhs.isCloseRange
    }

    init(direction: Int? = nil, buttons: [String], isCharge: Bool, isHold: Bool, isRelease: Bool, isRapid: Bool, isAirStep: Bool, isMotion360: Bool = false, isCloseRange: Bool = false) {
        self.direction = direction
        self.buttons = buttons
        self.isCharge = isCharge
        self.isHold = isHold
        self.isRelease = isRelease
        self.isRapid = isRapid
        self.isAirStep = isAirStep
        self.isMotion360 = isMotion360
        self.isCloseRange = isCloseRange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = try container.decodeIfPresent(Int.self, forKey: .direction)
        buttons = try container.decode([String].self, forKey: .buttons)
        isCharge = try container.decode(Bool.self, forKey: .isCharge)
        isHold = try container.decode(Bool.self, forKey: .isHold)
        isRelease = try container.decode(Bool.self, forKey: .isRelease)
        isRapid = try container.decode(Bool.self, forKey: .isRapid)
        isAirStep = try container.decode(Bool.self, forKey: .isAirStep)
        isMotion360 = try container.decodeIfPresent(Bool.self, forKey: .isMotion360) ?? false
        isCloseRange = try container.decodeIfPresent(Bool.self, forKey: .isCloseRange) ?? false
    }
}

struct ResolvedMove: Identifiable {
    let id: String
    let name: String
    let categoryLabel: String
    let notation: String
    let tokens: [NotationToken]
    let hitLevels: [HitLevel]
    let condition: String?
    let parsedSteps: [[ParsedStep]]
    let isAir: Bool
    let isCharge: Bool
    let isMotion360: Bool
    let matchCount: Int
    let totalSteps: Int
    let matchedStepCount: Int

    var inputDirections: [[Int]] {
        guard let first = parsedSteps.first else { return [] }
        return first.compactMap { step in
            if let dir = step.direction { return [dir] }
            return nil
        }
    }

    var inputButtons: [[String]] {
        guard let first = parsedSteps.first else { return [] }
        return first.filter { !$0.buttons.isEmpty }.map { $0.buttons }
    }
}

enum FightDataDirection: Int, Codable, CaseIterable {
    case neutral = 5
    case up = 8
    case upRight = 9
    case right = 6
    case downRight = 3
    case down = 2
    case downLeft = 1
    case left = 4
    case upLeft = 7

    static func fromRetroButtons(held: Set<RetroButton>) -> FightDataDirection? {
        let hasUp = held.contains(.up)
        let hasDown = held.contains(.down)
        let hasLeft = held.contains(.left)
        let hasRight = held.contains(.right)
        if hasUp && hasRight { return .upRight }
        if hasUp && hasLeft { return .upLeft }
        if hasDown && hasRight { return .downRight }
        if hasDown && hasLeft { return .downLeft }
        if hasUp { return .up }
        if hasDown { return .down }
        if hasLeft { return .left }
        if hasRight { return .right }
        return nil
    }

    func isSubdirection(of parent: FightDataDirection) -> Bool {
        switch (self, parent) {
        case (.up, .upRight), (.up, .upLeft),
             (.down, .downRight), (.down, .downLeft),
             (.left, .upLeft), (.left, .downLeft),
             (.right, .upRight), (.right, .downRight):
            return true
        default: return false
        }
    }
}

enum MotionType: Equatable {
    case quarterCircle(from: FightDataDirection)
    case halfCircle(from: FightDataDirection)
    case fullCircle(direction: FightDataDirection)
}

enum ButtonTokenType: Equatable {
    case punch(strength: ButtonStrength)
    case kick(strength: ButtonStrength)
    case air
    case grapple
    case block
    case weapon(style: WeaponStyle)
    case generic(label: String)
}

enum ButtonStrength: Equatable {
    case low
    case medium
    case high
}

enum WeaponStyle: Equatable {
    case sword
    case axe
}

enum NotationToken: Equatable {
    case direction(FightDataDirection)
    case motion(MotionType)
    case button(ButtonTokenType)
    case separator
    case wait
    case air
    case charge(FightDataDirection?)
    case holdButton
    case rapidPress
    case hitLevel(HitLevel)
    case alternative
    case motion360
    case standClose
}

struct InputSequenceStep: Equatable {
    var direction: FightDataDirection?
    let buttons: Set<String>
    var isCharge: Bool = false

    static func == (lhs: InputSequenceStep, rhs: InputSequenceStep) -> Bool {
        lhs.direction == rhs.direction && lhs.buttons == rhs.buttons && lhs.isCharge == rhs.isCharge
    }
}

enum InputDisplayStep: Equatable {
    case direction(FightDataDirection, isCharge: Bool)
    case motion(MotionType)
    case buttons(Set<String>)
}
