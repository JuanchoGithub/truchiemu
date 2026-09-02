import SwiftUI
import AppKit

/// Page 2 in TV mode: detailed view of a single game.
/// Shows hero boxart, title screen (if any), up to 4 snaps, metadata, and a
/// launch hint. Title screen and snaps are downloaded on demand.
struct TVModeGameDetailView: View {
    let rom: ROM
    let theme: TVModeSettings.Theme
    let focused: Bool
    /// Most recent save slot for this ROM (computed by `TVModeViewModel`),
    /// or `nil` when no save state exists. Drives the Continue/Play hint
    /// below the title: when non-nil, pressing A on the gamepad loads the
    /// save (mirrors the desktop `Continue` button); Y launches fresh.
    var mostRecentSaveSlot: SlotInfo?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tvModeScale) private var scale
    @EnvironmentObject private var library: ROMLibrary
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var boxart: NSImage?
    @State private var titleImage: NSImage?
    @State private var snaps: [NSImage] = []
    @State private var selectedSnapIndex: Int = 0
    @State private var downloading: Bool = false

    var body: some View {
        HStack(spacing: 32 * scale) {
            heroColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            infoColumn
                .frame(width: 440 * scale, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(40 * scale)
        .onAppear { loadArt() }
        .onChange(of: rom.id) { _, _ in resetArt(); loadArt() }
    }

    /// The game's declared boxart layout (vertical / box / landscape). Drives
    /// the container aspect ratio when the image hasn't resolved yet, mirroring
    /// the flat move-list tiles in `TVModeGameTile`.
    private var boxType: BoxType {
        SystemPreferences.shared.boxType(for: rom.systemID ?? "")
    }

    /// Aspect ratio of the hero art. Falls back to the system's `BoxType` while
    /// the image is still loading so the container never flashes a wrong-ratio
    /// frame.
    private var heroAspect: CGFloat {
        if let img = boxart ?? titleImage, img.size.width > 0, img.size.height > 0 {
            return img.size.width / img.size.height
        }
        return boxType.aspectRatio
    }

    /// Fits the hero art into `available` while preserving its aspect ratio.
    private func heroSize(in available: CGSize) -> CGSize {
        let byHeight = CGSize(width: available.height * heroAspect, height: available.height)
        if byHeight.width <= available.width {
            return byHeight
        }
        return CGSize(width: available.width, height: available.width / heroAspect)
    }

    /// Corner radius follows the art's own proportions, matching the move-list
    /// tiles so portrait covers stay moderately rounded and landscape covers get
    /// a shallower arc.
    private func heroCornerRadius(for size: CGSize) -> CGFloat {
        let base = min(size.width, size.height) * 0.07
        return min(max(base, 6 * scale), 22 * scale)
    }

    @ViewBuilder
    private var heroColumn: some View {
        VStack(alignment: .center, spacing: 16 * scale) {
            GeometryReader { geo in
                let size = heroSize(in: geo.size)
                let radius = heroCornerRadius(for: size)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if let img = boxart ?? titleImage {
                        // Auto holo on the selected game's hero boxart — always on,
                        // using the user's weighted random variant, with the
                        // wizard-style self-driven light + card motion. No border
                        // or backing fill: just the art clipped to rounded corners.
                        TVModeHoloBoxart(
                            image: img,
                            romID: rom.id.uuidString,
                            cornerRadius: radius,
                            showBackingFill: false
                        )
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Color.gray.opacity(0.18))
                            .frame(width: size.width, height: size.height)
                    }
                    Spacer(minLength: 0)
                }
            }

            Text(rom.displayName)
                .font(.system(size: 26 * scale, weight: .bold))
                .foregroundStyle(theme == .bold ? AppColors.textPrimary(colorScheme) : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Render the launch affordance. There are two states:
            //
            // 1. No save state exists — a single chip reading "Press A to Play"
            //    matches the original behaviour.
            // 2. A save state exists — the primary chip becomes "Continue — {date}"
            //    (bound to A) and a smaller secondary chip announces "Y to Play
            //    from start" so the couch user can establish a fresh game even
            //    when continuing is the default. Without the secondary hint,
            //    the user has no signal that pressing Y also exists as a path.
            if let slot = mostRecentSaveSlot, slot.exists {
                Text(continueLabel(for: slot))
                    .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18 * scale).padding(.vertical, 8 * scale)
                    .background(
                        Capsule().fill(theme == .bold ? AppColors.accentForScheme(colorScheme).opacity(0.25) : Color.gray.opacity(0.2))
                    )
                    .overlay(Capsule().strokeBorder(theme == .bold ? AppColors.accentForScheme(colorScheme) : Color.white.opacity(0.4), lineWidth: 1 * scale))

                Text(loc.localized("tvMode.detail.playFromStart"))
                    .font(.system(size: 12 * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14 * scale).padding(.vertical, 6 * scale)
                    .background(
                        Capsule().fill(Color.gray.opacity(0.15))
                    )
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1 * scale))
            } else {
                Text("tvMode.detail.launch")
                    .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18 * scale).padding(.vertical, 8 * scale)
                    .background(
                        Capsule().fill(theme == .bold ? AppColors.accentForScheme(colorScheme).opacity(0.25) : Color.gray.opacity(0.2))
                    )
                    .overlay(Capsule().strokeBorder(theme == .bold ? AppColors.accentForScheme(colorScheme) : Color.white.opacity(0.4), lineWidth: 1 * scale))
            }
        }
    }

    @ViewBuilder
    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 22 * scale) {
            snapsSection
            metadataSection
            descriptionSection
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
            .frame(maxHeight: .infinity, alignment: .topLeading)
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

    /// Localized "Continue — {date}" label for the launch hint. Reuses the
    /// existing `gameDetail.continueDate` placeholder so the date formatter
    /// matches what `Header.continueButton` produces on the desktop detail
    /// page — users coming from desktop to TV-mode should see the same string.
    private func continueLabel(for slot: SlotInfo) -> String {
        let template = loc.localized("gameDetail.continueDate")
        if let date = slot.modificationDate {
            let relative = GameDetailView.relativeDateFormatter
                .localizedString(for: date, relativeTo: Date())
            return template.replacingOccurrences(of: "{date}", with: relative)
        }
        return loc.localized("header.continue")
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
