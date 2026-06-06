import SwiftUI
import AppKit

// MARK: - List Row

struct GameListRowView: View {
    let rom: ROM
    let isSelected: Bool
    let isEvenRow: Bool
    let zoomLevel: Double
    let filter: LibraryFilter?
    @Environment(\.colorScheme) private var colorScheme
    @State private var thumb: NSImage?
    @State private var isHovered = false
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var categoryManager: CategoryManager
    @ObservedObject private var raService = RetroAchievementsService.shared
    
    private var titleFontSize: CGFloat {
        12 + zoomLevel * 8
    }
    
    private var subtitleFontSize: CGFloat {
        9 + zoomLevel * 5
    }
    
    private var thumbSize: CGFloat {
        36 + zoomLevel * 24
    }
    
    private var categoryBadges: [GameCategory] {
        categoryManager.categories.filter { $0.gameIDs.contains(rom.id) }
    }
    
    // MARK: - Formatted Playtime
    
    private var formattedPlaytime: String? {
        guard rom.totalPlaytimeSeconds > 0 else { return nil }
        let seconds = rom.totalPlaytimeSeconds
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
    
    private var timesPlayedLabel: String? {
        guard rom.timesPlayed > 0 else { return nil }
        if rom.timesPlayed == 1 {
            return "1 play"
        } else {
            return "\(rom.timesPlayed) plays"
        }
    }
    
    private var metadataLine1: String? {
        var parts: [String] = []
        if let year = rom.metadata?.year, !year.isEmpty {
            parts.append(year)
        }
        if let dev = rom.metadata?.developer, !dev.isEmpty {
            parts.append(dev)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " \u{2022} ")
    }
    
    private var metadataLine2: String? {
        var parts: [String] = []
        if let genre = rom.metadata?.genre, !genre.isEmpty {
            parts.append(genre)
        }
        if let players = rom.metadata?.players, players > 0 {
            parts.append(players == 1 ? "1 player" : "\(players) players")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " \u{2022} ")
    }

    var body: some View {
        HStack(spacing: 12) {
            artThumb
            
            // Left side: game info
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rom.displayName)
                        .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                    
                    if let systemID = rom.systemID, systemID != "unknown", !(filter?.isSystemView ?? false) {
                        Text(systemID.uppercased())
                            .font(.system(size: subtitleFontSize * 0.8, weight: .regular, design: .rounded))
                            .foregroundColor(AppColors.textMuted(colorScheme))
                            .lineLimit(1)
                    }
                }
                
                // System name
                if let sys = SystemDatabase.system(forID: rom.systemID ?? "") {
                    HStack(spacing: 4) {
                        if let emuImg = sys.emuImage(size: 132) {
                            Image(nsImage: emuImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                        }
Text(sys.name)
                        .font(.system(size: subtitleFontSize))
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                }
                
                // Category badges
                if !categoryBadges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(categoryBadges) { category in
                                CategoryBadgeView(category: category)
                            }
                        }
                    }
                }
                
                // Metadata: Year/Developer
                if let line1 = metadataLine1 {
                    Text(line1)
                        .font(.system(size: subtitleFontSize - 1))
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.8))
                }
                
                // Metadata: Genre/Players
                if let line2 = metadataLine2 {
                    Text(line2)
                        .font(.system(size: subtitleFontSize - 1))
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.8))
                }
            }
            
            Spacer()
            
            // Right side: stats column
            VStack(alignment: .trailing, spacing: 4) {
                // Playtime
                if let playtime = formattedPlaytime {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: subtitleFontSize - 0.5))
                        Text(playtime)
                            .font(.system(size: subtitleFontSize))
                            .fontWeight(.medium)
}
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }

            // Times played
            if let timesPlayed = timesPlayedLabel {
                Text(timesPlayed)
                    .font(.system(size: subtitleFontSize))
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }

            // Last played
            if let played = rom.lastPlayed {
                Text(played, style: .relative)
                .font(.system(size: subtitleFontSize - 0.5))
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.7))
            }

            // RetroAchievements compatible
            if raService.isEnabled && rom.raMatchStatus == "matched" {
                Image(systemName: "trophy.fill")
                .foregroundColor(AppColors.brandAccent)
                .font(.system(size: subtitleFontSize))
            }

            // Favorite indicator
                if rom.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.pink)
                        .font(.system(size: subtitleFontSize))
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            Rectangle()
            .fill(isEvenRow ? AppColors.cardBackground(colorScheme) : .clear)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? AppColors.accentBackground(colorScheme) :
                  isHovered ? AppColors.brandAccentSecondary.opacity(0.04) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? AppColors.brandAccentSecondary.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppColors.brandAccentSecondary.opacity(0.2))
                .frame(width: 2, height: 20)
                .padding(.leading, 4)
        }
        .onHover { isHovered = $0 }
        .task(id: rom.id) {
            // Lazy-resolve local boxart on-demand if not already set
            if rom.hasBoxArt {
                if let thumb = await ImageCache.shared.thumbnail(for: rom.boxArtLocalPath) {
                    self.thumb = thumb
                }
            } else {
                if let resolvedPath = BoxArtService.shared.resolveLocalBoxArtIfNeeded(for: rom, library: library) {
                    self.thumb = await ImageCache.shared.thumbnail(for: resolvedPath)
                } else {
                    self.thumb = nil
                }
            }
        }
    }

    private var artThumb: some View {
        Group {
            if let img = thumb {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            } else {
                let sys = SystemDatabase.system(forID: rom.systemID ?? "")
                if let emuImg = sys?.emuImage(size: 132) {
                    Image(nsImage: emuImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                } else {
                    Image(systemName: sys?.iconName ?? "gamecontroller")
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColors.cardBackgroundSubtle(colorScheme))
                }
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        .shadow(color: AppColors.brandAccent.opacity(0.12), radius: 3, x: 0, y: 1)
    }
}
