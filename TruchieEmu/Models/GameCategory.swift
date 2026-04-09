import Foundation
import SwiftUI

/// A user-defined category for organizing games in the library
struct GameCategory: Identifiable, Codable, Hashable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var iconName: String // SF Symbol name
    var colorHex: String // Hex color string
    
    /// Array of ROM IDs that belong to this category
    var gameIDs: [UUID] = []
    
    /// Display order in the sidebar
    var sortOrder: Int = 0
    
    /// Derived color
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
    
    /// Common icon presets
    static let commonIcons = [
        "folder.fill", "star.fill", "heart.fill", "gamecontroller.fill",
        "trophy.fill", "flag.fill", "bookmark.fill", "tag.fill",
        "cart.fill", "bag.fill", "gift.fill", "crown.fill",
        "bolt.fill", "flame.fill", "moon.fill", "sun.max.fill",
        "cloud.fill", "drop.fill", "leaf.fill", "bubble.left.fill",
        "music.note.list", "film.fill", "tv.fill", "book.fill",
        "puzzlepiece.fill", "brain.fill", "wand.and.stars", "rosette"
    ]
    
    /// Predefined color palette
    static let colorPalette: [(name: String, hex: String)] = [
        ("Red", "FF3B30"), ("Orange", "FF9500"), ("Yellow", "FFCC00"),
        ("Green", "34C759"), ("Mint", "00C7BE"), ("Teal", "5AC8FA"),
        ("Cyan", "32ADE6"), ("Blue", "007AFF"), ("Indigo", "5856D6"),
        ("Purple", "AF52DE"), ("Pink", "FF2D55"), ("Brown", "A2845E"),
        ("Gray", "8E8E93"), ("Dark Gray", "636366")
    ]
    
    /// Default categories
    static func defaults() -> [GameCategory] {
        [
            GameCategory(name: "Favorites", iconName: "heart.fill", colorHex: "FF2D55", sortOrder: 0),
        ]
    }
    
    static func == (lhs: GameCategory, rhs: GameCategory) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
    
    var hex: String? {
        let components = Self.components(from: self)
        guard let components = components else { return nil }
        
        let r = UInt8(round(components.red * 255))
        let g = UInt8(round(components.green * 255))
        let b = UInt8(round(components.blue * 255))
        
        return String(format: "%02X%02X%02X", r, g, b)
    }
    
    private static func components(from color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        let nsColor = NSColor(color)
        guard let components = nsColor.cgColor.components, components.count >= 3 else {
            return nil
        }
        return (
            red: components[0],
            green: components[1],
            blue: components[2],
            alpha: components.count >= 4 ? components[3] : 1.0
        )
    }
}