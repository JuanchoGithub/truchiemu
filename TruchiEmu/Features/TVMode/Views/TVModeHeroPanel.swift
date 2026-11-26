import SwiftUI
import AppKit

/// Cinematic stage in the middle of TV mode: the focused game's box art on the
/// left, an editorial info column on the right (title, metadata chips, a short
/// description and the current button affordances).
///
/// The stage always previews the selected game of the focused system, so
/// browsing systems keeps the screen alive instead of showing an empty centre.
struct TVModeHeroPanel: View {
    let rom: ROM?
    let page: TVModeViewModel.Page
    let theme: TVModeSettings.Theme
    let emptyMessage: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tvModeScale) private var scale
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        GeometryReader { geo in
            let palette = TVModePalette(theme: theme, colorScheme: colorScheme)
            if let rom {
                let hero = heroSize(in: geo.size, aspect: boxAspect(for: rom))
                HStack(alignment: .center, spacing: 44 * scale) {
                    TVModeHeroArt(
                        rom: rom,
                        size: hero,
                        theme: theme,
                        animate: page == .row2
                    )
                    infoColumn(rom: rom, palette: palette)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                emptyState(palette: palette)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Hero sizing

    private func boxAspect(for rom: ROM) -> CGFloat {
        let boxType = SystemPreferences.shared.boxType(for: rom.systemID ?? "")
        return boxType.aspectRatio
    }

    /// Fits the cover's declared aspect inside the stage. The hero takes at
    /// most 38% of the stage width so the info column always has room.
    private func heroSize(in available: CGSize, aspect: CGFloat) -> CGSize {
        let maxWidth = available.width * 0.38
        let maxHeight = available.height
        let byHeight = CGSize(width: maxHeight * aspect, height: maxHeight)
        if byHeight.width <= maxWidth { return byHeight }
        return CGSize(width: maxWidth, height: maxWidth / aspect)
    }

    // MARK: - Info column

    private func infoColumn(rom: ROM, palette: TVModePalette) -> some View {
        VStack(alignment: .leading, spacing: 16 * scale) {
            Text(verbatim: systemName(for: rom).uppercased())
                .font(.system(size: 11 * scale, weight: .bold))
                .tracking(2.2 * scale)
                .foregroundStyle(palette.accent)

            Text(verbatim: rom.displayName)
                .font(.system(size: 40 * scale, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)

            metaChips(rom: rom, palette: palette)

            if let description = rom.metadata?.description, !description.isEmpty {
                Text(verbatim: description)
                    .font(.system(size: 14 * scale))
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(2.5 * scale)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionRow(palette: palette)
                .padding(.top, 4 * scale)
        }
    }

    private func systemName(for rom: ROM) -> String {
        SystemDatabase.system(forID: rom.systemID ?? "")?.sidebarDisplayName
            ?? loc.localized("tvMode.page.games")
    }

    @ViewBuilder
    private func metaChips(rom: ROM, palette: TVModePalette) -> some View {
        let genre = rom.metadata?.genre.map { GenreManager.shared.effectiveDisplayName(for: $0) }
        let players = rom.metadata?.players
        let playtime = playtimeLabel(rom)

        let hasAny = rom.metadata?.year != nil
            || genre != nil
            || (players ?? 0) > 0
            || playtime != nil
        if hasAny {
            HStack(spacing: 8 * scale) {
                if let year = rom.metadata?.year, !year.isEmpty {
                    chip(text: year, palette: palette)
                }
                if let genre, !genre.isEmpty {
                    chip(text: genre, palette: palette)
                }
                if let players, players > 0 {
                    chip(text: "\(players)", systemImage: "person.2.fill", palette: palette)
                }
                if let playtime {
                    chip(text: playtime, systemImage: "clock.fill", palette: palette)
                }
            }
        }
    }

    private func chip(text: String, systemImage: String? = nil, palette: TVModePalette) -> some View {
        HStack(spacing: 5 * scale) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(verbatim: text)
                .font(.system(size: 11 * scale, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 5 * scale)
        .background(Capsule().fill(palette.panelFill))
        .overlay(Capsule().strokeBorder(palette.panelStroke, lineWidth: 1 * scale))
    }

    private func actionRow(palette: TVModePalette) -> some View {
        HStack(spacing: 10 * scale) {
            switch page {
            case .row1:
                actionChip(glyph: "A", label: loc.localized("tvMode.hint.open"), primary: true, palette: palette)
                actionChip(glyph: "→", label: loc.localized("tvMode.hint.games"), primary: false, palette: palette)
            case .row2:
                actionChip(glyph: "A", label: loc.localized("header.play"), primary: true, palette: palette)
                actionChip(glyph: "↓", label: loc.localized("tvMode.hint.details"), primary: false, palette: palette)
            case .detail:
                EmptyView()
            }
            actionChip(glyph: "Y", label: loc.localized("app.settings"), primary: false, palette: palette)
        }
    }

    private func actionChip(glyph: String, label: String, primary: Bool, palette: TVModePalette) -> some View {
        HStack(spacing: 8 * scale) {
            Text(verbatim: glyph)
                .font(.system(size: 10 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(primary ? AppColors.textOnAccent(for: palette.accent, colorScheme: colorScheme) : palette.textPrimary)
                .frame(width: 20 * scale, height: 20 * scale)
                .background(Circle().fill(primary ? palette.accent : palette.panelFillStrong))
            Text(verbatim: label)
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(primary ? palette.textPrimary : palette.textSecondary)
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 7 * scale)
        .background(Capsule().fill(primary ? palette.actionFill : palette.panelFill))
        .overlay(
            Capsule().strokeBorder(
                primary ? palette.accent.opacity(0.55) : palette.panelStroke,
                lineWidth: 1 * scale
            )
        )
    }

    private func emptyState(palette: TVModePalette) -> some View {
        VStack(spacing: 14 * scale) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 38 * scale, weight: .light))
                .foregroundStyle(palette.textTertiary)
            Text(verbatim: emptyMessage)
                .font(.system(size: 16 * scale, weight: .medium))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func playtimeLabel(_ rom: ROM) -> String? {
        let total = Int(rom.totalPlaytimeSeconds)
        guard total >= 60 else { return nil }
        let hours = total / 3600
        let mins = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}

// MARK: - Hero art

/// Large holo box art with a debounced high-resolution upgrade.
///
/// While the user flies through systems or games, the hero keeps showing the
/// last resolved cover and only touches disk for a full-size decode once the
/// selection has been quiet for a moment. The immediate pass reads the
/// in-memory thumbnail cache only (usually already warm from the poster rail),
/// so a fast sweep never decodes on the main thread.
private struct TVModeHeroArt: View {
    let rom: ROM
    let size: CGSize
    let theme: TVModeSettings.Theme
    let animate: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tvModeScale) private var scale
    @State private var image: NSImage?

    private var cornerRadius: CGFloat {
        min(max(min(size.width, size.height) * 0.05, 8 * scale), 24 * scale)
    }

    private var artPath: URL? {
        if rom.hasBoxArt { return rom.boxArtLocalPath }
        if rom.hasTitleScreen { return rom.titleScreenLocalPath }
        return nil
    }

    var body: some View {
        let palette = TVModePalette(theme: theme, colorScheme: colorScheme)
        ZStack {
            if let image {
                TVModeHoloBoxart(
                    image: image,
                    romID: rom.id.uuidString,
                    cornerRadius: cornerRadius,
                    showBackingFill: false,
                    animate: animate
                )
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1 * scale)
                )
                .shadow(color: palette.shadow, radius: 30 * scale, y: 16 * scale)
                .shadow(
                    color: palette.accent.opacity(animate ? 0.30 : 0.12),
                    radius: 54 * scale
                )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.panelFill)
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 42 * scale))
                            .foregroundStyle(palette.textTertiary)
                    )
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(palette.panelStroke, lineWidth: 1 * scale)
                    )
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: rom.id) { await loadArt() }
    }

    @MainActor
    private func loadArt() async {
        guard let path = artPath else {
            image = nil
            return
        }
        // Immediate pass: memory only. The poster rail usually has this thumb
        // resident, so the hero tracks the selection without a disk read.
        if let cached = ImageCache.shared.thumbnailCachedOrPregen(for: path, preferredSize: .medium) {
            image = cached
        }

        // Quiet-period upgrade to a full-size cover.
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { return }
        if let large = ImageCache.shared.thumbnailSyncPregen(for: path, preferredSize: .large) {
            image = large
            return
        }
        if let large = await ImageCache.shared.thumbnail(for: path, preferredSize: .large) {
            guard !Task.isCancelled else { return }
            image = large
        }
    }
}
