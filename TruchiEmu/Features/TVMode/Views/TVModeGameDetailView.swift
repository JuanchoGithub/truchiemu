import SwiftUI
import AppKit

/// Page 2 in TV mode: detailed view of a single game.
/// Shows hero boxart, title screen (if any), up to 4 snaps, metadata, and a
/// launch hint. Title screen and snaps are downloaded on demand.
struct TVModeGameDetailView: View {
    let rom: ROM
    let theme: TVModeSettings.Theme
    let focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tvModeScale) private var scale
    @EnvironmentObject private var library: ROMLibrary
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var boxart: NSImage?
    @State private var titleImage: NSImage?
    @State private var snaps: [NSImage] = []
    @State private var selectedSnapIndex: Int = 0
    @State private var downloading: Bool = false

    private var heroWidth: CGFloat { 320 * scale }

    var body: some View {
        HStack(spacing: 32 * scale) {
            heroColumn
                .frame(width: heroWidth)
            infoColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(40 * scale)
        .onAppear { loadArt() }
        .onChange(of: rom.id) { _, _ in resetArt(); loadArt() }
    }

    @ViewBuilder
    private var heroColumn: some View {
        VStack(alignment: .center, spacing: 16 * scale) {
            if let img = boxart ?? titleImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: heroWidth, height: heroWidth * 4.0 / 3.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                            .strokeBorder(
                                theme == .bold ? AppColors.accentForScheme(colorScheme) : Color.white.opacity(0.4),
                                lineWidth: 2 * scale
                            )
                    )
            } else {
                RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: heroWidth, height: heroWidth * 4.0 / 3.0)
            }

            Text(rom.displayName)
                .font(.system(size: 26 * scale, weight: .bold))
                .foregroundStyle(theme == .bold ? AppColors.textPrimary(colorScheme) : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("tvMode.detail.launch")
                .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18 * scale).padding(.vertical, 8 * scale)
                .background(
                    Capsule().fill(theme == .bold ? AppColors.accentForScheme(colorScheme).opacity(0.25) : Color.gray.opacity(0.2))
                )
                .overlay(Capsule().strokeBorder(theme == .bold ? AppColors.accentForScheme(colorScheme) : Color.white.opacity(0.4), lineWidth: 1 * scale))
        }
    }

    @ViewBuilder
    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 22 * scale) {
            snapsSection
            metadataSection
            descriptionSection
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var snapsSection: some View {
        if !snaps.isEmpty {
            VStack(alignment: .leading, spacing: 10 * scale) {
                Text(loc.localized("tvMode.detail.snaps"))
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .foregroundStyle(theme == .bold ? AppColors.textPrimary(colorScheme) : .primary)
                HStack(spacing: 10 * scale) {
                    ForEach(snaps.indices, id: \.self) { i in
                        let img = snaps[i]
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 220 * scale, height: 165 * scale)
                            .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                                    .strokeBorder(
                                        i == selectedSnapIndex ? (theme == .bold ? AppColors.accentForScheme(colorScheme) : Color.white) : Color.white.opacity(0.08),
                                        lineWidth: i == selectedSnapIndex ? 2 * scale : 0.5 * scale
                                    )
                            )
                            .onTapGesture { selectedSnapIndex = i }
                    }
                }
            }
        } else if downloading {
            HStack(spacing: 10 * scale) {
                ProgressView().scaleEffect(0.8)
                Text(loc.localized("tvMode.detail.noSnaps")).font(.system(size: 13 * scale)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            metadataRow(title: "tvMode.detail.year", value: rom.metadata?.year)
            metadataRow(title: "tvMode.detail.developer", value: rom.metadata?.developer)
            metadataRow(title: "tvMode.detail.publisher", value: rom.metadata?.publisher)
            metadataRow(title: "tvMode.detail.genre", value: rom.metadata?.genre.map { GenreManager.shared.effectiveDisplayName(for: $0) })
            metadataRow(title: "tvMode.detail.players", value: playerDescription)
            metadataRow(title: "tvMode.detail.played", value: String(rom.timesPlayed))
            metadataRow(title: "tvMode.detail.playtime", value: playtimeDescription)
            metadataRow(title: "tvMode.detail.lastPlayed", value: rom.lastPlayed != nil ? formatLastPlayed(rom.lastPlayed!) : nil)
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if let desc = rom.metadata?.description, !desc.isEmpty {
            ScrollView {
                Text(desc)
                    .font(.system(size: 14 * scale))
                    .foregroundStyle(theme == .bold ? AppColors.textPrimary(colorScheme).opacity(0.85) : .primary.opacity(0.85))
                    .lineSpacing(1.6)
            }
            .frame(maxHeight: 140 * scale)
        }
    }

    @ViewBuilder
    private func metadataRow(title: String, value: String?) -> some View {
        if let v = value, !v.isEmpty {
            HStack {
                Text(loc.localized(title))
                    .font(.system(size: 12 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer().frame(width: 12 * scale)
                Text(v)
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(theme == .bold ? AppColors.textPrimary(colorScheme) : .primary)
            }
        }
    }

    private var playerDescription: String? {
        guard let p = rom.metadata?.players, p > 0 else { return nil }
        return "\(p)"
    }

    private var playtimeDescription: String {
        let total = Int(rom.totalPlaytimeSeconds)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        if mins > 0 { return "\(mins)m" }
        return "\(total)s"
    }

    private func formatLastPlayed(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    // MARK: - Art

    private func resetArt() {
        boxart = nil
        titleImage = nil
        snaps = []
        selectedSnapIndex = 0
        downloading = false
    }

    private func loadArt() {
        downloading = true
        if rom.hasBoxArt {
            boxart = ImageCache.shared.thumbnailSync(for: rom.boxArtLocalPath, preferredSize: .large)
        }
        if rom.hasTitleScreen {
            titleImage = ImageCache.shared.thumbnailSync(for: rom.titleScreenLocalPath, preferredSize: .large)
        }
        for path in rom.screenshotPaths.prefix(4) {
            if let img = ImageCache.shared.thumbnailSync(for: path, preferredSize: .medium) {
                snaps.append(img)
            } else {
                Task {
                    if let img = await ImageCache.shared.image(for: path) {
                        await MainActor.run {
                            snaps.append(img)
                            if selectedSnapIndex >= snaps.count { selectedSnapIndex = 0 }
                        }
                    }
                }
            }
        }
        Task {
            async let titleTask = BoxArtService.shared.downloadTitleScreen(for: rom)
            async let snapTask = BoxArtService.shared.downloadScreenshots(for: rom)
            _ = await (titleTask, snapTask)
            await MainActor.run {
                if rom.hasBoxArt, boxart == nil {
                    boxart = ImageCache.shared.thumbnailSync(for: rom.boxArtLocalPath, preferredSize: .large)
                }
                if rom.hasTitleScreen, titleImage == nil {
                    titleImage = ImageCache.shared.thumbnailSync(for: rom.titleScreenLocalPath, preferredSize: .large)
                }
                // Reload snaps after the async fetch since the ROM's URL paths
                // may now be populated on disk.
                snaps.removeAll()
                for path in rom.screenshotPaths.prefix(4) {
                    if let img = ImageCache.shared.thumbnailSync(for: path, preferredSize: .medium) {
                        snaps.append(img)
                    } else {
                        Task {
                            if let img = await ImageCache.shared.image(for: path) {
                                await MainActor.run {
                                    snaps.append(img)
                                    if selectedSnapIndex >= snaps.count { selectedSnapIndex = max(0, snaps.count - 1) }
                                }
                            }
                        }
                    }
                }
                downloading = false
            }
        }
    }
}
