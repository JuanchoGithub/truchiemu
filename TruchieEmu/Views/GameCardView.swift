import SwiftUI

/// Optimized game card view for the library grid.
/// - Fixed-height text area ensures grid alignment regardless of title length
/// - Clipped hover zoom prevents grid breakage
/// - Efficient image loading with task-based async resolution
struct GameCardView: View {
    let rom: ROM
    let isSelected: Bool
    let isMultiSelected: Bool
    let zoomLevel: Double
    var gridRefreshToken: UUID = UUID()
    
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
    
    /// Fixed height for the title area — ensures grid alignment regardless of title length
    private var titleFixedHeight: CGFloat {
        // Two lines of text at the given font size + line spacing
        (titleFontSize * 1.2) * 2
    }
    
    private var categoryBadges: [GameCategory] {
        categoryManager.categories.filter { $0.gameIDs.contains(rom.id) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Artwork area — clipped to prevent hover zoom from bleeding out
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
            
            // Title area — fixed height for consistent grid alignment
            Text(rom.displayName)
                .font(.system(size: titleFontSize, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary)
                .frame(height: titleFixedHeight, alignment: .top)
            
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
        .clipped() // Prevents shadow/hover effects from expanding the card bounds
        .onHover { isHovered = $0 }
        .accessibilityLabel(rom.displayName)
        .accessibilityAddTraits(.isButton)
        .task(id: "\(rom.boxArtPath?.path ?? "")-\(gridRefreshToken)") {
            await loadBoxArt()
        }
    }
    
    private func loadBoxArt() async {
        // Fast path: use pre-resolved path — disk read happens off main actor
        if let artPath = self.rom.boxArtPath {
            if let cached = await ImageCache.shared.image(for: artPath) {
                self.image = cached
            }
            return
        }
        // On-demand path: run the file-system scan on a background thread
        // to avoid blocking the main UI/scroll. Only hop to MainActor to
        // persist the found path.
        if let resolved = await resolveBoxArtInBackground(for: self.rom) {
            if let cached = await ImageCache.shared.image(for: resolved) {
                self.image = cached
            }
        }
    }
    
    /// Resolve box art on a background thread (avoids @MainActor BoxArtService dispatch),
    /// then hop to MainActor only for the library persist. Keeps scroll buttery.
    private func resolveBoxArtInBackground(for rom: ROM) async -> URL? {
        // Step 1: full file-system scan on background thread — no main actor hopping
        let task = Task.detached {
            Self.resolveBoxArtFileSync(for: rom)
        }
        guard let resolvedURL = await task.value else {
            return nil
        }
        // Step 2: persist on MainActor (required for library.updateROM)
        await MainActor.run {
            var updated = rom
            updated.boxArtPath = resolvedURL
            self.library.updateROM(updated)
        }
        return resolvedURL
    }
    
    // MARK: - Non-@MainActor file resolution (inlined to bypass @MainActor service)
    
    /// Synchronous file-system boxart scan — must run off the main actor.
    nonisolated
    private static func resolveBoxArtFileSync(for rom: ROM) -> URL? {
        let localBoxArtDir = rom.path.deletingLastPathComponent().appendingPathComponent("boxart", isDirectory: true)
        let imageExtensions = ["png", "jpg", "jpeg", "webp", "gif", "bmp"]
        
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
        var seen = Set<String>()
        let uniqueStems = candidateStems.filter { stem in
            let normalized = stem.lowercased()
            if seen.contains(normalized) { return false }
            seen.insert(normalized)
            return true
        }
        for stem in uniqueStems {
            for ext in imageExtensions {
                let candidate = localBoxArtDir.appendingPathComponent("\(stem).\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path), isValidImageFileSync(at: candidate) {
                    return candidate
                }
            }
        }
        if FileManager.default.fileExists(atPath: rom.boxArtLocalPath.path), isValidImageFileSync(at: rom.boxArtLocalPath) {
            return rom.boxArtLocalPath
        }
        return nil
    }
    
    nonisolated
    private static func isValidImageFileSync(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        if let first = String(data: data.prefix(512), encoding: .utf8)?.lowercased(),
           first.contains("<!doctype") || first.contains("<html") || first.contains("<!html") {
            return false
        }
        if data.count < 2 { return false }
        if data.starts(with: [0x89, 0x50]) { return true }
        if data.count >= 3 && data.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        if data.count >= 4 && data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true }
        if data.starts(with: [0x42, 0x4D]) { return true }
        if data.count >= 12 && data.starts(with: [0x52, 0x49, 0x46, 0x46]) && data[8...11].elementsEqual([0x57, 0x45, 0x42, 0x50]) { return true }
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "webp"]
        return imageExtensions.contains(url.pathExtension.lowercased()) && data.count > 100
    }
    
    private var artworkView: some View {
        GridCardBoxArtView(
            image: image,
            placeholder: { AnyView(placeholderArt) },
            aspectRatio: boxType.aspectRatio,
            isHovered: isHovered
        )
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

// MARK: - Category Badges Row (extracted subview for performance)

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