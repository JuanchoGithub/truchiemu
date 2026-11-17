import SwiftUI

// MARK: - Library Deck Components
//
// Building blocks for the redesigned main-library shell: the navigation deck's
// quick-access tiles, the collection hero header above the content, and the
// rounded "control deck" plate that hosts the filter pills.

/// Rounded surface plate with a hairline border, used for tiles, the hero and
/// the filter control deck.
struct DeckPlate<Content: View>: View {
    var radius: CGFloat = 16
    var isSelected: Bool = false
    var tint: Color = AppColors.brandAccent
    var content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        radius: CGFloat = 16,
        isSelected: Bool = false,
        tint: Color = AppColors.brandAccent,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.isSelected = isSelected
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(LinearGradient(
                                colors: [tint.opacity(0.92), tint.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                            : AnyShapeStyle(AppColors.cardBackground(colorScheme))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : AppColors.cardBorder(colorScheme),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Quick Access Tile

/// Compact stat tile for the navigation deck. Shows an icon, a live count and
/// an uppercase label; the selected tile rests on the accent fill.
struct LibraryQuickAccessTile: View {
    let icon: String
    let label: String
    let count: Int
    let isSelected: Bool
    var tint: Color = AppColors.brandAccent
    /// Wider tiles (the odd trailing one in a two-up row) lay out horizontally
    /// so the deck never shows a tile with a dead half.
    var isWide: Bool = false
    var isGamepadFocused: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var foreground: Color {
        isSelected
            ? AppColors.textOnAccent(for: tint, colorScheme: colorScheme)
            : AppColors.textPrimary(colorScheme)
    }

    private var accent: Color {
        isSelected
            ? AppColors.textOnAccent(for: tint, colorScheme: colorScheme)
            : tint
    }

    private var iconBadge: some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent.opacity(isSelected ? 0.18 : 0.13))
            )
    }

    private var countText: some View {
        Text(verbatim: count.formatted())
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .contentTransition(.numericText())
    }

    private var labelText: some View {
        Text(verbatim: label.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.7)
            .lineLimit(1)
            .foregroundStyle(isSelected ? foreground.opacity(0.85) : AppColors.textTertiary(colorScheme))
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isWide {
                    HStack(spacing: 9) {
                        iconBadge
                        labelText
                        Spacer(minLength: 6)
                        countText
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 4) {
                            iconBadge
                            Spacer(minLength: 0)
                            if isSelected {
                                Circle()
                                    .fill(accent)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 3)
                            }
                        }

                        Spacer(minLength: 10)

                        countText

                        labelText
                            .padding(.top, 1)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            DeckPlate(radius: 14, isSelected: isSelected, tint: tint) {
                LinearGradient(
                    colors: isSelected
                        ? [Color.white.opacity(0.16), Color.clear]
                        : [Color.white.opacity(colorScheme == .dark ? 0.045 : 0.55), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isHovered && !isSelected ? tint.opacity(0.35) : .clear,
                        lineWidth: 1
                    )
                if isGamepadFocused {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppColors.brandAccent, lineWidth: 2)
                }
            }
            .allowsHitTesting(false)
        }
        .shadow(
            color: isSelected ? tint.opacity(0.22) : .clear,
            radius: isHovered ? 10 : 6,
            y: isHovered ? 4 : 2
        )
        .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1.0)
        .onHover { hovering in
            guard !ScrollActivity.isScrolling else { return }
            isHovered = hovering
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryScrollActivityChanged)) { _ in
            if ScrollActivity.isScrolling, isHovered { isHovered = false }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.1) : AppMotion.micro,
            value: isHovered
        )
        .animation(AppMotion.stateChange, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: "\(count)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Hero Stat Tile

/// Stat block for the collection hero: a soft tinted plate with a bold value
/// over a tiny uppercase unit ("68% / WITH ART"). Reads like the counted
/// blocks on a dashboard without needing a chart.
struct LibraryStatTile: View {
    let icon: String
    let value: String
    let unit: String
    var tint: Color = AppColors.brandAccent

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tint)

                Text(verbatim: value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                    .lineLimit(1)
            }

            Text(verbatim: unit.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(AppColors.textTertiary(colorScheme))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 60, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? (isHovered ? 0.20 : 0.13) : (isHovered ? 0.16 : 0.10)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(isHovered ? 0.32 : 0.16), lineWidth: 1)
        )
        .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1)
        .animation(reduceMotion ? nil : AppMotion.micro, value: isHovered)
        .onHover { isHovered = $0 }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(value) \(unit)"))
    }
}

// MARK: - Hero Backdrop

/// Ambient bed behind the collection hero: an accent wash, one drifting
/// secondary glow parked in the top-trailing corner and a fading dot field.
/// The glow only animates its offset, so it never re-lays out the header.
private struct HeroAura: View, Equatable {
    let colorScheme: ColorScheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    static func == (lhs: HeroAura, rhs: HeroAura) -> Bool {
        lhs.colorScheme == rhs.colorScheme
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    AppColors.brandAccent.opacity(colorScheme == .dark ? 0.10 : 0.07),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    AppColors.brandAccentSecondary.opacity(colorScheme == .dark ? 0.20 : 0.16),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 190
            )
            .frame(width: 380, height: 240)
            .blur(radius: 18)
            .offset(
                x: 90 + (drift ? 18 : -14),
                y: -120 + (drift ? -8 : 12)
            )

            DotField(color: AppColors.textPrimary(colorScheme))
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.22),
                            .init(color: .white, location: 0.70)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .opacity(0.55)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

/// Hairline dot grid, drawn once per hero update.
private struct DotField: View {
    let color: Color
    var spacing: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            let dot = Path(ellipseIn: CGRect(x: -0.9, y: -0.9, width: 1.8, height: 1.8))
            var field = Path()
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    field.addPath(dot, transform: CGAffineTransform(translationX: x, y: y))
                    x += spacing
                }
                y += spacing
            }
            context.fill(field, with: .color(color.opacity(0.14)))
        }
    }
}

// MARK: - Hero Shelf Card

/// One tilted box-art card in the hero's recent shelf. Hovering straightens
/// and lifts the card and reveals a play badge; clicking launches the game.
private struct HeroShelfCard: View {
    let rom: ROM
    /// Horizontal rank offset used to build the fan (-1.5 ... +1.5).
    let fanIndex: Double
    let onHover: (Bool) -> Void
    let onLaunch: () -> Void

    private let width: CGFloat = 48
    private let height: CGFloat = 66

    @State private var image: NSImage?
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(rom: ROM, fanIndex: Double, onHover: @escaping (Bool) -> Void, onLaunch: @escaping () -> Void) {
        self.rom = rom
        self.fanIndex = fanIndex
        self.onHover = onHover
        self.onLaunch = onLaunch

        // Paint from the in-memory cache only; the `.task` fills a miss.
        let cached: NSImage? = rom.hasBoxArt
            ? ImageCache.shared.thumbnailCachedOrPregen(for: rom.boxArtLocalPath, preferredSize: .tiny)
            : nil
        _image = State(initialValue: cached)
    }

    var body: some View {
        Button(action: onLaunch) {
            artwork
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(isHovered ? 0.55 : 0.22), lineWidth: 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isHovered {
                        Image(systemName: "play.fill")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(AppColors.brandAccent))
                            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                            .padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .shadow(
                    color: isHovered ? AppColors.brandAccent.opacity(0.45) : .black.opacity(0.25),
                    radius: isHovered ? 10 : 5,
                    y: isHovered ? 5 : 2
                )
                .rotationEffect(.degrees(isHovered ? 0 : fanIndex * 4), anchor: .bottom)
                .offset(y: isHovered ? -7 : abs(fanIndex) * 1.2)
                .scaleEffect(isHovered ? 1.14 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.12) : AppMotion.tilt, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        .help(rom.displayName)
        .accessibilityLabel(Text(verbatim: "\(LocalizationManager.shared.localized("contextMenu.launchGame")) \(rom.displayName)"))
        .task(id: rom.id) {
            guard image == nil, rom.hasBoxArt else { return }
            image = await ImageCache.shared.thumbnail(for: rom.boxArtLocalPath, preferredSize: .small)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [
                    AppColors.brandAccent.opacity(0.30),
                    AppColors.brandAccent.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Collection Hero

/// Header band above the library content. Owns collection identity, live
/// counts for the current filter, and a fanned shelf of recent games.
struct LibraryCollectionHero: View {
    let title: String
    let system: SystemInfo?
    let icon: String
    /// Small uppercase tag above the title, e.g. "NINTENDO" or "LIBRARY".
    let eyebrow: String
    let games: Int
    let systems: Int
    let withArt: Int
    let favorites: Int
    /// Newest first. Hovering one swaps the count line for a resume line.
    let recent: [ROM]
    let onLaunch: (ROM) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var appeared = false
    @State private var hoveredRecent: ROM?
    @State private var plateTilt: CGPoint = .zero

    private var artPercent: Int {
        guard games > 0 else { return 0 }
        return Int((Double(withArt) / Double(games) * 100).rounded())
    }

    private var countLine: String {
        let gamesText = "\(games.formatted()) \(unitText(games, pluralKey: "shell.unit.games"))"
        guard systems > 1 else { return gamesText }
        return "\(gamesText) · \(systems) \(unitText(systems, pluralKey: "shell.unit.systems"))"
    }

    /// Picks the singular key when the count is exactly one, so the hero never
    /// reads "1 games".
    private func unitText(_ count: Int, pluralKey: String) -> String {
        count == 1 ? loc.localized(pluralKey + ".one") : loc.localized(pluralKey)
    }

    private var shelf: [ROM] {
        Array(recent.prefix(4))
    }

    var body: some View {
        ZStack {
            HeroAura(colorScheme: colorScheme)
                .equatable()

            HStack(alignment: .center, spacing: 14) {
                iconPlate
                    .rotation3DEffect(.degrees(plateTilt.y * -7), axis: (1, 0, 0), perspective: 0.5)
                    .rotation3DEffect(.degrees(plateTilt.x * 10), axis: (0, 1, 0), perspective: 0.5)
                    .onContinuousHover { phase in
                        guard !reduceMotion else { return }
                        switch phase {
                        case .active(let point):
                            plateTilt = CGPoint(
                                x: (point.x / 56) - 0.5,
                                y: (point.y / 56) - 0.5
                            )
                        case .ended:
                            plateTilt = .zero
                        }
                    }
                    .animation(reduceMotion ? nil : AppMotion.tilt, value: plateTilt)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: eyebrow.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(AppColors.brandAccent)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppColors.brandAccent.opacity(colorScheme == .dark ? 0.16 : 0.10))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(AppColors.brandAccent.opacity(0.18), lineWidth: 1)
                        )

                    Text(verbatim: title)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .contentTransition(.opacity)

                    subtitle
                }

                Spacer(minLength: 8)

                if games > 0 {
                    HStack(spacing: 6) {
                        if systems > 1 {
                            LibraryStatTile(
                                icon: "gamecontroller.fill",
                                value: systems.formatted(),
                                unit: loc.localized("shell.unit.systems")
                            )
                        }
                        LibraryStatTile(
                            icon: "photo.on.rectangle",
                            value: "\(artPercent)%",
                            unit: loc.localized("shell.unit.withArt")
                        )
                        if favorites > 0 {
                            LibraryStatTile(
                                icon: "heart.fill",
                                value: favorites.formatted(),
                                unit: loc.localized("shell.unit.favorites"),
                                tint: .pink
                            )
                        }
                    }
                    .layoutPriority(2)
                }

                if !shelf.isEmpty {
                    recentShelf
                        .padding(.leading, 2)
                        .layoutPriority(3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(height: 94)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0) : AppMotion.entrance()) {
                appeared = true
            }
        }
    }

    private var subtitle: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(verbatim: countLine)
            }
            .opacity(hoveredRecent == nil ? 1 : 0)

            if let rom = hoveredRecent {
                HStack(spacing: 5) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppColors.brandAccent)
                    Text(verbatim: resumeLine(for: rom))
                        .lineLimit(1)
                }
                .transition(.opacity)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppColors.textTertiary(colorScheme))
        .lineLimit(1)
        .animation(.easeOut(duration: 0.16), value: hoveredRecent?.id)
    }

    private func resumeLine(for rom: ROM) -> String {
        guard rom.lastPlayed != nil else { return rom.displayName }
        return "\(loc.localized("shell.resume")) · \(rom.displayName)"
    }

    private var recentShelf: some View {
        HStack(spacing: -18) {
            ForEach(Array(shelf.enumerated()), id: \.element.id) { index, rom in
                HeroShelfCard(
                    rom: rom,
                    fanIndex: Double(index) - Double(shelf.count - 1) / 2,
                    onHover: { hovering in
                        if hovering {
                            hoveredRecent = rom
                        } else if hoveredRecent?.id == rom.id {
                            hoveredRecent = nil
                        }
                    },
                    onLaunch: { onLaunch(rom) }
                )
                .zIndex(hoveredRecent?.id == rom.id ? 10 : Double(index))
            }
        }
        .frame(height: 66, alignment: .center)
    }

    @ViewBuilder
    private var iconPlate: some View {
        ZStack {
            // Soft accent aura behind the plate.
            RadialGradient(
                colors: [AppColors.brandAccent.opacity(0.22), .clear],
                center: .center,
                startRadius: 2,
                endRadius: 44
            )
            .frame(width: 88, height: 88)
            .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.accentBackground(colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppColors.brandAccent.opacity(0.18), lineWidth: 1)
                }
                .frame(width: 52, height: 52)

            if let system, let image = system.emuImage(size: 132) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
            } else if GamingIconService.isGamingIconName(icon),
                      let image = GamingIconService.shared.image(for: icon) {
                // Categories can store game-icons.net names ("gi:..."), which
                // Image(systemName:) silently renders as nothing.
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .foregroundStyle(AppColors.brandAccent)
            } else {
                Image(systemName: icon.isEmpty ? "tag" : icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColors.brandAccent)
            }
        }
        .frame(width: 56, height: 56)
    }
}
