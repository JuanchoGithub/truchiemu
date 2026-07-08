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
        case .noBoxArt: return LocalizationManager.shared.localized("filter.noBoxArt")
        case .neverPlayed: return LocalizationManager.shared.localized("filter.neverPlayed")
        case .unscanned: return LocalizationManager.shared.localized("filter.unidentified")
        case .multiplayer: return LocalizationManager.shared.localized("filter.multiplayer")
        }
    }

    var tooltip: String {
        switch self {
        case .noBoxArt: return LocalizationManager.shared.localized("filter.noBoxArtTooltip")
        case .neverPlayed: return LocalizationManager.shared.localized("filter.neverPlayedTooltip")
        case .unscanned: return LocalizationManager.shared.localized("filter.unidentifiedTooltip")
        case .multiplayer: return LocalizationManager.shared.localized("filter.multiplayerTooltip")
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
        return AppColors.brandAccent
    }

    static let primaryFilters: [GameFilterOption] = [.multiplayer]
    static let otherFilters: [GameFilterOption] = [.noBoxArt, .neverPlayed, .unscanned]
}