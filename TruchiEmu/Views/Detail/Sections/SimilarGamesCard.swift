import SwiftUI

/// Recommendation shelf for the game info view. Each tile opens the game info
/// window; the play badge on hover launches the game directly.
struct SimilarGamesCard: View {
    let matches: [SimilarGameMatch]
    let onOpen: (ROM) -> Void
    let onPlay: (ROM) -> Void

    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        ModernSectionCard(
            title: loc.localized("gameDetail.similarGames"),
            icon: "sparkles",
            badge: "\(matches.count)"
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118, maximum: 150), spacing: AppSpacing.md)],
                alignment: .leading,
                spacing: AppSpacing.lg
            ) {
                ForEach(matches) { match in
                    SimilarGameTile(
                        match: match,
                        onOpen: { onOpen(match.rom) },
                        onPlay: { onPlay(match.rom) }
                    )
                }
            }
        }
    }
}

private struct SimilarGameTile: View {
    let match: SimilarGameMatch
    let onOpen: () -> Void
    let onPlay: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var artImage: NSImage?
    @State private var isHovered = false

    private var systemName: String {
        SystemDatabase.systemName(forInternalID: match.rom.systemID ?? "")
    }

    private var subtitle: String {
        let year = match.rom.metadata?.year
        return [systemName, year]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var systemIconName: String {
        SystemDatabase.system(forID: match.rom.systemID ?? "")?.iconName ?? "gamecontroller.fill"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                artworkView

                Text(verbatim: match.rom.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .lineLimit(1)

                Text(verbatim: loc.localized(match.reason.localizationKey))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(AppColors.brandAccent)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isHovered {
                playButton
                    .padding(6)
            }
        }
        .help(loc.localized("contextMenu.seeGameInfo"))
        .accessibilityLabel(Text(verbatim: match.rom.displayName))
        .onHover { isHovered = $0 }
        .task(id: match.rom.id) {
            guard artImage == nil, match.rom.hasBoxArt else { return }
            artImage = await ImageCache.shared.thumbnail(for: match.rom.boxArtLocalPath, preferredSize: .small)
        }
    }

    private var artworkView: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let artImage {
                    Image(nsImage: artImage)
                        .resizable()
                        .scaledToFill()
                } else if let system = SystemDatabase.system(forID: match.rom.systemID ?? ""),
                          let emuImage = system.emuImage(size: 96) {
                    Image(nsImage: emuImage)
                        .resizable()
                        .scaledToFit()
                        .padding(22)
                } else {
                    Image(systemName: systemIconName)
                        .font(.title2)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isHovered ? AppColors.brandAccent.opacity(0.8) : AppColors.cardBorder(colorScheme),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: isHovered ? AppColors.brandAccent.opacity(0.28) : .black.opacity(0.14),
                radius: isHovered ? 8 : 3,
                y: isHovered ? 4 : 1
            )
            .scaleEffect(isHovered ? 1.03 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var playButton: some View {
        Button(action: onPlay) {
            Image(systemName: "play.fill")
                .font(.system(size: 9, weight: .black))
                .foregroundColor(AppColors.textOnAccent(colorScheme))
                .frame(width: 24, height: 24)
                .background(Circle().fill(AppColors.brandAccent))
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .help(loc.localized("contextMenu.launchGame"))
        .accessibilityLabel(Text(verbatim: "\(loc.localized("contextMenu.launchGame")) \(match.rom.displayName)"))
    }
}

private extension SimilarGameMatch.Reason {
    var localizationKey: String {
        switch self {
        case .genre: return "similarGames.reason.genre"
        case .developer: return "similarGames.reason.developer"
        case .series: return "similarGames.reason.series"
        case .publisher: return "similarGames.reason.publisher"
        case .year: return "similarGames.reason.year"
        }
    }
}
