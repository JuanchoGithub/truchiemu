import SwiftUI
import AppKit

// Applies the hover/pointer-tracking modifiers only when `active` is true.
// While the grid is scrolling we drop them entirely so SwiftUI does no hover
// hit-testing on the card under the cursor — otherwise every card that scrolls
// under a stationary pointer flips its hover preference and recomputes the
// (heavy) holo body on each crossing, which janks the scroll.
fileprivate extension View {
    @ViewBuilder
    func holoHoverWhenNotScrolling(
        active: Bool,
        isScrolling: Bool,
        onHover: @escaping (Bool) -> Void,
        onContinuous: @escaping (HoverPhase) -> Void
    ) -> some View {
        if active {
            self
                .onHover { hovering in
                    // Defense-in-depth: even if the modifier is attached, ignore
                    // hover events while scrolling so rapid card crossings don't
                    // flood the main thread with state updates.
                    guard !isScrolling else { return }
                    onHover(hovering)
                }
                .onContinuousHover { phase in
                    guard !isScrolling else { return }
                    onContinuous(phase)
                }
        } else {
            self
        }
    }
}

// Optimized holo game card view for the library grid.
// Replicates the Pokemon TCG holographic card effect using SwiftUI blend modes and 3D transforms.
struct HoloGameCardView: View {
    let rom: ROM
    let isSelected: Bool
    let isMultiSelected: Bool
    let zoomLevel: Double
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
    @State private var holoMasks: HoloMaskSet?
    @State private var zoomReloadToken: UUID = UUID()
    // Hover-only foil opacity (rainbow + scratch). Animated 0 → 1 when the
    // cursor enters the card and 1 → 0 when it leaves — same approach as
    // pokemon-cards-css's `card__shine`/`card__glare` opacity jumps. The
    // curve is gentle (0.22s in, 0.30s out) so the effect doesn't snap
    // harshly when the cursor crosses a card boundary.
    @State private var holoOpacity: Double = 0
    // Cursor spotlight opacity. Same hover-binary gate but tuned a touch
    // faster than the foil so the spotlight tracks the cursor crisply.
    @State private var glareIntensity: Double = 0
    @Environment(\.colorScheme) private var colorScheme
@ObservedObject private var prefs = SystemPreferences.shared
    @ObservedObject private var dragState = GameDragState.shared
    @ObservedObject private var boxArtService = BoxArtService.shared
    @ObservedObject private var holoSettings = HoloSettingsStore.shared
    @EnvironmentObject private var library: ROMLibrary
    @EnvironmentObject private var categoryManager: CategoryManager
    @ObservedObject private var scrollState = LibraryScrollState.shared
    @State private var lastDecomposedROMID: UUID?
    // Trigger for lazy holo mask decomposition — only runs when user actually
    // hovers the card (effectsActive becomes true), not on card appearance.
    @State private var holoMaskTrigger: Bool = false
    // Local generation state — avoids observing global HoloSaliencyService
    // which would cause all cards to re-render when ANY card generates masks.
    @State private var isGeneratingMasks: Bool = false
    
    // Inside-the-card mouse position from `.onContinuousHover`. Drives the
    // small 3D tilt and the cursor spotlight. Only valid while the cursor
    // is on the card (SwiftUI fires .onContinuousHover only inside the
    // view), which is why the spotlight is hover-gated rather than proximity.
    @State private var mousePosition: CGPoint?
    // Frame of the box art within the card's local coordinate space (named
    // "holoCard"). The holo foil/glare must react only while the cursor is
    // over the box art — the artwork occupies the top portion of the card,
    // below which sits the title text, and hovering the text should NOT light
    // up the holo.
    @State private var artworkFrameInCard: CGRect = .zero
    
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
        
        // Don't pre-populate the thumbnail synchronously here. On a system
        // switch the visible cards' `init` runs 50+ times in one MainActor
        // pass; each `thumbnailSync` does a sync NSCache lookup and, on a
        // cold cache (e.g. first visit to a new system), a sync
        // `CGImageSourceCreateImageAtIndex` decode. That stacks up to seconds
        // of MainActor blocking and the new roms never get a chance to
        // render. The `.task` below fills `image` from the async path,
        // which is actor-serialized (fast) and never blocks the main thread.
        _image = State(initialValue: nil)
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
    
    private var subtitleFontSize: CGFloat {
        max(8, titleFontSize - 3)
    }
    
    private var textBlockFixedPadding: CGFloat {
        switch boxType {
        case .vertical: return 14
        case .box: return 10
        case .landscape: return 10
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
    
    private var brandAccent: Color {
        AppColors.brandAccent
    }

    // Play-button diameter follows the box art (grid zoom) size: at ≤50% zoom
    // it stays at the base size; from 50%→100% it scales up to 2× the base.
    private var playButtonDiameter: CGFloat {
        let base: CGFloat = 46
        let factor = zoomLevel <= 0.5 ? 1.0 : 1.0 + (zoomLevel - 0.5) * 2.0
        return base * factor
    }
    
    // 3D tilt. Uses the *local* mouse position (only valid while the cursor is
    // inside the card, from `.onContinuousHover`), since the tilt is the
    // visible rotation the user is supposed to see. The rainbow / foil /
    // scratch layers do NOT shift with mouse position — only the boxart
    // rotates, so the mask appears glued to the art rather than sliding
    // against it.
    // Position is normalized within the artwork frame (not the whole card) so
    // tilt and glare stay consistent whether or not the cursor is over the
    // box art area.
    private var normalizedMouseX: CGFloat {
        guard let mp = mousePosition, artworkFrameInCard.width > 0 else { return 0.5 }
        return min(max((mp.x - artworkFrameInCard.minX) / artworkFrameInCard.width, 0), 1)
    }

    private var normalizedMouseY: CGFloat {
        guard let mp = mousePosition, artworkFrameInCard.height > 0 else { return 0.5 }
        return min(max((mp.y - artworkFrameInCard.minY) / artworkFrameInCard.height, 0), 1)
    }

    // 3D tilt toward the cursor, mirroring simeydotme's pokemon-cards-css
    // `.card__rotator` (rotateY/rotateX driven by pointer offset from center,
    // spring-smoothed). The card pivots around its own center so the edge
    // nearest the cursor lifts toward the viewer: cursor at the artwork's
    // top-left → the top edge rises toward the cursor and the left edge
    // rises toward the cursor, while the opposite edges recede. Angles
    // are 0 at the artwork center and reach ±maxTiltAngle at the edges.
    //
    // Sign convention (SwiftUI +X right, +Y down, +Z toward viewer;
    // right-hand rule): a positive rotX about (1,0,0) tilts the top AWAY
    // (drops away from cursor at top) and a positive rotY about (0,1,0)
    // tilts the LEFT toward the viewer (rises toward cursor at left).
    // Therefore, to RAISE the edge toward the cursor:
    //   rotX = (ny - 0.5) * 2 * maxTiltAngle  (top rises when ny < 0.5)
    //   rotY = (0.5 - nx) * 2 * maxTiltAngle  (left rises when nx < 0.5)
    private let maxTiltAngle: Double = 9

    // Animated tilt state. Driven with `withAnimation(AppMotion.tilt)` from
    // the hover handlers so ONLY the rotation springs — the glare keeps its
    // crisp 1:1 cursor tracking (a card-wide `.animation(value:)` would drag
    // the glare and foil along with the tilt spring).
    @State private var tiltRotationX: Double = 0
    @State private var tiltRotationY: Double = 0

    private var tiltTargetRotationX: Double {
        (normalizedMouseY - 0.5) * 2 * maxTiltAngle
    }

    private var tiltTargetRotationY: Double {
        (0.5 - normalizedMouseX) * 2 * maxTiltAngle
    }

    // SwiftUI `rotation3DEffect`'s `perspective` parameter is the reciprocal of
    // CSS's: SMALLER = flatter, LARGER = more dramatic, and large values
    // (e.g. 600) go near-singular so the card flips edge-on. Verified
    // empirically against the layer transform:
    //   p=0.5 -> m22 ~ 0.92 (mild), p=1 -> 0.85, p=600 -> degenerate.
    // 0.5 gives a subtle, clean pivot like simeydotme's `perspective: 600px`
    // does in CSS (whose semantics are inverted from SwiftUI's).
    private let tiltPerspective: CGFloat = 0.5

    // The tilt is a rotation about X followed by a rotation about Y. Applied
    // as two chained rotation3DEffect calls, each modifier applies its own
    // perspective projection, which double-flattens the card and warps it.
    // Instead, compose the two rotations into a single axis-angle rotation
    // (via quaternion multiplication of Rx * Ry) and apply it once, so the
    // perspective is applied exactly once — matching the CSS
    // `transform: perspective() rotateX() rotateY()` the simeydotme effect
    // uses. Net rotation is identical (verified: Rx then Ry, same sign
    // convention), but the projection is clean.
    private var tiltCombinedAngle: Double {
        let ax = tiltRotationX * .pi / 180
        let ay = tiltRotationY * .pi / 180
        // Net rotation = q_y * q_x (X rotation applied first, then Y).
        let qw = cos(ay / 2) * cos(ax / 2)
        return 2 * acos(min(max(qw, -1), 1)) * 180 / .pi
    }

    private var tiltCombinedAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        let ax = tiltRotationX * .pi / 180
        let ay = tiltRotationY * .pi / 180
        var x = cos(ay / 2) * sin(ax / 2)
        var y = sin(ay / 2) * cos(ax / 2)
        var z = -sin(ay / 2) * sin(ax / 2)
        let len = sqrt(x * x + y * y + z * z)
        if len < 1e-6 { return (1, 0, 0) }
        return (x / len, y / len, z / len)
    }

    // True only while the cursor is over the box art itself (not the title
    // text below). Gates the holo foil + glare.
    private var isOverArtwork: Bool {
        guard let mp = mousePosition else { return false }
        return artworkFrameInCard.contains(mp)
    }

    // Holo foil intensity = hover-binary gate (holoOpacity) × tilt-driven
    // reflection strength. A flat card reflects little light, a tilted
    // card reflects more — the surface normal turns toward the light as
    // the cursor moves off-center and the 3D pivot engages, so the foil
    // ramps up with the tilt magnitude. The hover gate keeps the foil
    // invisible off-card (no proximity halo); the tilt boost fades it
    // up as the card pivots. Glare (`glareIntensity`) stays hover-binary
    // and pointer-positioned (the light sits where the cursor is).
    private var holoIntensity: Double {
        let tiltMag = min(
            hypot(tiltRotationX, tiltRotationY) / (maxTiltAngle * 1.41421356),
            1
        )
        return effectsActive ? holoOpacity * tiltMag : 0
    }

    // True only while the cursor is over the card AND the grid is not
    // scrolling. All holo effects (foil, glare, tilt, bump, scale, play
    // button) are gated on this so they don't fire mid-scroll — they only
    // engage once the scroll settles (see `LibraryScrollState`).
    private var effectsActive: Bool {
        isHovered && !scrollState.isScrolling
    }

    private var translateY: CGFloat {
        effectsActive ? -10 : 0
    }

    private var scale: CGFloat {
        isPressed ? 0.97 : (isLaunching ? 1.05 : 1.0)
    }

    private var zTranslation: CGFloat {
        scale * 150
    }

    var body: some View {
        cardContent
            .coordinateSpace(name: "holoCard")
            // Hover + pointer tracking attached BEFORE the scale transform
            // below. If tracked inside the transformed subtree, the scale
            // moving the artwork under the cursor makes the hover fire on/off
            // in a feedback loop → the foil and glare opacity oscillate
            // ("pulsating orb"). Tracking the untransformed card keeps the hit
            // region stable; whether the cursor is actually over the box art is
            // decided by `isOverArtwork`. The 3D tilt below is applied to this
            // untransformed card, so rotating it doesn't move the hit region
            // either; the cursor drives the tilt AND the glare spotlight.
            .holoHoverWhenNotScrolling(
                active: !scrollState.isScrolling,
                isScrolling: scrollState.isScrolling,
                onHover: { hovering in
                    isHovered = hovering
                    if !hovering { mousePosition = nil }
                    // Ease the card back to flat on exit.
                    withAnimation(AppMotion.tilt) {
                        tiltRotationX = 0
                        tiltRotationY = 0
                    }
                },
                onContinuous: { phase in
                    switch phase {
                    case .active(let location):
                        mousePosition = location
                        // Spring the 3D tilt toward the cursor. Scoped to the
                        // tilt state only — the glare reads `mousePosition`
                        // directly so it keeps crisp 1:1 tracking.
                        withAnimation(AppMotion.tilt) {
                            tiltRotationX = tiltTargetRotationX
                            tiltRotationY = tiltTargetRotationY
                        }
                    case .ended:
                        mousePosition = nil
                        withAnimation(AppMotion.tilt) {
                            tiltRotationX = 0
                            tiltRotationY = 0
                        }
                    }
                }
            )
            .onChange(of: isOverArtwork) { _, over in
                // Foil + glare both fade on hover-binary, but only while the
                // cursor is over the box art itself (not the title text below).
                // The foil eases slightly slower than the glare so the white
                // spotlight snaps on while the color layer eases underneath.
                withAnimation(.easeOut(duration: over ? 0.22 : 0.30)) {
                    holoOpacity = over ? 1 : 0
                }
                withAnimation(.easeOut(duration: over ? 0.18 : 0.30)) {
                    glareIntensity = over ? 1 : 0
                }
            }
            .onChange(of: scrollState.isScrolling) { _, scrolling in
                // While the grid scrolls, drop all hover-driven state so the
                // heavy holo view doesn't recompute on every scroll event.
                // Effects re-engage when the cursor moves after scrolling settles.
                if scrolling {
                    isHovered = false
                    mousePosition = nil
                    tiltRotationX = 0
                    tiltRotationY = 0
                    holoOpacity = 0
                    glareIntensity = 0
                }
            }
            .onChange(of: effectsActive) { _, active in
                // Only start holo mask decomposition when user actually hovers
                // (effectsActive becomes true). This avoids pre-computing masks
                // for all grid cards when they're just visible but not interacted with.
                if active {
                    holoMaskTrigger = true
                }
            }
            // 3D tilt toward the cursor is applied to the ARTWORK ONLY (see
            // cardContent) so only the boxart pivots around its own center —
            // the title text below stays flat, matching simeydotme's
            // pokemon-cards-css where the boxart itself is the rotating card.
            // The scale/offset below compose on top of the tilted artwork.
            .scaleEffect(scale)
            .offset(y: isPressed ? -4 : translateY)
            .zIndex(effectsActive || isLaunching ? 100 : 0)
            .animation(AppMotion.micro, value: isHovered)
            .animation(AppMotion.feedback, value: isPressed)
            .animation(.easeOut(duration: 0.2), value: effectsActive)
            .animation(nil, value: isLaunching)
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
                guard rom.hasBoxArt else {
                    if self.image != nil { self.image = nil }
                    return
                }
                let artPath = rom.boxArtLocalPath
                let thumbSize = zoomBucket

                // No `thumbnailSync` here: on a system switch the NSCache is
                // cold for the new system's roms, and the synchronous fast
                // path does disk I/O + image decode on MainActor — for 50+
                // visible cards that stacks up to multi-second main-thread
                // blocks and the new roms never appear. The async path is
                // near-instant for warmed caches (single actor hop) and
                // acceptable on the cold path (one MainActor yield).
                if thumbSize != .tiny {
                    if let tiny = await ImageCache.shared.thumbnail(for: artPath, preferredSize: .tiny) {
                        self.image = tiny
                    }
                }
                if Task.isCancelled { return }

                if let img = await ImageCache.shared.thumbnail(for: artPath, preferredSize: thumbSize) {
                    self.image = img
                }
            }
            .task(id: "\(rom.id)-holoMask-\(zoomReloadToken)-\(boxArtService.boxArtUpdated)-\(holoMaskTrigger)") {
                guard rom.hasBoxArt else {
                    if holoMasks != nil { holoMasks = nil }
                    lastDecomposedROMID = nil
                    return
                }
                // Wait for hover trigger — only decompose when user actually
                // hovers this card. This avoids pre-computing masks for all
                // visible cards in the grid when they're not interacted with.
                guard holoMaskTrigger else { return }
                // Defer the (CPU-heavy) Vision decompose until the grid is not
                // actively scrolling. Generating masks mid-scroll pins cores and
                // stalls the scroll; the holo FX are suppressed during scroll
                // anyway, so there's no reason to pay the cost until it settles.
                while scrollState.isScrolling {
                    if Task.isCancelled { return }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
                if Task.isCancelled { return }
                // Mark local generation state for progress indicator (avoids
                // observing global HoloSaliencyService which causes all cards
                // to re-render when any card generates masks).
                await MainActor.run { isGeneratingMasks = true }
                defer { Task { @MainActor in isGeneratingMasks = false } }
                // Fast path: if the saliency service already has the masks in
                // memory for this romID, take them immediately and skip the
                // whole async pipeline. Avoids touching the actor at all when
                // revisiting a system whose cards have already been decomposed.
                if let inMemory = HoloSaliencyService.shared.cachedMasksSync(for: rom.id.uuidString) {
                    holoMasks = inMemory
                    lastDecomposedROMID = rom.id
                    return
                }
                // Defensive: if `.id(rom.id)` ever stops resetting @State
                // (e.g. if this view is reused elsewhere), drop stale masks
                // pinned to the previous rom so the task re-runs clean.
                if lastDecomposedROMID != rom.id {
                    holoMasks = nil
                    lastDecomposedROMID = rom.id
                }
                let artPath = rom.boxArtLocalPath
                // Feed a larger image to the decomposer for better segmentation.
                // Use the async path *only* — never `thumbnailSync` here. The
                // previous code's sync-cached-thumbnail fast path looked safe
                // but ran disk I/O on MainActor for cold cards, and on every
                // system switch the 50+ visible cards all hit it in the same
                // main-thread runloop, stacking up hundreds of ms of UI block
                // and preventing the new roms from appearing.
                guard let img = await ImageCache.shared.thumbnail(for: artPath, preferredSize: .large) else {
                    return
                }
                if Task.isCancelled { return }
                if let masks = await HoloSaliencyService.shared.holoMasks(romID: rom.id.uuidString, image: img) {
                    if Task.isCancelled { return }
                    holoMasks = masks
                    lastDecomposedROMID = rom.id
                }
            }
            .onChange(of: zoomBucket) { _, _ in
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
                    // Main artwork with holo effects. Hover + pointer tracking live on the
                    // untransformed card in `body` (stable hit region); this
                    // view just renders the foil/glare which are gated by
                    // `isOverArtwork` so they react only over the box art.
                    //
                    // The 3D tilt toward the cursor is applied HERE, to the
                    // artwork alone, so the boxart pivots around its own
                    // center exactly like simeydotme's `.card__rotator` — the
                    // title text below stays flat and nothing stretches.
                    holoArtworkView()
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(effectsActive ? 0.08 : 0))
                        )
                        .opacity(isHiddenItem ? 0.55 : 1)
                        .rotation3DEffect(
                            .degrees(effectsActive ? tiltCombinedAngle : 0),
                            axis: tiltCombinedAxis,
                            anchor: .center,
                            perspective: tiltPerspective
                        )
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    
                    if raEnabled && rom.raMatchStatus == "matched" {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.textOnAccent(for: brandAccent.opacity(0.85), colorScheme: colorScheme))
                            .padding(4)
                            .background(brandAccent.opacity(0.85))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    if isMultiSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(brandAccent)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    if isHovered, let menuContent = contextMenu {
                        ZStack {
                            Circle()
                                .fill(
                                    AngularGradient(
                                        colors: [
                                            brandAccent.opacity(0.85),
                                            brandAccent,
                                            brandAccent.opacity(0.85)
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
                        .shadow(color: brandAccent.opacity(0.4), radius: 4, y: 2)
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
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                // Frame of the box art in the card's local
                                // ("holoCard") coordinate space — decides
                                // whether the cursor is over the box art.
                                artworkFrameInCard = geo.frame(in: .named("holoCard"))
                            }
                            .onChange(of: geo.frame(in: .named("holoCard"))) { _, new in
                                artworkFrameInCard = new
                            }
                    }
                )
                .overlay(alignment: .center) {
                    if isGeneratingMasks {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(brandAccent)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                            )
                    }
                }
            }
            
            Spacer()
                .frame(height: textBlockFixedPadding)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(rom.displayName)
                    .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(isHiddenItem ? .gray : AppColors.textPrimary(colorScheme))
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
        .overlay(alignment: .center) {
            if isLaunching {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(brandAccent)
            }
        }
        .overlay(alignment: .center) {
            if holoSettings.showPlayButton, effectsActive, !isLaunching {
                GlassOrbPlayButton(
                    content: { holoArtworkView(allowBump: false) },
                    accent: brandAccent,
                    action: { onDoubleClick?() },
                    diameter: playButtonDiameter,
                    externalPointer: CGSize(
                        width: (normalizedMouseX - 0.5) * 2,
                        height: (normalizedMouseY - 0.5) * 2
                    ),
                    artworkFrame: artworkFrameInCard,
                    coordinateSpaceName: "holoCard",
                    tiltRotationX: tiltRotationX,
                    tiltRotationY: tiltRotationY,
                    tiltPerspective: tiltPerspective
                )
                .transition(.opacity)
                .accessibilityLabel(Text("Launch " + rom.displayName))
            }
        }
        .shadow(
            color: isLaunching
                ? brandAccent.opacity(0.4)
                : isSelected
                ? brandAccent.opacity(0.30)
                : effectsActive
                ? brandAccent.opacity(0.28)
                : Color.black.opacity(0.14),
            radius: isLaunching ? 14 : isSelected ? 9 : isHovered ? 12 : 7,
            y: isLaunching ? 0 : isHovered ? 6 : 3
        )
    }
    
    private var cardBackground: Color {
        if isSelected { return brandAccent.opacity(0.15) }
        if isHiddenItem { return Color.gray.opacity(0.08) }
        return .clear
    }
    
    @ViewBuilder
    private func holoArtworkView(allowBump: Bool = true) -> some View {
        if isGroupView, let nsImage = image {
            switch displayMode {
            case .fillBlurred: holoArtworkFillBlurred(nsImage)
            case .cropSquare:  holoArtworkCropSquare(nsImage)
            }
        } else {
            holoArtworkDefault(allowBump: allowBump)
        }
    }
    
    // Default artwork with holo layers
private func holoArtworkDefault(allowBump: Bool = true) -> some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            
            let artShift = min(w, h) * 0.03
            let artPX = (0.5 - normalizedMouseX) * artShift
                let artPY = (0.5 - normalizedMouseY) * artShift
            
            // Web-rendered holo (simeydotme CSS) replaces the SwiftUI foil
            // when the card is hovered/active — faithful and far cheaper to
            // maintain than re-implementing `background-blend-mode` in SwiftUI.
            let webVariant = HoloSettingsSnapshot(
                from: holoSettings, romID: rom.id.uuidString
            ).randomization?.variant ?? .regularHolo
            // swiftHolo always uses the native SwiftUI/Metal renderer
            let isSwiftHolo = webVariant == .reverseSwift
            // For other variants, check the per-variant rendering engine setting
            let useWebHolo = effectsActive && !isSwiftHolo && (holoSettings.renderingEngine[webVariant] ?? .web) == .web
            
            let scale = isPressed ? 1.08 : (effectsActive ? 1.06 : 1.0)
            
            ZStack {
                // Box art fills the entire card (base layer for blend modes).
                // Art parallax: the artwork slides *opposite* the cursor while
                // the holo foil above tracks it — the source's `--background-x/
                // y` depth trick. Scale is bumped so the shift never reveals an
                // empty edge.
                // Hidden while the web holo is active: the WebView renders the
                // box art itself (with foil), and leaving this layer on would
                // show a second, parallax-shifted box art behind it.
                if !useWebHolo {
                    if let nsImage = image {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: w, height: h)
                            .offset(x: artPX, y: artPY)
                            .clipped()
                    } else {
                        placeholderArt
                            .offset(x: artPX, y: artPY)
                    }
                }
            
            // Colored foil — proximity-driven. Barely visible at rest,
            // ramps to full color as the cursor approaches the card.
            // Hidden while the web holo is active (it draws the full
            // card image + foil itself). Only render when effects are active
            // to avoid expensive holo layer computation during scroll.
            if effectsActive && !useWebHolo {
                holoLayers(width: w, height: h, allowBump: allowBump)
            }

            // Cursor spotlight — hover-binary. Small radial highlight
            // that tracks the cursor while inside the card, off when
            // not hovering. Only render when effects are active.
            if effectsActive && !useWebHolo {
                holoGlare(width: w, height: h)
            }

            // Web-rendered holo on top (image + foil), driven by the
            // app's own cursor position. Hit-testing is disabled so the
            // card underneath keeps its hover/click behaviour. The
            // framing modifiers mirror the non-holo box art above
            // (scaledToFill + 1.06 zoom + cursor parallax + clip) so the
            // image doesn't reframe on hover — only the foil appears.
            }
            .frame(width: w, height: h) // Fixed frame fills GeometryReader
            .scaleEffect(scale, anchor: .center) // Scale from center, grows outward
            // Web-rendered holo on top (image + foil), driven by the
            // app's own cursor position. Hit-testing is disabled so the
            // card underneath keeps its hover/click behaviour. Placed in
            // overlay so it doesn't inherit the ZStack's scaleEffect.
            .overlay(
                Group {
                    if useWebHolo, let nsImage = image {
                        // Quantize frameSize to 0.5pt buckets to prevent WKWebView
                        // reloads on sub-pixel layout fluctuations during scroll.
                        let holoW = (w * 2).rounded() / 2
                        let holoH = (h * 2).rounded() / 2
                        HoloWebCardView(
                            image: nsImage,
                            variantClass: webVariant.cssClass,
                            pointerX: normalizedMouseX,
                            pointerY: normalizedMouseY,
                            heroMask: holoMasks?.hero,
                            frameSize: CGSize(width: holoW, height: holoH),
                            fitMode: .cover,
                            isActive: useWebHolo
                        )
                        .offset(x: artPX, y: artPY)
                        .clipped()
                        .allowsHitTesting(false)
                    }
                }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(isPressed ? 0.35 : 0.20), radius: isPressed ? 9 : 5, x: 0, y: isPressed ? 5 : 3)
    }
    
    // Holo regions for one card. The settings store drives both the
    // intensity (per region, slider in Holo settings) and the pattern source
    // (the user's chosen pattern; per-card randomization applies only when the
    // card's `maskDeviationChance` roll succeeds).
    //
    // The foil is pre-rendered and its position is fixed — tiles clipped to
    // the region masks stay glued to the art. The cursor drives the foil's
    // *appearance*: the rainbow hue rotates and a specular sweep band glides
    // across the masked regions, both following the cursor (see
    // `HoloFoilLayers`).
    @ViewBuilder
    private func holoLayers(width w: CGFloat, height h: CGFloat, allowBump: Bool = true) -> some View {
        var holoSnapshot = HoloSettingsSnapshot(from: holoSettings, romID: rom.id.uuidString)
        holoSnapshot.backgroundMedianRGB = image.flatMap { HoloColorSampler.medianRGB(romID: rom.id.uuidString, image: $0) }
        return ZStack {
            HoloFoilLayers(
                masks: holoMasks,
                settings: holoSnapshot,
                w: w, h: h,
                pointerX: normalizedMouseX,
                pointerY: normalizedMouseY,
                tiltX: tiltRotationX,
                tiltY: tiltRotationY,
                isHovered: effectsActive,
                allowBump: allowBump
            )
            HoloScratchLayer(w: w, h: h)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // Normalized cursor position (0...1) within the artwork frame, in the
    // artwork's own local coordinate space. Used by the glare. Only valid
    // while hovering — callers gate on holoOpacity/glareIntensity so the
    // center fallback is invisible when the cursor is away.
    private func holoGlareX(_ w: CGFloat) -> CGFloat {
        guard let mp = mousePosition, artworkFrameInCard.width > 0 else { return 0.5 }
        // The glare view is the box art's fitted rect, centered within the
        // card's artwork frame — normalize the cursor against that rect, not
        // the whole (letterboxed) card.
        let boxartMinX = artworkFrameInCard.minX + (artworkFrameInCard.width - w) / 2
        return min(max((mp.x - boxartMinX) / w, 0), 1)
    }

    private func holoGlareY(_ h: CGFloat) -> CGFloat {
        guard let mp = mousePosition, artworkFrameInCard.height > 0 else { return 0.5 }
        let boxartMinY = artworkFrameInCard.minY + (artworkFrameInCard.height - h) / 2
        return min(max((mp.y - boxartMinY) / h, 0), 1)
    }

    // The cursor spotlight — a small radial highlight that tracks the
    // pointer. Gated by `glareIntensity` (hover-binary), NOT by
    // proximity. When the cursor enters the card the spotlight fades in;
    // when it leaves, it fades out. The whole layer is a no-op visually
    // when glareIntensity is 0.
    @ViewBuilder
    private func holoGlare(width w: CGFloat, height h: CGFloat) -> some View {
        // Cursor in the artwork's own normalized coords (0...1). The
        // `.onContinuousHover` reports in the untransformed card's local
        // space, and `holoGlareX/Y` subtract the artwork frame's origin and
        // divide by its size — so the values land in this GeometryReader's
        // coordinate space. Falls back to center when not hovering, which is
        // fine since the parent gates the whole view on `glareIntensity`.
        HoloSheenEffect(pointerX: holoGlareX(w), pointerY: holoGlareY(h))
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
    }

    // Size the box art occupies when `scaledToFit` into a `w`×`h` frame.
    // Used to confine the holo foil/glare (and their masks, generated from the
    // original art) to the actual displayed art rect instead of the whole card.
    private static func fittedBoxartSize(image: NSImage?, w: CGFloat, h: CGFloat) -> CGSize {
        guard let img = image, img.size.width > 0, img.size.height > 0 else {
            return CGSize(width: w, height: h)
        }
        let artAspect = img.size.width / img.size.height
        let cardAspect = w / h
        if artAspect > cardAspect {
            return CGSize(width: w, height: w / artAspect)
        }
        return CGSize(width: h * artAspect, height: h)
    }

    // Fill blurred (Method 1) with holo layers
    private func holoArtworkFillBlurred(_ nsImage: NSImage) -> some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height

            // The sharp box art is `scaledToFit` into the card, so it occupies a
            // centered sub-rectangle rather than the full (letterboxed) card.
            // The holo masks are generated from the ORIGINAL box art, so the
            // foil + glare must be confined to that same fitted rect — otherwise
            // the masks get stretched across the whole card and drift off the
            // displayed art. (Also more correct: the holo is a property of the
            // art, not the blurred fill behind it.)
            let artSize = Self.fittedBoxartSize(image: image, w: w, h: h)

            // Web-rendered holo (simeydotme CSS) replaces the SwiftUI foil
            // when the card is hovered/active — faithful and far cheaper to
            // maintain than re-implementing `background-blend-mode` in SwiftUI.
            let webVariant = HoloSettingsSnapshot(
                from: holoSettings, romID: rom.id.uuidString
            ).randomization?.variant ?? .regularHolo
            // swiftHolo always uses the native SwiftUI/Metal renderer
            let isSwiftHolo = webVariant == .reverseSwift
            // For other variants, check the per-variant rendering engine setting
            let useWebHolo = effectsActive && !isSwiftHolo && (holoSettings.renderingEngine[webVariant] ?? .web) == .web

            ZStack {
                // Blurred background fills the card
                if let nsImage = image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                        .opacity(0.85)
                        .blur(radius: max(10, min(h, 280) * 0.08))
                }

                Color.black.opacity(0.25)

                // Sharp box art on top (base for holo blend modes)
                // Hidden while the web holo is active: the WebView renders the
                // box art itself (with foil), and leaving this layer on would
                // show a second, parallax-shifted box art behind it.
                if !useWebHolo, let nsImage = image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: w, height: h)
                        .scaleEffect(isPressed ? 1.05 : 1)
                }
            }
.frame(width: w, height: h)
            // Holo layers & glare — only render when effects are active to avoid
            // expensive computation during scroll. Use conditional rendering
            // instead of opacity(0) so the view tree isn't built at all.
            if effectsActive && !useWebHolo {
                holoLayers(width: artSize.width, height: artSize.height)
                    .frame(width: artSize.width, height: artSize.height)
            }
            if effectsActive && !useWebHolo {
                holoGlare(width: artSize.width, height: artSize.height)
                    .frame(width: artSize.width, height: artSize.height)
            }
            // Web-rendered holo on top (image + foil), driven by the
            // app's own cursor position. Hit-testing is disabled so the
            // card underneath keeps its hover/click behaviour.
            // Sized to artSize and centered to match the contained image,
            // so holo effects only appear on the actual box art (not blurred bg).
            if useWebHolo, let nsImage = image {
                // Quantize to 0.5pt buckets to prevent WKWebView reloads on
                // sub-pixel layout fluctuations during scroll.
                let holoW = (artSize.width * 2).rounded() / 2
                let holoH = (artSize.height * 2).rounded() / 2
                HoloWebCardView(
                    image: nsImage,
                    variantClass: webVariant.cssClass,
                    pointerX: normalizedMouseX,
                    pointerY: normalizedMouseY,
                    heroMask: holoMasks?.hero,
                    frameSize: CGSize(width: holoW, height: holoH),
                    fitMode: .contain,
                    isActive: useWebHolo
                )
                .frame(width: holoW, height: holoH)
                .position(x: w/2, y: h/2)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(isPressed ? 0.35 : 0.20), radius: isPressed ? 9 : 5, x: 0, y: isPressed ? 5 : 3)
    }
    
    // Crop square (Method 2) with holo layers
    private func holoArtworkCropSquare(_ nsImage: NSImage) -> some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let w = geometry.size.width
            let h = geometry.size.height
            
            // Web-rendered holo (simeydotme CSS) replaces the SwiftUI foil
            // when the card is hovered/active — faithful and far cheaper to
            // maintain than re-implementing `background-blend-mode` in SwiftUI.
            let webVariant = HoloSettingsSnapshot(
                from: holoSettings, romID: rom.id.uuidString
            ).randomization?.variant ?? .regularHolo
            // swiftHolo always uses the native SwiftUI/Metal renderer
            let isSwiftHolo = webVariant == .reverseSwift
            // For other variants, check the per-variant rendering engine setting
            let useWebHolo = effectsActive && !isSwiftHolo && (holoSettings.renderingEngine[webVariant] ?? .web) == .web
            
            ZStack {
                // Box art fills the square (base for holo blend modes)
                // Hidden while the web holo is active: the WebView renders the
                // box art itself (with foil), and leaving this layer on would
                // show a second box art behind it.
                if !useWebHolo, let nsImage = image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipped()
                        .scaleEffect(isPressed ? 1.05 : 1)
                }
                
                // Holo effect layers blend with the box art — only render when
                // effects are active to avoid expensive computation during scroll.
                if effectsActive && !useWebHolo {
                    holoLayers(width: side, height: side)
                }
                if effectsActive && !useWebHolo {
                    holoGlare(width: side, height: side)
                }
                
                // Web-rendered holo on top (image + foil), driven by the
                // app's own cursor position. Hit-testing is disabled so the
                // card underneath keeps its hover/click behaviour.
                if useWebHolo, let nsImage = image {
                    // Quantize to 0.5pt buckets to prevent WKWebView reloads on
                    // sub-pixel layout fluctuations during scroll.
                    let holoSide = (side * 2).rounded() / 2
                    HoloWebCardView(
                        image: nsImage,
                        variantClass: webVariant.cssClass,
                        pointerX: normalizedMouseX,
                        pointerY: normalizedMouseY,
                        heroMask: holoMasks?.hero,
                        frameSize: CGSize(width: holoSide, height: holoSide),
                        fitMode: .contain,
                        isActive: useWebHolo
                    )
                    .frame(width: holoSide, height: holoSide)
                    .position(x: w/2, y: h/2)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: w, height: h)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

extension HoloGameCardView {
    nonisolated static func resolveBoxArtOnDemand(for rom: ROM) async -> URL? {
        let artPath = rom.boxArtLocalPath
        if FileManager.default.fileExists(atPath: artPath.path) {
            return artPath
        }
        return nil
    }
}