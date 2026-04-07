import SwiftUI

/// Optimized game card view for the library grid.
/// Simplified image loading path for fast scroll performance.
struct GameCardView: View {
    let rom: ROM
    let isSelected: Bool
    let isMultiSelected: Bool
    let zoomLevel: Double

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var image: NSImage?
    @ObservedObject private var prefs = SystemPreferences.shared
    @EnvironmentObject private var library: ROMLibrary
    @EnvironmentObject private var categoryManager: CategoryManager

    private var boxType: BoxType {
        prefs.boxType(for: rom.systemID ?? "")
    }

    private var titleFontSize: CGFloat {
        10 + zoomLevel * 6
    }

    /// Approximate line height for the title font (font size + leading)
    private var titleLineHeight: CGFloat {
        titleFontSize * 1.2
    }

    private var categoryBadges: [GameCategory] {
        categoryManager.categories.filter { $0.gameIDs.contains(rom.id) }
    }

    /// Whether this ROM is hidden (e.g., MAME BIOS, device, mechanical)
    private var isHiddenItem: Bool {
        rom.isHidden
    }

    // MARK: - Computed styling helpers (break up complex expressions for compiler)

    private var artworkGrayscale: Double {
        isHiddenItem ? 0.85 : (isHovered ? 0.05 : 0)
    }

    private var artworkOpacity: Double {
        isHiddenItem ? 0.55 : 1
    }

    private var cardBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.25) }
        if isHiddenItem { return Color.gray.opacity(0.08) }
        return isHovered ? Color.secondary.opacity(0.1) : .clear
    }

    private var cardStrokeColor: Color {
        if isSelected { return Color.accentColor }
        if isHiddenItem { return Color.gray.opacity(0.3) }
        return .clear
    }

    private var cardStrokeWidth: CGFloat {
        isHiddenItem ? 1 : 2
    }

    private var shadowColor: Color {
        if isHiddenItem { return .clear }
        if isHovered && !isSelected { return Color.accentColor.opacity(0.2) }
        return .clear
    }

    private var titleColor: Color {
        isHiddenItem ? .gray : .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                artworkView
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(isHovered ? 0.1 : 0))
                    )
                    .grayscale(artworkGrayscale)
                    .opacity(artworkOpacity)

                if isMultiSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .padding(4)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(rom.displayName)
                    .font(.system(size: titleFontSize, weight: .medium))
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
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardStrokeColor, lineWidth: cardStrokeWidth)
        )
        .shadow(
            color: isHovered ? Color.accentColor.opacity(0.15) : Color.black.opacity(0.3),
            radius: isHovered ? 12 : 6,
            y: isHovered ? 8 : 3
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .clipped()
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: isHovered)
        .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: isPressed)
        .accessibilityLabel(rom.displayName)
        .accessibilityAddTraits(.isButton)
        // Load box art: try multiple naming patterns via BoxArtService.
        // Sets hasBoxArt based on whether the image loads successfully.
        .task(id: rom.id) {
            // First try the deterministic path
            var artPath = rom.boxArtLocalPath
            
            // If that file doesn't exist, try the multi-stem resolution
            if !FileManager.default.fileExists(atPath: artPath.path) {
                if let resolved = BoxArtService.shared.resolveLocalBoxArt(for: rom) {
                    artPath = resolved
                }
            }

            if let img = await ImageCache.shared.image(for: artPath) {
                self.image = img
                await MainActor.run {
                    if !rom.hasBoxArt {
                        var updated = rom
                        updated.hasBoxArt = true
                        library.updateROM(updated)
                    }
                }
            } else {
                // Image not found or invalid — ensure hasBoxArt is false
                await MainActor.run {
                    if rom.hasBoxArt {
                        var updated = rom
                        updated.hasBoxArt = false
                        library.updateROM(updated)
                    }
                    self.image = nil
                }
            }
        }
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
        .shadow(color: Color.black.opacity(isHovered ? 0.4 : 0.3), radius: isHovered ? 10 : 6, x: 0, y: isHovered ? 5 : 3)
    }

    private var placeholderArt: some View {
        ZStack {
            LinearGradient(
                colors: [systemColor.opacity(0.6), systemColor.opacity(0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
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

    private var systemColor: Color {
        let colors: [Color] = [.purple, .blue, .cyan, .green, .orange, .red, .pink]
        let hash = abs((rom.systemID ?? "x").hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - On-Demand Box Art Resolution

extension GameCardView {
    /// Checks the deterministic box art path for local existence.
    /// Simplified since boxArtLocalPath is always computed the same way.
    nonisolated
    static func resolveBoxArtOnDemand(for rom: ROM) async -> URL? {
        let artPath = rom.boxArtLocalPath
        if FileManager.default.fileExists(atPath: artPath.path) {
            return artPath
        }
        return nil
    }
}

// MARK: - Category Badges Row

struct CategoryBadgesRow: View {
    let badges: [GameCategory]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(badges) { category in
                    CategoryBadgeView(category: category)
                }
            }
        }
    }
}