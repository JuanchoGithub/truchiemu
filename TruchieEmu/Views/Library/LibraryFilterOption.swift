import SwiftUI

// MARK: - Game Filter Options

// Filter chips for refining the game library view
enum GameFilterOption: String, CaseIterable, Identifiable {
    case noBoxArt      = "noBoxArt"
    case neverPlayed   = "neverPlayed"
    case notFavorite   = "notFavorite"
    case unscanned     = "unscanned"
    case multiplayer   = "multiplayer"
    case hasMetadata   = "hasMetadata"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .noBoxArt:     return "photo"
        case .neverPlayed:  return "play.slash"
        case .notFavorite:  return "heart.slash"
        case .unscanned:    return "qrcode.viewfinder"
        case .multiplayer:  return "person.2.fill"
        case .hasMetadata:  return "info.circle"
        }
    }
    
    var label: String {
        switch self {
        case .noBoxArt:     return "No Box Art"
        case .neverPlayed:  return "Never Played"
        case .notFavorite:  return "Not Favorite"
        case .unscanned:    return "Unidentified"
        case .multiplayer:  return "Multiplayer"
        case .hasMetadata:  return "Has Metadata"
        }
    }
    
    var tooltip: String {
        switch self {
        case .noBoxArt:     return "Games missing cover art"
        case .neverPlayed:  return "Games that have never been launched"
        case .notFavorite:  return "Games not marked as favorites"
        case .unscanned:    return "Games lacking identification data"
        case .multiplayer:  return "Games supporting 2+ players"
        case .hasMetadata:  return "Has Metadata"
        }
    }
    
    func matches(_ rom: ROM) -> Bool {
        switch self {
        case .noBoxArt:
            return !rom.hasBoxArt
        case .neverPlayed:
            return rom.lastPlayed == nil
        case .notFavorite:
            return !rom.isFavorite
        case .unscanned:
            return rom.crc32 == nil && rom.thumbnailLookupSystemID == nil
        case .multiplayer:
            return (rom.metadata?.players ?? 0) >= 2
        case .hasMetadata:
            let title = rom.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !title.isEmpty
        }
    }
    
    var activeColor: Color {
        // Unified accent color — lets box art, not filter chips, provide the palette
        return .accentColor
    }
}
