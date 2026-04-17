import SwiftUI

/// Optimized game card view for the library grid.
/// Simplified image loading path for fast scroll performance.
struct GameCardView: View {
    let rom: ROM
    let isSelected: Bool
    let isMultiSelected: Bool
    let zoomLevel: Double
    var draggedROMs: [ROM] = [] // NEW: Provides context for the multi-item drag stack
    let onTap: () -> Void 
    var contextMenu: (() -> AnyView)?
    var onDrag: (() -> NSItemProvider?)? 

    @State private var isHovered = false
    @State private var image: NSImage?
    @ObservedObject private var prefs = SystemPreferences.shared
    @ObservedObject var dragState = GameDragState.shared
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
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(CardButtonStyle())
        .onHover { isHovered = $0 }
        .contextMenu {
            contextMenu?()
        }
        .onDrag {
            return onDrag?() ?? NSItemProvider()
        } preview: {
            // The animated drag stack, passing the fully loaded image synchronously
            DragPreviewStack(
                mainROM: rom,
                mainImage: self.image,
                draggedROMs: draggedROMs.filter { $0.id != rom.id },
                zoomLevel: zoomLevel
            )
        }
        .animation(.spring(), value: isHovered)
        .accessibilityLabel(rom.displayName)
        .accessibilityAddTraits(.isButton)
        .task(id: rom.id) {
            var artPath = rom.boxArtLocalPath
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
                colors:[systemColor.opacity(0.6), systemColor.opacity(0.3)],
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
    nonisolated static func resolveBoxArtOnDemand(for rom: ROM) async -> URL? {
        let artPath = rom.boxArtLocalPath
        if FileManager.default.fileExists(atPath: artPath.path) {
            return artPath
        }
        return nil
    }
}

// MARK: - Support Views

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(), value: configuration.isPressed)
    }
}

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

// MARK: - Animated Drag Preview stack

struct DragPreviewStack: View {
    let mainROM: ROM
    let mainImage: NSImage?
    let draggedROMs: [ROM]
    let zoomLevel: Double
    
    @State private var isAnimating = false
    
    var body: some View {
        let cardWidth = 80 + (zoomLevel * 200)
        let boxSize = cardWidth + 50 // Fixed bounding box to prevent macOS from trimming
        
        ZStack {
            // Invisible background locks the bounding box size
            // macOS trims purely transparent pixels. Opacity 0.01 is invisible but prevents trimming,
            // ensuring the 25% scale down actually looks small relative to the cursor!
            Color.white.opacity(0.01)
                .frame(width: boxSize, height: boxSize)

            // Background scattered cards
            ForEach(Array(draggedROMs.prefix(4).enumerated()), id: \.element.id) { index, otherRom in
                DragPreviewCard(rom: otherRom, preloadedImage: nil)
                    .frame(width: cardWidth)
                    .scaleEffect(isAnimating ? 0.25 : 1.0) // Shrink to 25%
                    // Start perfectly straight behind main card, fan out slightly
                    .rotationEffect(.degrees(isAnimating ? 0 : Double.random(in: -30...30)))
                    // Hide perfectly behind the main card (offset 0), slide them out as it shrinks
                    .offset(
                        x: isAnimating ? CGFloat((index + 1) * 3) : 0,
                        y: isAnimating ? CGFloat((index + 1) * 3) : 0
                    )
                    .zIndex(Double(-index))
            }
            
            // The main card the user actually clicked
            DragPreviewCard(rom: mainROM, preloadedImage: mainImage)
                .frame(width: cardWidth)
                .scaleEffect(isAnimating ? 0.25 : 1.0) // Shrink to 25%
                .zIndex(100)
            
            // Item count badge showing how many games are being dragged
            if !draggedROMs.isEmpty {
                Text("\(draggedROMs.count + 1)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.red).shadow(radius: 2))
                    .offset(x: (cardWidth * 0.125) + 8, y: -(cardWidth * 0.125) - 15)
                    // Always opaque, but pops from invisible tiny scale (0.001) to full size
                    .scaleEffect(isAnimating ? 1.0 : 0.001)
                    .zIndex(101)
            }
        }
        .frame(width: boxSize, height: boxSize)
        .onAppear {
            // A 0.02s async delay ensures the OS dragging session is fully 
            // initialized before we tell SwiftUI to shrink and animate the stack.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    isAnimating = true
                }
            }
        }
    }
}

/// A simplified, performance-friendly card strictly for the dragging stack
struct DragPreviewCard: View {
    let rom: ROM
    let preloadedImage: NSImage?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            
            // Fast, synchronous path so macOS accepts the drag view immediately
            if let img = preloadedImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(1)
            } else {
                // Instant fallback UI for background stack items
                VStack {
                    Image(systemName: "gamecontroller.fill")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .padding(.bottom, 4)
                    Text(rom.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
        }
        .aspectRatio(0.75, contentMode: .fit) // Lock aspect ratio so the preview frame is perfectly predictable
    }
}
