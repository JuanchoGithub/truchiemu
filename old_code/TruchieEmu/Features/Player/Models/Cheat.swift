import Foundation

// MARK: - Cheat Data Structures

// Represents a single cheat code for a game.
struct Cheat: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var index: Int
    var description: String
    var code: String
    var enabled: Bool = false
    var format: CheatFormat = .raw
    
    // Display name for the cheat (usually the description)
    var displayName: String {
        description.isEmpty ? "Cheat \(index + 1)" : description
    }
    
    // Short preview of the code (truncated if too long)
    var codePreview: String {
        code.count > 20 ? String(code.prefix(20)) + "..." : code
    }
}

// Supported cheat code formats.
enum CheatFormat: String, Codable, CaseIterable {
    case raw         // Raw hex address + value (e.g., 7E0DBE05)
    case gameGenie   // Game Genie (NES: 6-char, SNES: 8-char with check digit)
    case par         // Pro Action Replay (SNES/Genesis: 8-digit hex)
    case gameshark   // GameShark (PS1/N64: 8-digit hex with device code)
    
    var displayName: String {
        switch self {
        case .raw: return "Raw Hex"
        case .gameGenie: return "Game Genie"
        case .par: return "Pro Action Replay"
        case .gameshark: return "GameShark"
        }
    }
    
    // Example code format for user guidance
    var example: String {
        switch self {
        case .raw: return "7E0DBE05"
        case .gameGenie: return "G0X-Y1Z"
        case .par: return "7E0DBE05"
        case .gameshark: return "800DBE05"
        }
    }
}

// MARK: - Cheat File

// Represents a parsed .cht cheat file containing multiple cheats.
struct CheatFile: Identifiable, Codable {
    var id: UUID = UUID()
    var romPath: String          // Path to the ROM this cheat file belongs to
    var romName: String          // Name of the ROM for display
    var cheats: [Cheat]
    var source: CheatSource      // Where this file came from
    
    // Number of enabled cheats
    var enabledCount: Int {
        cheats.filter { $0.enabled }.count
    }
    
    // All cheats as a single string (for debugging)
    var summary: String {
        "\(cheats.count) cheats (\(enabledCount) enabled)"
    }
}

// Source of the cheat file.
enum CheatSource: String, Codable {
    case libretroDatabase   // From libretro-database/cheats
    case userDefined        // User-created custom cheat file
    case autoDetected       // Auto-loaded from ROM folder
}

// MARK: - Cheat Category

// Categories for organizing cheats.
enum CheatCategory: String, Codable, CaseIterable {
    case gameplay     // Infinite lives, health, etc.
    case items        // Weapons, power-ups, etc.
    case debug        // Debug modes, level select, etc.
    case custom       // User-added custom codes
    
    var displayName: String {
        switch self {
        case .gameplay: return "Gameplay"
        case .items: return "Items & Equipment"
        case .debug: return "Debug & Testing"
        case .custom: return "Custom Codes"
        }
    }
    
    var icon: String {
        switch self {
        case .gameplay: return "heart.fill"
        case .items: return "star.fill"
        case .debug: return "wrench.fill"
        case .custom: return "plus.circle.fill"
        }
    }
}