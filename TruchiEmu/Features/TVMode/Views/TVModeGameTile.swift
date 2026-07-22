import SwiftUI
import AppKit

/// Flat boxart tile shown in row 2 (games). Sized to the actual boxart
/// aspect (loaded from the image or, failing that, the system `BoxType`) so
/// SNES/Genesis/DOS landscape covers aren't crammed into a portrait canvas.
/// Focused state scales up by 30% and gains a soft accent halo whose size
/// follows the tile's own bounds — not a fixed rectangle.
struct TVModeGameTile: View {
    let rom: ROM
    let isFocused: Bool
    let theme: TVModeSettings.Theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?

    private static let preferredWidth: CGFloat = 160

    var body: some View {
        VStack(spacing: 8) {
            tileContent
                .overlay(
                    RoundedRectangle(cornerRadius: boxCornerRadius, style: .continuous)
                        .strokeBorder(
                            isFocused ? (theme == .bold ? AppColors.accentForScheme(colorScheme) : Color.white) : Color.white.opacity(0.08),
                            lineWidth: isFocused ? 3 : 1
                        )
                )
                .scaleEffect(isFocused ? 1.30 : 1.0, anchor: .bottom)
                .animation(.easeOut(duration: 0.22), value: isFocused)

            Text(rom.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme == .bold ? AppColors.textPrimary(colorScheme) : .primary)
                .lineLimit(1)
                .frame(width: imageDisplaySize.width + 40)
        }
        .onAppear { preloadImage() }
        .onChange(of: rom.id) { _, _ in preloadImage() }
    }

    /// Aspect ratio of the displayed image. Falls back to the system's
    /// declared `BoxType` when the image hasn't loaded yet (avoiding a
    /// transient portrait flash before the cover arrives).
    private var imageAspect: CGFloat {
        if let img = image, img.size.width > 0, img.size.height > 0 {
            return img.size.width / img.size.height
        }
        let boxType = SystemPreferences.shared.boxType(for: rom.systemID ?? "")
        return boxType.aspectRatio
    }

    /// Width of the loaded cover at our preferred display width. Landscape /
    /// box / portrait boxart keep its own aspect — no more 3:4 squashing.
    private var imageDisplaySize: CGSize {
        let aspect = imageAspect
        let width = Self.preferredWidth
        return CGSize(width: width, height: width / aspect)
    }

    /// Corner radius scales with the actual image dimensions, so portrait
    /// covers keep moderately rounded corners and landscape covers get a
    /// proportionally shallower arc.
    private var boxCornerRadius: CGFloat {
        let size = imageDisplaySize
        let base = min(size.width, size.height) * 0.07
        return min(max(base, 6), 22)
    }

    @ViewBuilder
    private var tileContent: some View {
        ZStack {
            // Subtle background fill that shows through any letterboxing the
            // image doesn't cover, plus shadows live behind it.
            RoundedRectangle(cornerRadius: boxCornerRadius, style: .continuous)
                .fill(boxBackground)
                .shadow(color: shadowColor, radius: isFocused ? 28 : 5, y: isFocused ? 12 : 2)

            boxartView
                .frame(width: imageDisplaySize.width, height: imageDisplaySize.height)
                .clipShape(RoundedRectangle(cornerRadius: boxCornerRadius, style: .continuous))

            // Halo behind the tile — sized to the tile, not a fixed box, so
            // each cover's accent glow matches its own proportions.
            if isFocused {
                RoundedRectangle(cornerRadius: boxCornerRadius + 10, style: .continuous)
                    .fill(haloColor)
                    .blur(radius: 32)
                    .opacity(0.55)
                    .padding(-18)
                    .frame(
                        width: imageDisplaySize.width + 36,
                        height: imageDisplaySize.height + 36
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(
            width: imageDisplaySize.width + (isFocused ? 36 : 0),
            height: imageDisplaySize.height + (isFocused ? 36 : 0)
        )
    }

    @ViewBuilder
    private var boxartView: some View {
        if let img = image {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            // Placeholder: dark rounded rect with a small game icon.
            RoundedRectangle(cornerRadius: boxCornerRadius - 2, style: .continuous)
                .fill(boxBackground)
                .overlay(
                    Image(systemName: "gamecontroller.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(imageDisplaySize.width * 0.18)
                        .foregroundStyle(.white.opacity(0.25))
                )
        }
    }

    private var boxBackground: Color {
        if theme == .bold {
            return AppColors.cardBackground(colorScheme).opacity(0.4)
        }
        return Color.gray.opacity(0.15)
    }

    private var shadowColor: Color {
        if theme == .bold {
            return AppColors.accentForScheme(colorScheme).opacity(isFocused ? 0.45 : 0.0)
        }
        return .black.opacity(isFocused ? 0.5 : 0.2)
    }

    private var haloColor: Color {
        if theme == .bold {
            return AppColors.accentForScheme(colorScheme).opacity(0.6)
        }
        return Color.white.opacity(0.35)
    }

    private func preloadImage() {
        let thumb = BoxArtThumbnailSize.medium
        if rom.hasBoxArt {
            image = ImageCache.shared.thumbnailSync(for: rom.boxArtLocalPath, preferredSize: thumb)
        }
        if image == nil {
            Task {
                if let nsImage = await ImageCache.shared.image(for: rom.boxArtLocalPath) {
                    await MainActor.run { self.image = nsImage }
                }
            }
        }
    }
}
