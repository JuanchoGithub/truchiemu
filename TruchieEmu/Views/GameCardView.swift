import SwiftUI

/// Optimized game card view for the library grid.
/// Simplified image loading path for fast scroll performance.
struct GameCardView: View {
    let rom: ROM
    let isSelected: Bool
    let isMultiSelected: Bool
    let zoomLevel: Double

    @State private var isHovered = false
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

    private var categoryBadges: [GameCategory] {
        categoryManager.categories.filter { $0.gameIDs.contains(rom.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Artwork area
            ZStack(alignment: .topTrailing) {
                artworkView
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(isHovered ? 0.1 : 0))
                    )

                if isMultiSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .padding(4)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            // Title area
            Text(rom.displayName)
                .font(.system(size: titleFontSize, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary)

            // Category badges
            if !categoryBadges.isEmpty {
                CategoryBadgesRow(badges: categoryBadges)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(
            color: isHovered && !isSelected ? Color.accentColor.opacity(0.2) : .clear,
            radius: isHovered ? 8 : 4,
            y: isHovered ? 4 : 2
        )
        .clipped()
        .onHover { isHovered = $0 }
        .accessibilityLabel(rom.displayName)
        .accessibilityAddTraits(.isButton)
        // Load box art: always attempt resolution when card appears.
        // Fast path: if boxArtPath is set, load directly from cache.
        // Slow path: scan filesystem on-demand (background thread).
        .task(id: rom.id) {
            // Fast path: boxArtPath already resolved
            if let artPath = rom.boxArtPath {
                self.image = await ImageCache.shared.image(for: artPath)
                return
            }
            // On-demand: scan local boxart folders on background thread
            if let resolved = await Self.resolveBoxArtOnDemand(for: rom) {
                self.image = await ImageCache.shared.image(for: resolved)
            }
        }
    }

    private var artworkView: some View {
        ZStack {
            if let nsImage = image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(isHovered ? 1.05 : 1)
                    .animation(.easeOut(duration: 0.3), value: isHovered)
            } else {
                placeholderArt
                    .scaleEffect(isHovered ? 1.02 : 1)
                    .animation(.easeOut(duration: 0.3), value: isHovered)
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
    /// Scans local boxart folders on a background thread and persists the result.
    /// This is the fast path that was used in ebda454 — simple filesystem scan.
    nonisolated
    static func resolveBoxArtOnDemand(for rom: ROM) async -> URL? {
        let localBoxArtDir = rom.path.deletingLastPathComponent().appendingPathComponent("boxart", isDirectory: true)
        let imageExtensions = ["png", "jpg", "jpeg", "webp", "gif", "bmp"]

        // Build candidate stems
        var candidateStems: [String] = []
        let romFileName = rom.path.lastPathComponent
        candidateStems.append("\(romFileName)_boxart")
        let romFileStem = rom.path.deletingPathExtension().lastPathComponent
        candidateStems.append("\(romFileStem)_boxart")
        if rom.name != romFileStem && !rom.name.isEmpty {
            candidateStems.append("\(rom.name)_boxart")
        }
        let sanitized = romFileStem
            .replacingOccurrences(of: " \\(.*?\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: " \\[.*?\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized != romFileStem && !sanitized.isEmpty {
            candidateStems.append("\(sanitized)_boxart")
        }

        // Deduplicate
        var seen = Set<String>()
        let uniqueStems = candidateStems.filter { stem in
            let normalized = stem.lowercased()
            if seen.contains(normalized) { return false }
            seen.insert(normalized)
            return true
        }

        // Check each candidate
        for stem in uniqueStems {
            for ext in imageExtensions {
                let candidate = localBoxArtDir.appendingPathComponent("\(stem).\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    // Persist the found path so next time it's cached
                    await MainActor.run {
                        var updated = rom
                        updated.boxArtPath = candidate
                        // Note: We don't call library.updateROM here to avoid
                        // triggering a full grid refresh. The path is used
                        // in-memory for this session.
                    }
                    return candidate
                }
            }
        }

        // Fallback: check the app's own naming convention
        if FileManager.default.fileExists(atPath: rom.boxArtLocalPath.path) {
            let path = rom.boxArtLocalPath
            await MainActor.run {
                var updated = rom
                updated.boxArtPath = path
            }
            return path
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