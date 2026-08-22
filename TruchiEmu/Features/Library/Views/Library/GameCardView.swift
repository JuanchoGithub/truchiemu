import SwiftUI

// Optimized game card view for the library grid.
// Simplified image loading path for fast scroll performance.
struct GameCardView: View {
    let rom: ROM
    let isSelected: Bool
    let isMultiSelected: Bool
    let zoomLevel: Double

    // Play-button diameter follows the box art (grid zoom) size: at ≤50% zoom
    // it stays at the base size; from 50%→100% it scales up to 2× the base.
    private var playButtonDiameter: CGFloat {
        let base: CGFloat = 46
        let factor = zoomLevel <= 0.5 ? 1.0 : 1.0 + (zoomLevel - 0.5) * 2.0
        return base * factor
    }
    let filter: LibraryFilter?
    let raEnabled: Bool
    let onTap: (() -> Void)?
    let onDoubleClick: (() -> Void)?
    var contextMenu: (() -> AnyView)?
    var selectedIDsProvider: (() -> Set<UUID>)?

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var isLaunching = false
    @State private var image: NSImage?
    @State private var blurredFillImage: NSImage?
    @State private var zoomReloadToken: UUID = UUID()
    @State private var artworkFrameInCard: CGRect = .zero
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var prefs = SystemPreferences.shared
    @ObservedObject private var dragState = GameDragState.shared
    @ObservedObject private var boxArtService = BoxArtService.shared
    @EnvironmentObject private var library: ROMLibrary
    @EnvironmentObject private var categoryManager: CategoryManager

    init(
        rom: ROM,
        isSelected: Bool,
        isMultiSelected: Bool,
        zoomLevel: Double,
        filter: LibraryFilter?,
        raEnabled: Bool,
        onTap: (() -> Void)?,
        onDoubleClick: (() -> Void)?,
        contextMenu: (() -> AnyView)?,
        selectedIDsProvider: (() -> Set<UUID>)?
    ) {
        self.rom = rom
        self.isSelected = isSelected
        self.isMultiSelected = isMultiSelected
        self.zoomLevel = zoomLevel
        self.filter = filter
        self.raEnabled = raEnabled
        self.onTap = onTap
        self.onDoubleClick = onDoubleClick
        self.contextMenu = contextMenu
        self.selectedIDsProvider = selectedIDsProvider

        // Pre-populate the cached thumbnail synchronously in init so recycled
        // NSCollectionViewItems paint immediately on configure() instead of
        // flickering the placeholder while awaiting a cache hit round-trip
        // through the ImageCache actor. rom.boxArtLocalPath is authoritative
        // and rom.hasBoxArt is correct, so this is zero main-thread I/O; on a
        // miss we fall back to nil and the .task body does the async load.
        let preferredSize = BoxArtThumbnailSize.forGridZoom(zoomLevel)
        let initialImage: NSImage? = rom.hasBoxArt
            ? ImageCache.shared.thumbnailSync(for: rom.boxArtLocalPath, preferredSize: preferredSize)
            : nil
        _image = State(initialValue: initialImage)

        // Same fast-path for the pre-rasterized blurred-fill bitmap used by the
        // fillBlurred display mode. Cache miss returns nil without touching disk;
        // the on-the-fly `.blur` covers the one frame before the async task below
        // warms the cache. Only relevant when displayMode is .fillBlurred and the
        // current view is a group view (system views keep using the legacy path).
        let isGroup = filter.map { !$0.isSystemView } ?? false
        let initialBlur: NSImage? = {
            guard rom.hasBoxArt,
                  isGroup,
                  prefs.boxArtDisplayMode() == .fillBlurred else { return nil }
            return ImageCache.shared.blurredFillImageSync(for: rom.boxArtLocalPath, size: preferredSize)
        }()
        _blurredFillImage = State(initialValue: initialBlur)
    }

    private var zoomBucket: BoxArtThumbnailSize {
        BoxArtThumbnailSize.forGridZoom(zoomLevel)
    }

    private var boxType: BoxType {
        prefs.boxType(for: rom.systemID ?? "")
    }

    private var displayMode: BoxArtDisplayMode {
        prefs.boxArtDisplayMode()
    }

    private var isGroupView: Bool {
        !isSingleBoxTypeView
    }

    // The frame aspect the artwork container is locked to. For system views
    // this is the user-selected BoxType. For group views (All Games, Favorites,
    // Categories, ...) it follows the BoxArtDisplayMode the user picked in the
    // toolbar: cropSquare = 1:1, fillBlurred = portrait (matches the legacy
    // All Games height so Method 1 is visually neutral vs. the old behaviour).
    private var effectiveFrameAspectRatio: CGFloat {
        if isGroupView {
            switch displayMode {
            case .fillBlurred: return 3.0 / 4.0
            case .cropSquare: return 1.0
            }
        }
        return boxType.aspectRatio
    }

    private var titleFontSize: CGFloat {
        10 + zoomLevel * 6
    }

    private var titleLineHeight: CGFloat {
        titleFontSize * 1.2
    }

    private var textRowHeight: CGFloat {
        ceil(titleFontSize * 1.3)
    }

    private var subtitleFontSize: CGFloat {
        max(8, titleFontSize - 3)
    }

    private var subtitleLineHeight: CGFloat {
        ceil(subtitleFontSize * 1.3)
    }

    private var textBlockFixedPadding: CGFloat {
        switch boxType {
        case .vertical: return 8
        case .box: return 4
        case .landscape: return 4
        }
    }

    private var isSingleBoxTypeView: Bool {
        if case .system = filter { return true }
        return false
    }

    private var systemSubtitle: String? {
        guard !isSingleBoxTypeView,
              let systemID = rom.systemID, systemID != "unknown",
              let sys = SystemDatabase.system(forID: systemID) else { return nil }
        return sys.sidebarDisplayName
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
        return .clear
    }

    private var cardStrokeColor: Color {
        if isHiddenItem { return Color.gray.opacity(0.3) }
        return .clear
    }

    private var cardStrokeWidth: CGFloat {
        1.5
    }

    private var titleColor: Color {
        isHiddenItem ? .gray : AppColors.textPrimary(colorScheme)
    }

    var body: some View {
        cardContent
        .coordinateSpace(name: "gameCard")
        .scaleEffect(isPressed ? 0.97 : (isLaunching ? 1.05 : (isHovered ? 1.02 : 1.0)))
        .animation(AppMotion.micro, value: isHovered)
        .animation(AppMotion.feedback, value: isPressed)
        .animation(nil, value: isLaunching)
    .onHover { isHovered = $0 }
    .onDrag {
            let draggedIDs: [UUID]
            if isSelected, let provider = selectedIDsProvider {
                draggedIDs = Array(provider())
            } else {
                draggedIDs = [rom.id]
            }
            GameDragState.shared.startDrag(gameIDs: draggedIDs)
            let uuidString = draggedIDs.map(\.uuidString).joined(separator: ",")
            return NSItemProvider(object: uuidString as NSString)
        }
        .onTapGesture {
            onTap?()
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    isLaunching = true
                    onDoubleClick?()
                }
        )
        .contextMenu {
            contextMenu?()
        }
        .accessibilityLabel(rom.displayName)
        .accessibilityHint(Text("Double-click or press Enter to launch"))
        .accessibilityAddTraits(.isButton)
        .task(id: "\(rom.id)-\(rom.hasBoxArt)-\(zoomReloadToken)-\(boxArtService.boxArtUpdated)") {
            // rom.boxArtLocalPath is now authoritative (resolved during the
            // off-scroll pipeline), so this is zero main-thread I/O. Art-less
            // ROMs bail immediately to the placeholder with no await.
            guard rom.hasBoxArt else {
                if self.image != nil { self.image = nil }
                if self.blurredFillImage != nil { self.blurredFillImage = nil }
                return
            }
            let artPath = rom.boxArtLocalPath

            let thumbSize = zoomBucket

            // Fast path: if the thumbnail is already in the in-memory cache,
            // paint it synchronously and return without any await — keeps
            // recycling cells flicker-free and avoids yielding to the actor.
            if let cached = ImageCache.shared.thumbnailSync(for: artPath, preferredSize: thumbSize) {
                self.image = cached
                if isGroupView, prefs.boxArtDisplayMode() == .fillBlurred {
                    if let blurCached = ImageCache.shared.blurredFillImageSync(for: artPath, size: thumbSize) {
                        self.blurredFillImage = blurCached
                    } else {
                        // Fire-and-forget: rasterize the blurred fill off the
                        // main thread and update state when ready. The next
                        // recycle will hit the cache and skip this hop.
                        Task { @MainActor in
                            if let blurred = await ImageCache.shared.blurredFillImage(for: artPath, size: thumbSize) {
                                self.blurredFillImage = blurred
                            }
                        }
                    }
                }
                return
            }

            if thumbSize != .tiny {
                if let tiny = await ImageCache.shared.thumbnail(for: artPath, preferredSize: .tiny) {
                    self.image = tiny
                }
            }

            if let img = await ImageCache.shared.thumbnail(for: artPath, preferredSize: thumbSize) {
                self.image = img
                // After the base thumbnail lands, kick off the blurred-fill
                // rasterization in the background. The cell renders with the
                // sharp thumbnail + on-the-fly SwiftUI blur for a few frames,
                // then swaps to the cached blurred bitmap once ready.
                if isGroupView, prefs.boxArtDisplayMode() == .fillBlurred,
                   blurredFillImage == nil {
                    Task { @MainActor in
                        if let blurred = await ImageCache.shared.blurredFillImage(for: artPath, size: thumbSize) {
                            self.blurredFillImage = blurred
                        }
                    }
                }
            }
        }
        .onChange(of: zoomBucket) { _, _ in
            // Debounce zoom-driven image reloads so scrubbing the zoom slider
            // doesn't queue a decode for every step. The .task re-fires on token
            // change, picking up the latest bucket when this fires.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                zoomReloadToken = UUID()
            }
        }
        .onReceive(RunningGamesTracker.shared.$runningGames) { games in
            if isLaunching && games[rom.runningKey] != nil {
                isLaunching = false
            }
        }
        .task(id: isLaunching) {
            guard isLaunching else { return }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            isLaunching = false
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                ZStack(alignment: .topTrailing) {
                    artworkView
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { artworkFrameInCard = geo.frame(in: .named("gameCard")) }
                                .onChange(of: geo.frame(in: .named("gameCard"))) { _, new in artworkFrameInCard = new }
                        }
                    )
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(isHovered ? 0.08 : 0))
                    )
                    .grayscale(artworkGrayscale)
                    .opacity(artworkOpacity)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                    if raEnabled && rom.raMatchStatus == "matched" {
                        Image(systemName: "trophy.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.textOnAccent(for: AppColors.brandAccent.opacity(0.85), colorScheme: colorScheme))
                        .padding(4)
                        .background(AppColors.brandAccent.opacity(0.85))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .padding(4)
                        .transition(.scale.combined(with: .opacity))
                    }

                    if isMultiSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(AppColors.brandAccent)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                if isHovered, let menuContent = contextMenu {
                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [
                                        AppColors.brandAccent.opacity(0.85),
                                        AppColors.brandAccent,
                                        AppColors.brandAccent.opacity(0.85)
                                    ],
                                    center: .center
                                )
                            )
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                    }
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .shadow(color: AppColors.brandAccent.opacity(0.4), radius: 4, y: 2)
                    .overlay(
                        Menu { menuContent() } label: {
                            Circle()
                                .fill(Color.clear)
                                .contentShape(Circle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    )
                    .opacity(0.7)
                    .padding(8)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .overlay(alignment: .bottom) {
                if !categoryBadges.isEmpty {
                    CategoryBadgesRow(badges: categoryBadges)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                }
            }
            .aspectRatio(effectiveFrameAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)

            Spacer()
                .frame(height: textBlockFixedPadding)

            VStack(alignment: .leading, spacing: 2) {
                Text(rom.displayName)
                    .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(titleColor)
                    .frame(maxWidth: .infinity, alignment: .center)

                if let systemName = systemSubtitle {
                    Text(systemName)
                        .font(.system(size: subtitleFontSize, weight: .regular, design: .rounded))
                        .foregroundColor(AppColors.textMuted(colorScheme))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if isHiddenItem, let mameType = rom.mameRomType {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9))
                            .foregroundColor(AppColors.textMuted(colorScheme))
                        Text(mameType.capitalized)
                            .font(.system(size: 9))
                            .foregroundColor(AppColors.textMuted(colorScheme))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSingleBoxTypeView {
                Spacer(minLength: 0)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isSingleBoxTypeView ? .top : .center)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        )
        .overlay(
            Group {
                if isLaunching {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.brandAccent, lineWidth: 3)
                        .shadow(color: AppColors.brandAccent.opacity(0.5), radius: 8)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(cardStrokeColor, lineWidth: cardStrokeWidth)
                }
            }
        )
        .overlay(alignment: .center) {
            if isLaunching {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(AppColors.brandAccent)
            }
        }
            .overlay(alignment: .center) {
                if isHovered, !isLaunching {
                GlassOrbPlayButton(
                    content: {
                        if let nsImage = image {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.secondary.opacity(0.3)
                        }
                    },
                    accent: AppColors.brandAccent,
                    action: { onDoubleClick?() },
                    diameter: playButtonDiameter,
                    externalPointer: nil,
                    artworkFrame: artworkFrameInCard,
                    coordinateSpaceName: "gameCard"
                )
                .transition(.opacity)
                .accessibilityLabel(Text("Launch " + rom.displayName))
            }
        }
        .shadow(
            color: isLaunching
                ? AppColors.brandAccent.opacity(0.4)
                : isSelected
                ? AppColors.brandAccentSecondary.opacity(0.30)
                : isHovered
                ? AppColors.brandAccentSecondary.opacity(0.28)
                : Color.black.opacity(0.14),
            radius: isLaunching ? 14 : isSelected ? 9 : isHovered ? 12 : 7,
            y: isLaunching ? 0 : isHovered ? 6 : 3
        )
        .offset(y: isPressed ? -4 : 0)
    }

    @ViewBuilder
    private var artworkView: some View {
        if isGroupView, let nsImage = image {
            switch displayMode {
            case .fillBlurred: artworkFillBlurred(nsImage)
            case .cropSquare:  artworkCropSquare(nsImage)
            }
        } else {
            artworkDefault
        }
    }

    private var artworkDefault: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear
                if let nsImage = image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(isPressed ? 1.05 : 1)
                } else {
                    placeholderArt
                         .scaleEffect(isPressed ? 1.02 : 1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.10), lineWidth: 1))
        .shadow(color: Color.black.opacity(isPressed ? 0.35 : 0.20), radius: isPressed ? 9 : 5, x: 0, y: isPressed ? 5 : 3)
    }

    // Method 1: blurred fill. A blurred, oversized copy of the cover fills the
    // portrait frame, the sharp cover is drawn on top centered. Hides the dead
    // space around landscape covers without changing row height.
    //
    // Two background paths:
    //   - blurredFillImage set → display the pre-rasterized CoreImage blur.
    //     This is the steady-state case: a single GPU blit, no per-frame filter.
    //   - blurredFillImage nil   → fall back to SwiftUI `.blur` on the live
    //     thumbnail for the brief window before the async raster completes.
    private func artworkFillBlurred(_ nsImage: NSImage) -> some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                Color.black
                if let blurred = blurredFillImage {
                    Image(nsImage: blurred)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                        .opacity(0.85)
                } else {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                        .blur(radius: max(10, min(h, 280) * 0.08))
                        .opacity(0.85)
                }
                Color.black.opacity(0.25)
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h)
                    .scaleEffect(isPressed ? 1.05 : 1)
            }
            .frame(width: w, height: h)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.10), lineWidth: 1))
        .shadow(color: Color.black.opacity(isPressed ? 0.35 : 0.20), radius: isPressed ? 9 : 5, x: 0, y: isPressed ? 5 : 3)
    }

    // Method 2: crop to square. fit-to-fill a square frame, center-cropping
    // any overflow. Portrait covers slice top/bottom, landscape slice
    // left/right. Box covers are unaffected.
    private func artworkCropSquare(_ nsImage: NSImage) -> some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Color.black
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
                    .scaleEffect(isPressed ? 1.05 : 1)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.10), lineWidth: 1))
        .shadow(color: Color.black.opacity(isPressed ? 0.35 : 0.20), radius: isPressed ? 9 : 5, x: 0, y: isPressed ? 5 : 3)
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