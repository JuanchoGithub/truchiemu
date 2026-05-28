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
    let characters: [FightDataCharacter]
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

struct ParsedInput: Codable {
    let raw: String
    let directions: [[Int]]
    let buttons: [[String]]
    let charge: Bool
    let chargeDirection: Int?
    let air: Bool
    let rapidPress: Bool
    let holdButton: Bool
    let followUp: Bool
    let neutral: Bool
    let motion360: Bool
}

struct FightDataMove: Codable, Identifiable {
    var id: String { "\(category)_\(name)_\(input ?? "")" }
    let category: String
    let name: String
    let input: String?
    let parsedInput: ParsedInput?

    var inputDirections: [[Int]] { parsedInput?.directions ?? [] }
    var inputButtons: [[String]] { parsedInput?.buttons ?? [] }
    var isAir: Bool { parsedInput?.air ?? false }
    var isCharge: Bool { parsedInput?.charge ?? false }
    var chargeDirectionValue: Int? { parsedInput?.chargeDirection }
    var isMotion360: Bool { parsedInput?.motion360 ?? false }
    var isRapidPress: Bool { parsedInput?.rapidPress ?? false }
    var isHoldButton: Bool { parsedInput?.holdButton ?? false }
    var hasInputData: Bool { input != nil || parsedInput != nil }
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

    var symbol: String {
        switch self {
        case .neutral: return "●"
        case .up: return "↑"
        case .upRight: return "↗"
        case .right: return "→"
        case .downRight: return "↘"
        case .down: return "↓"
        case .downLeft: return "↙"
        case .left: return "←"
        case .upLeft: return "↖"
        }
    }

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
            default:
                return false
            }
        }
}

struct ResolvedMove: Identifiable {
    let id: String
    let name: String
    let categoryLabel: String
    let notation: String
    let inputDirections: [[Int]]
    let inputButtons: [[String]]
    let isAir: Bool
    let isCharge: Bool
    let isMotion360: Bool
    let matchCount: Int
    let totalSteps: Int
    let matchedStepCount: Int
}

struct InputSequenceStep: Equatable {
    var direction: FightDataDirection?
    let buttons: Set<String>
    var isCharge: Bool = false

    static func == (lhs: InputSequenceStep, rhs: InputSequenceStep) -> Bool {
        lhs.direction == rhs.direction && lhs.buttons == rhs.buttons && lhs.isCharge == rhs.isCharge
    }
}
