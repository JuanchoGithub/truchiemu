import SwiftUI

// MARK: - Game Filter Options

// Filter chips for refining the game library view
enum GameFilterOption: String, CaseIterable, Identifiable {
    case noBoxArt = "noBoxArt"
    case neverPlayed = "neverPlayed"
    case unscanned = "unscanned"
    case multiplayer = "multiplayer"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .noBoxArt: return "photo"
        case .neverPlayed: return "play.slash"
        case .unscanned: return "qrcode.viewfinder"
        case .multiplayer: return "person.2.fill"
        }
    }

    var label: String {
        switch self {
        case .noBoxArt: return "No Box Art"
        case .neverPlayed: return "Never Played"
        case .unscanned: return "Unidentified"
        case .multiplayer: return "Multiplayer"
        }
    }

    var tooltip: String {
        switch self {
        case .noBoxArt: return "Games missing cover art"
        case .neverPlayed: return "Games that have never been launched"
        case .unscanned: return "Games lacking identification data"
        case .multiplayer: return "Games supporting 2+ players"
        }
    }

    func matches(_ rom: ROM) -> Bool {
        switch self {
        case .noBoxArt:
            return !rom.hasBoxArt
        case .neverPlayed:
            return rom.lastPlayed == nil
        case .unscanned:
            return rom.crc32 == nil && rom.thumbnailLookupSystemID == nil
        case .multiplayer:
            return (rom.metadata?.players ?? 0) >= 2
        }
    }

    var activeColor: Color {
        return .accentColor
    }
}