import Foundation
import SwiftUI

// MARK: - ESRB Rating Enum

enum ESRRBRating: String, CaseIterable, Identifiable, Codable {
    case eC = "EC"
    case e = "E"
    case e10Plus = "E10+"
    case t = "T"
    case m = "M"
    case ao = "AO"
    case rp = "RP"
    
    var id: String { rawValue }
    
    var fullLabel: String {
        switch self {
        case .eC: return "EC - Early Childhood"
        case .e: return "E - Everyone"
        case .e10Plus: return "E10+ - Everyone 10+"
        case .t: return "T - Teen"
        case .m: return "M - Mature 17+"
        case .ao: return "AO - Adults Only 18+"
        case .rp: return "RP - Rating Pending"
        }
    }
    
    var icon: String {
        switch self {
        case .eC: return "shield.checkered"
        case .e: return "shield.fill"
        case .e10Plus: return "shield.lefthalf.filled"
        case .t: return "shield.lefthalf.filled"
        case .m: return "shield.slash"
        case .ao: return "xmark.shield"
        case .rp: return "questionmark.shield"
        }
    }
    
    var color: Color {
        switch self {
        case .eC, .e: return .green
        case .e10Plus: return .cyan
        case .t: return .yellow
        case .m: return .orange
        case .ao: return .red
        case .rp: return .secondary
        }
    }
}

// MARK: - Game Type Enum

enum GameType: String, CaseIterable, Identifiable, Codable {
    case action, adventure, fighting, platformer, puzzle
    case racing, rpg, simulation, sports, strategy
    
    var id: String { rawValue }
    
    var displayLabel: String { rawValue.capitalized }
    
    var icon: String {
        switch self {
        case .action: return "burst.fill"
        case .adventure: return "map.fill"
        case .fighting: return "hand.raised.filled"
        case .platformer: return "arrow.up.right.square.fill"
        case .puzzle: return "puzzlepiece.fill"
        case .racing: return "flag.checkered"
        case .rpg: return "sparkles"
        case .simulation: return "gearshape.fill"
        case .sports: return "sportscourt.fill"
        case .strategy: return "lightbulb.fill"
        }
    }
}

extension String {
    var capitalizedWords: String {
        split(separator: " ").map {
            let l = $0.lowercased()
            return l.prefix(1).uppercased() + l.dropFirst()
        }.joined(separator: " ")
    }
}
