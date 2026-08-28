import SwiftUI
import AppKit

// MARK: - List Row

struct GameListRowView: View {
    let rom: ROM
    let isSelected: Bool
    let isEvenRow: Bool
    let zoomLevel: Double
    let filter: LibraryFilter?
    let raEnabled: Bool
    var contextMenu: (() -> AnyView)?
    let isScrolling: Bool
    var onPlay: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var thumb: NSImage?
    @State private var isHovered = false
    @State private var raProgress: (earned: Int, total: Int)?
    @ObservedObject private var boxArtService = BoxArtService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var categoryManager: CategoryManager
    
    private var titleFontSize: CGFloat {
        12 + zoomLevel * 8
    }
    
    private var subtitleFontSize: CGFloat {
        9 + zoomLevel * 5
    }
    
    private var boxType: BoxType {
        SystemPreferences.shared.boxType(for: rom.systemID ?? "")
    }

    private var artExtent: CGFloat {
        64 + zoomLevel * 72
    }

    private var thumbWidth: CGFloat {
        let aspect = boxType.aspectRatio
        return aspect >= 1 ? artExtent : artExtent * aspect
    }

    private var thumbHeight: CGFloat {
        let aspect = boxType.aspectRatio
        return aspect >= 1 ? artExtent / aspect : artExtent
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

    private func summarizedLastPlayed(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        guard interval >= 0 else { return loc.localized("library.stat.justNow") }
        let sec = Int(interval)
        if sec < 60 { return loc.localized("library.stat.justNow") }
        let min = sec / 60
        if min < 60 { return String(format: loc.localized("library.stat.minutes"), min) }
        let hr = min / 60
        if hr < 24 { return String(format: loc.localized("library.stat.hours"), hr) }
        let day = hr / 24
        if day < 7 { return String(format: loc.localized("library.stat.days"), day) }
        let week = day / 7
        if week < 5 { return String(format: loc.localized("library.stat.weeks"), week) }
        let month = day / 30
        if month < 12 { return String(format: loc.localized("library.stat.months"), month) }
        let year = day / 365
        return String(format: loc.localized("library.stat.years"), year)
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
            parts.append(GenreManager.shared.effectiveDisplayName(for: genre))
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
                        if isHovered {
                            Text(loc.localized("library.stat.time"))
                                .font(.system(size: subtitleFontSize - 1))
                                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.7))
                        }
                        Text(playtime)
                            .font(.system(size: subtitleFontSize))
                            .fontWeight(.medium)
                    }
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }

                // Times played
                if let timesPlayed = timesPlayedLabel {
                    HStack(spacing: 3) {
                        if isHovered {
                            Text(loc.localized("library.stat.plays"))
                                .font(.system(size: subtitleFontSize - 1))
                                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.7))
                        }
                        Text(timesPlayed)
                            .font(.system(size: subtitleFontSize))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                }

                // Last played
                if let played = rom.lastPlayed {
                    HStack(spacing: 3) {
                        if isHovered {
                            Text(loc.localized("library.stat.lastPlayed"))
                                .font(.system(size: subtitleFontSize - 1))
                                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.7))
                        }
                        Text(summarizedLastPlayed(played))
                            .font(.system(size: subtitleFontSize - 0.5))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.7))
                    }
                }

                // RetroAchievements
                if raEnabled && rom.raMatchStatus == "matched" {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: subtitleFontSize - 0.5))
                        if isHovered {
                            Text(loc.localized("library.stat.achievements"))
                                .font(.system(size: subtitleFontSize - 1))
                                .foregroundColor(AppColors.brandAccent.opacity(0.8))
                        }
                        if let progress = raProgress {
                            Text("\(progress.earned)/\(progress.total)")
                                .font(.system(size: subtitleFontSize))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                    }
                    .foregroundColor(AppColors.brandAccent)
                }

                // Favorite indicator
                    if rom.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.pink)
                            .font(.system(size: subtitleFontSize))
                    }
                }

            if isHovered, let menuContent = contextMenu {
                ZStack {
                    Circle()
                        .fill(AppColors.brandAccent)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white)
                }
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(color: AppColors.brandAccent.opacity(0.4), radius: 4, y: 2)
                .opacity(0.7)
                .overlay(
                    Menu { menuContent() } label: {
                        Color.clear
                            .contentShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                )
                .transition(.opacity.combined(with: .scale))
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
        .onHover { hovering in
            if isScrolling {
                if !hovering { isHovered = false }
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
        }
        .task(id: "\(rom.id)-\(boxArtService.boxArtUpdated)") {
            // rom.boxArtLocalPath is authoritative and rom.hasBoxArt is correct
            // (resolved during the off-scroll pipeline), so this is zero
            // main-thread I/O. Art-less ROMs show the system placeholder.
            if rom.hasBoxArt {
                let artPath = rom.boxArtLocalPath
                if let cached = ImageCache.shared.thumbnailSync(for: artPath, preferredSize: .small) {
                    self.thumb = cached
                } else if let thumb = await ImageCache.shared.thumbnail(for: artPath, preferredSize: .small) {
                    self.thumb = thumb
                }
            } else {
                self.thumb = nil
            }

            if let raGameId = rom.raGameId, raGameId > 0, rom.raMatchStatus == "matched" {
                raProgress = RetroAchievementsService.cachedAchievementProgress(for: raGameId)
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
        .frame(width: thumb != nil ? thumbWidth : min(thumbWidth, thumbHeight), height: thumb != nil ? thumbHeight : min(thumbWidth, thumbHeight))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        .shadow(color: AppColors.brandAccent.opacity(0.12), radius: 3, x: 0, y: 1)
        .overlay(alignment: .center) {
            if isHovered, onPlay != nil {
                GlassOrbPlayButton(
                    content: {
                        if let nsImage = thumb {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.secondary.opacity(0.3)
                        }
                    },
                    accent: AppColors.brandAccent,
                    action: { onPlay?() },
                    diameter: min(thumbWidth, thumbHeight) * 0.5
                )
                .transition(.opacity)
                .accessibilityLabel(Text("Launch " + rom.displayName))
            }
        }
    }
}
