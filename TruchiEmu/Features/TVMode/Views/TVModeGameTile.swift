import SwiftUI
import AppKit

/// Flat boxart tile shown in row 2 (games). Larger than row-1 system tiles.
/// Focused state scales up slightly and adds a glowing accent ring.
struct TVModeGameTile: View {
    let rom: ROM
    let isFocused: Bool
    let theme: TVModeSettings.Theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?

    private let width: CGFloat = 180
    private let height: CGFloat = heightFor(width: 180, aspect: 3.0 / 4.0)

    private static func heightFor(width: CGFloat, aspect: CGFloat) -> CGFloat {
        width / aspect
    }

    var body: some View {
        VStack(spacing: 8) {
            boxartView
                .frame(width: width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isFocused ? (theme == .bold ? AppColors.accentForScheme(colorScheme) : Color.white) : Color.white.opacity(0.08),
                            lineWidth: isFocused ? 3 : 1
                        )
                )
                .shadow(color: shadowColor, radius: isFocused ? 22 : 4, y: isFocused ? 10 : 2)
                .scaleEffect(isFocused ? 1.0 : 0.92)
                .animation(.easeOut(duration: 0.22), value: isFocused)

            Text(rom.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme == .bold ? AppColors.textPrimary(colorScheme) : .primary)
                .lineLimit(1)
                .frame(width: width + 40)
        }
        .onAppear { preloadImage() }
        .onChange(of: rom.id) { _, _ in preloadImage() }
    }

    @ViewBuilder
    private var boxartView: some View {
        if let img = image {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            // Placeholder: dark rounded rect with a small game icon.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme == .bold ? AppColors.cardBackground(colorScheme).opacity(0.4) : Color.gray.opacity(0.15))
                .overlay(
                    Image(systemName: "gamecontroller.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(40)
                        .foregroundStyle(.white.opacity(0.25))
                )
        }
    }

    private var shadowColor: Color {
        if theme == .bold {
            return AppColors.accentForScheme(colorScheme).opacity(isFocused ? 0.45 : 0.0)
        } else {
            return .black.opacity(isFocused ? 0.5 : 0.2)
        }
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
