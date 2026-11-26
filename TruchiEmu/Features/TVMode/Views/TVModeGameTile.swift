import SwiftUI
import AppKit

/// Compact box art poster in the games rail. No caption: the hero stage
/// carries the selected game's title, so the rail stays clean and shows more
/// art per screen.
///
/// The art keeps its own aspect (SNES/Genesis/DOS landscape covers are not
/// crammed into a portrait canvas) and is centred inside the rail slot. Focus
/// adds a thin accent ring and a soft halo whose size follows the art, not the
/// slot.
struct TVModeGameTile: View {
    let rom: ROM
    /// Center focus from `1` (exact center) to `0` (one slot away or row not
    /// active). Applied with NO animation modifier: motion comes from the row
    /// sweep itself.
    let focus: CGFloat
    let theme: TVModeSettings.Theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tvModeScale) private var scale
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            let palette = TVModePalette(theme: theme, colorScheme: colorScheme)
            let size = fittedSize(in: geo.size)
            let radius = cornerRadius(for: size)

            ZStack {
                if let img = image {
                    // Base art stays mounted; the holo stack (masked blend
                    // layers + a 20 Hz timeline) only mounts for the tile near
                    // the center, fading in over the base. Without this gate
                    // every visible tile kept a static holo stack alive, so the
                    // whole bottom bar re-composited a dozen foil layers on each
                    // systems-row step — the fast up/down sweep crawled.
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

                    if focus > 0.05 {
                        TVModeHoloBoxart(
                            image: img,
                            romID: rom.id.uuidString,
                            cornerRadius: radius,
                            showBackingFill: true
                        )
                        .opacity(min(1, focus * 3))
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    }
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(palette.panelFill)
                        .overlay(
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 22 * scale))
                                .foregroundStyle(palette.textTertiary)
                        )
                        .frame(width: size.width, height: size.height)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(palette.focusRing, lineWidth: 2 * scale)
                    .opacity(focus)
            )
            .shadow(
                color: palette.shadow.opacity(0.55 + 0.45 * focus),
                radius: (7 + 16 * focus) * scale,
                y: (3 + 7 * focus) * scale
            )
            .shadow(
                color: palette.accent.opacity(0.50 * focus),
                radius: 30 * scale
            )
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onAppear { preloadImage() }
        .onChange(of: rom.id) { _, _ in preloadImage() }
    }

    private var imageAspect: CGFloat {
        if let img = image, img.size.width > 0, img.size.height > 0 {
            return img.size.width / img.size.height
        }
        let boxType = SystemPreferences.shared.boxType(for: rom.systemID ?? "")
        return boxType.aspectRatio
    }

    /// Largest rect with the cover's aspect that fits the rail slot.
    private func fittedSize(in available: CGSize) -> CGSize {
        let aspect = imageAspect
        guard aspect > 0, available.width > 0, available.height > 0 else { return available }
        let byHeight = CGSize(width: available.height * aspect, height: available.height)
        if byHeight.width <= available.width { return byHeight }
        return CGSize(width: available.width, height: available.width / aspect)
    }

    /// Corner radius scales with the actual image dimensions, so portrait
    /// covers keep moderately rounded corners and landscape covers get a
    /// proportionally shallower arc.
    private func cornerRadius(for size: CGSize) -> CGFloat {
        let base = min(size.width, size.height) * 0.06
        return min(max(base, 5 * scale), 18 * scale)
    }

    private func preloadImage() {
        let thumb = BoxArtThumbnailSize.medium
        guard rom.hasBoxArt else { image = nil; return }
        // Memory-only peek. `thumbnailSync` would decode the source image on
        // the main thread on a cache miss, which shows up as a multi-hundred-
        // millisecond UI stall per cold tile. A miss here shows the placeholder
        // for one frame and is filled asynchronously.
        if let cached = ImageCache.shared.thumbnailCachedOrPregen(for: rom.boxArtLocalPath, preferredSize: thumb) {
            image = cached
            return
        }
        Task {
            if let nsImage = await ImageCache.shared.thumbnail(for: rom.boxArtLocalPath, preferredSize: thumb) {
                await MainActor.run { self.image = nsImage }
            }
        }
    }
}
