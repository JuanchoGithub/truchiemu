import SwiftUI

// Optimized game card view for the library grid.
// Simplified image loading path for fast scroll performance.
struct GameCardView: View {
    let rom: ROM
    let isSelected: Bool
    let isMultiSelected: Bool
    let zoomLevel: Double
    let onTap: () -> Void
    var contextMenu: (() -> AnyView)?

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var mouseLocation: CGPoint = .zero
    @State private var image: NSImage?
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var prefs = SystemPreferences.shared
    @ObservedObject var dragState = GameDragState.shared
    @ObservedObject private var boxArtService = BoxArtService.shared
    @EnvironmentObject private var library: ROMLibrary
    @EnvironmentObject private var categoryManager: CategoryManager

    private var boxType: BoxType {
        prefs.boxType(for: rom.systemID ?? "")
    }

    private var titleFontSize: CGFloat {
        10 + zoomLevel * 6
    }

    private var titleLineHeight: CGFloat {
        titleFontSize * 1.2
    }

    private var categoryBadges: [GameCategory] {
        categoryManager.categories.filter { $0.gameIDs.contains(rom.id) }
    }

    private var isHiddenItem: Bool {
        rom.isHidden
    }

    // MARK: - Computed styling helpers

    private var artworkGrayscale: Double {
        isHiddenItem ? 0.85 : (isHovered ? 0.05 : 0)
    }

    private var artworkOpacity: Double {
        isHiddenItem ? 0.55 : 1
    }

    private var cardBackground: Color {
        if isSelected { return AppColors.brandAccentSecondary.opacity(0.15) }
        if isHiddenItem { return Color.gray.opacity(0.08) }
        return (isHovered || isPressed) ? AppColors.brandAccentSecondary.opacity(0.06) : .clear
    }

    private var cardStrokeColor: Color {
        if isSelected { return AppColors.brandAccentSecondary }
        if isHiddenItem { return Color.gray.opacity(0.3) }
        return isHovered ? AppColors.brandAccentSecondary.opacity(0.25) : .clear
    }

    private var cardStrokeWidth: CGFloat {
        isHiddenItem ? 1 : (isSelected || isHovered ? 1.5 : 0)
    }

    private var titleColor: Color {
        isHiddenItem ? .gray : AppColors.textPrimary(colorScheme)
    }

    private var parallaxRotation: (x: Double, y: Double) {
        guard isHovered, mouseLocation != .zero else { return (0, 0) }
        let cardWidth: CGFloat = 180
        let cardHeight: CGFloat = 240
        let nx = (mouseLocation.x - cardWidth / 2) / (cardWidth / 2)
        let ny = (mouseLocation.y - cardHeight / 2) / (cardHeight / 2)
        return (-ny * 2.5, nx * 2.5)
    }

    var body: some View {
        Button(action: onTap) {
            cardContent
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(AppMotion.feedback, value: isPressed)
        }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .onContinuousHover { phase in
        switch phase {
        case .active(let location):
            mouseLocation = location
        case .ended:
            mouseLocation = .zero
        }
    }
    .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .contextMenu {
            contextMenu?()
        }
        .animation(AppMotion.micro, value: isHovered)
        .accessibilityLabel(rom.displayName)
        .accessibilityAddTraits(.isButton)
        .task(id: "\(rom.id)-\(boxArtService.boxArtUpdated)") {
            var artPath = rom.boxArtLocalPath
            if !FileManager.default.fileExists(atPath: artPath.path) {
                if let resolved = BoxArtService.shared.resolveLocalBoxArt(for: rom) {
                    artPath = resolved
                }
            }

            if let img = await ImageCache.shared.thumbnail(for: artPath) {
                self.image = img
                await MainActor.run {
                    if !rom.hasBoxArt {
                        var updated = rom
                        updated.hasBoxArt = true
                        library.updateROM(updated, persist: false, silent: true)
                    }
                }
            } else {
                await MainActor.run {
                    if rom.hasBoxArt {
                        var updated = rom
                        updated.hasBoxArt = false
                        library.updateROM(updated, persist: false, silent: true)
                    }
                    self.image = nil
                }
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                artworkView
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(isHovered ? 0.08 : 0))
                    )
                    .grayscale(artworkGrayscale)
                    .opacity(artworkOpacity)

                if isMultiSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(AppColors.brandAccent)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .padding(4)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(rom.displayName)
                    .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(titleColor)
                    .frame(minHeight: titleLineHeight * 2, alignment: .top)

                if isHiddenItem, let mameType = rom.mameRomType {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                        Text(mameType.capitalized)
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                }
            }

            if !categoryBadges.isEmpty {
                CategoryBadgesRow(badges: categoryBadges)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        )
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.brandAccentSecondary.opacity(0.4), lineWidth: 1.5)
                        .shadow(color: AppColors.brandAccentSecondary.opacity(0.35), radius: 4)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(cardStrokeColor, lineWidth: cardStrokeWidth)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(colorScheme == .dark ? 0.12 : 0.05)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        )
        .shadow(
            color: isSelected ? AppColors.brandAccentSecondary.opacity(0.25) : (isHovered ? AppColors.brandAccentSecondary.opacity(0.2) : .clear),
            radius: isSelected ? 8 : (isHovered ? 14 : 0),
            y: isSelected ? 0 : (isHovered ? 8 : 0)
        )
        .offset(y: isHovered ? -4 : 0)
        .rotation3DEffect(
            .degrees(parallaxRotation.y),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.3
        )
        .rotation3DEffect(
            .degrees(parallaxRotation.x),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.3
        )
        .animation(.interpolatingSpring(stiffness: 200, damping: 20), value: mouseLocation)
    }

    private var artworkView: some View {
        GeometryReader { geometry in
            ZStack {
                if let nsImage = image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(isHovered ? 1.05 : 1)
                        .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: isHovered)
                } else {
                    placeholderArt
                         .scaleEffect(isHovered ? 1.02 : 1)
                         .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: isHovered)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(boxType.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.25), radius: isHovered ? 8 : 4, x: 0, y: isHovered ? 4 : 2)
    }

    private var placeholderArt: some View {
        ZStack {
            systemArtGradient
            VStack(spacing: 8) {
                if let sys = SystemDatabase.system(forID: rom.systemID ?? ""),
                   let img = sys.emuImage(size: 600) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } else {
                    Image(systemName: systemIcon)
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.8))
                }

                Text(rom.displayName)
                    .font(.system(size: titleFontSize * 0.8))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var systemIcon: String {
        SystemDatabase.system(forID: rom.systemID ?? "")?.iconName ?? "gamecontroller"
    }

    private var systemArtGradient: LinearGradient {
        let palette: [(Color, Color)] = [
            (Color(hue: 0.08, saturation: 0.55, brightness: 0.75), Color(hue: 0.06, saturation: 0.40, brightness: 0.55)),
            (Color(hue: 0.04, saturation: 0.50, brightness: 0.70), Color(hue: 0.03, saturation: 0.35, brightness: 0.50)),
            (Color(hue: 0.12, saturation: 0.50, brightness: 0.80), Color(hue: 0.10, saturation: 0.35, brightness: 0.60)),
            (Color(hue: 0.02, saturation: 0.55, brightness: 0.65), Color(hue: 0.01, saturation: 0.40, brightness: 0.45)),
            (Color(hue: 0.14, saturation: 0.45, brightness: 0.85), Color(hue: 0.12, saturation: 0.30, brightness: 0.65)),
            (Color(hue: 0.06, saturation: 0.55, brightness: 0.72), Color(hue: 0.05, saturation: 0.40, brightness: 0.52)),
            (Color(hue: 0.10, saturation: 0.45, brightness: 0.78), Color(hue: 0.08, saturation: 0.30, brightness: 0.58)),
            (Color(hue: 0.11, saturation: 0.50, brightness: 0.82), Color(hue: 0.09, saturation: 0.35, brightness: 0.62)),
        ]
        let hash = abs((rom.systemID ?? "x").hashValue)
        let colors = palette[hash % palette.count]
        return LinearGradient(colors: [colors.0.opacity(0.7), colors.1.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - On-Demand Box Art Resolution

extension GameCardView {
    nonisolated static func resolveBoxArtOnDemand(for rom: ROM) async -> URL? {
        let artPath = rom.boxArtLocalPath
        if FileManager.default.fileExists(atPath: artPath.path) {
            return artPath
        }
        return nil
    }
}

// MARK: - Support Views



struct CategoryBadgesRow: View {
  let badges: [GameCategory]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(badges) { category in
        CategoryBadgeView(category: category, isCompact: badges.count > 1)
      }
    }
  }
}
