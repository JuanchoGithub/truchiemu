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
    var tint: Color? = nil
    var content: Content

    @Environment(\.colorScheme) private var colorScheme

    private var effectiveTint: Color { tint ?? AppColors.brandAccent }

    init(
        radius: CGFloat = 16,
        isSelected: Bool = false,
        tint: Color? = nil,
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
                                colors: [effectiveTint.opacity(0.92), effectiveTint.opacity(0.72)],
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
    var tint: Color? = nil
    /// Wider tiles (the odd trailing one in a two-up row) lay out horizontally
    /// so the deck never shows a tile with a dead half.
    var isWide: Bool = false
    var isGamepadFocused: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var effectiveTint: Color { tint ?? AppColors.brandAccent }

    private var foreground: Color {
        isSelected
            ? AppColors.textOnAccent(for: effectiveTint, colorScheme: colorScheme)
            : AppColors.textPrimary(colorScheme)
    }

    private var accent: Color {
        isSelected
            ? AppColors.textOnAccent(for: effectiveTint, colorScheme: colorScheme)
            : effectiveTint
    }

    private var iconBadge: some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(isSelected ? 0.26 : 0.18),
                                accent.opacity(isSelected ? 0.12 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(accent.opacity(isSelected ? 0.30 : 0.16), lineWidth: 1)
            )
            .shadow(color: accent.opacity(isHovered && !isSelected ? 0.25 : 0), radius: 5)
            .scaleEffect(isHovered && !reduceMotion ? 1.10 : 1)
            .rotationEffect(.degrees(isHovered && !reduceMotion ? -5 : 0))
            .animation(reduceMotion ? nil : AppMotion.micro, value: isHovered)
    }

    private var countText: some View {
        Text(verbatim: count.formatted())
            .font(.system(size: 21, weight: .semibold, design: .rounded))
            .tracking(-0.4)
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

    private var topStatRow: some View {
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
    }

    private var narrowStatTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            topStatRow
            
            Spacer(minLength: 10)
            
            countText
            
            labelText
                .padding(.top, 1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
    }

    private var backgroundPlate: some View {
        DeckPlate(radius: 14, isSelected: isSelected, tint: effectiveTint) {
            LinearGradient(
                colors: isSelected
                    ? [Color.white.opacity(0.16), Color.clear]
                    : [Color.white.opacity(colorScheme == .dark ? 0.045 : 0.55), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
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
                    narrowStatTile
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(backgroundPlate)
        .overlay {
            ZStack {
                // Hover sheen sweeping in from the top-leading corner.
                LinearGradient(
                    colors: [
                        .white.opacity(isHovered ? (isSelected ? 0.12 : 0.16) : (isSelected ? 0.07 : 0.0)),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Inner catch-light along the top edge.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(isSelected ? 0.28 : 0.10), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isHovered && !isSelected ? effectiveTint.opacity(0.35) : .clear,
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
            color: isSelected ? effectiveTint.opacity(isHovered ? 0.34 : 0.22) : .clear,
            radius: isHovered ? 12 : 6,
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
    var tint: Color? = nil
    /// Optional 0...1 fill drawn as a hairline meter under the label. Used by
    /// the art-coverage tile so the hero carries one real data visual.
    var progress: Double? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var effectiveTint: Color { tint ?? AppColors.brandAccent }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(effectiveTint)

                Text(verbatim: value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : AppMotion.stateChange, value: value)
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                    .lineLimit(1)
            }

            Text(verbatim: unit.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(AppColors.textTertiary(colorScheme))
                .lineLimit(1)

            if let progress {
                Capsule()
                    .fill(effectiveTint.opacity(0.16))
                    .frame(width: 44, height: 2)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [effectiveTint, effectiveTint.opacity(0.65)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(2, 44 * CGFloat(min(max(progress, 0), 1))), height: 2)
                    }
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 60, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(effectiveTint.opacity(colorScheme == .dark ? (isHovered ? 0.20 : 0.13) : (isHovered ? 0.16 : 0.10)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(effectiveTint.opacity(isHovered ? 0.32 : 0.16), lineWidth: 1)
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

/// Ambient bed behind the collection hero: an accent wash, two drifting glows,
/// a slow light sweep and a fading dot field. Every moving layer animates its
/// offset/rotation only, so it never re-lays out the header.
private struct HeroAura: View, Equatable {
    let colorScheme: ColorScheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false
    @State private var counterDrift = false
    @State private var sweep = false

    static func == (lhs: HeroAura, rhs: HeroAura) -> Bool {
        lhs.colorScheme == rhs.colorScheme
    }

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    AppColors.brandAccent.opacity(isDark ? 0.12 : 0.08),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Primary glow parked in the top-trailing corner.
            RadialGradient(
                colors: [
                    AppColors.brandAccentSecondary.opacity(isDark ? 0.22 : 0.16),
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

            // Counterweight glow behind the icon plate, drifting the other way.
            RadialGradient(
                colors: [
                    AppColors.brandAccent.opacity(isDark ? 0.16 : 0.11),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 120
            )
            .frame(width: 260, height: 200)
            .blur(radius: 22)
            .offset(
                x: -180 + (counterDrift ? -12 : 10),
                y: -40 + (counterDrift ? 10 : -8)
            )

            // A slow specular sweep across the top edge of the band.
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(isDark ? 0.06 : 0.28),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 320, height: 1.2)
            .offset(x: sweep ? 140 : -360, y: 1)
            .blur(radius: 0.5)

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
            withAnimation(.easeInOut(duration: 23).repeatForever(autoreverses: true)) {
                counterDrift = true
            }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                sweep = true
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

    private let width: CGFloat = 52
    private let height: CGFloat = 72

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
            ZStack {
                // Ground glow: the card appears to stand on a lit shelf.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                (isHovered ? AppColors.brandAccent : Color.black)
                                    .opacity(isHovered ? 0.55 : 0.30),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: width * 0.62
                        )
                    )
                    .frame(width: width * 1.15, height: 14)
                    .blur(radius: 6)
                    .offset(y: height / 2 + 2)
                    .allowsHitTesting(false)

                artwork
                    .frame(width: width, height: height)
                    .overlay {
                        // Pointer-independent specular sweep on hover.
                        LinearGradient(
                            colors: [
                                .white.opacity(0),
                                .white.opacity(isHovered ? 0.28 : 0),
                                .white.opacity(0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.softLight)
                    }
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
                                .frame(width: 17, height: 17)
                                .background(Circle().fill(AppColors.brandAccent))
                                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                                .padding(4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .shadow(
                        color: isHovered ? AppColors.brandAccent.opacity(0.50) : .black.opacity(0.28),
                        radius: isHovered ? 12 : 5,
                        y: isHovered ? 6 : 2
                    )
                    .rotationEffect(.degrees(isHovered ? 0 : fanIndex * 4.5), anchor: .bottom)
                    .offset(y: isHovered ? -9 : abs(fanIndex) * 1.2)
                    .scaleEffect(isHovered ? 1.16 : 1)
                    .animation(reduceMotion ? .easeOut(duration: 0.12) : AppMotion.tilt, value: isHovered)
            }
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

private struct HeroWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
    @State private var isCollapsed = false
    @State private var hoveredRecent: ROM?
    @State private var plateTilt: CGPoint = .zero
    @State private var ringSpin = false
    @State private var heroWidth: CGFloat = 1000

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

    /// Newest game that actually has been played — the hero's primary action.
    private var resumeROM: ROM? {
        recent.first { $0.lastPlayed != nil }
    }

    var body: some View {
        ZStack {
            if isCollapsed {
                collapsedTitle
                    .transition(.opacity)
            } else {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .frame(height: isCollapsed ? 38 : 108)
        .clipped()
        .overlay(alignment: .top) {
            if !isCollapsed {
                // Hairline catch-light where the hero meets the window chrome.
                LinearGradient(
                    colors: [
                        Color.clear,
                        AppColors.brandAccent.opacity(colorScheme == .dark ? 0.30 : 0.22),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
            }
        }
        .overlay(alignment: .topLeading) {
            if !isCollapsed {
                Button(loc.localized("shell.hero.collapse"), systemImage: "chevron.up", action: collapseHero)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .padding(4)
                    .help(loc.localized("shell.hero.collapse"))
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .animation(reduceMotion ? nil : AppMotion.stateChange, value: isCollapsed)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0) : AppMotion.entrance()) {
                appeared = true
            }
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 15).repeatForever(autoreverses: false)) {
                ringSpin = true
            }
        }
    }

    private var expandedContent: some View {
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
                                x: (point.x / 60) - 0.5,
                                y: (point.y / 60) - 0.5
                            )
                        case .ended:
                            plateTilt = .zero
                        }
                    }
                    .animation(reduceMotion ? nil : AppMotion.tilt, value: plateTilt)

                VStack(alignment: .leading, spacing: 3) {
                    eyebrowChip

                    Text(verbatim: title)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    AppColors.textPrimary(colorScheme),
                                    AppColors.textPrimary(colorScheme).opacity(0.74)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .contentTransition(.opacity)
                        // The filter change that swaps this title is not wrapped
                        // in `withAnimation`, so the content transition needs its
                        // own trigger to actually cross-fade.
                        .animation(reduceMotion ? nil : AppMotion.stateChange, value: title)

                    HStack(spacing: 8) {
                        subtitle
                        if let rom = resumeROM {
                            HeroResumeButton(
                                rom: rom,
                                label: loc.localized("shell.resume"),
                                onLaunch: { onLaunch(rom) }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        }
                    }
                }
                // The title block keeps its space first; the shelf and the
                // stat tiles drop out as the window narrows instead of
                // squeezing the name and the resume action.
                .layoutPriority(1)

                Spacer(minLength: 8)

                if games > 0 && heroWidth >= 640 {
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
                            unit: loc.localized("shell.unit.withArt"),
                            progress: games > 0 ? Double(withArt) / Double(games) : 0
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

                if !shelf.isEmpty && heroWidth >= 940 {
                    recentShelf
                        .padding(.leading, 2)
                        .layoutPriority(3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: HeroWidthPreferenceKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(HeroWidthPreferenceKey.self) { heroWidth = $0 }
    }

    private var collapsedTitle: some View {
        Button(action: expandHero) {
            Text(verbatim: title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .tracking(-0.4)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            AppColors.textPrimary(colorScheme),
                            AppColors.textPrimary(colorScheme).opacity(0.74)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : AppMotion.stateChange, value: title)
        }
        .buttonStyle(.plain)
        .help(loc.localized("shell.hero.expand"))
        .accessibilityLabel(Text(verbatim: "\(loc.localized("shell.hero.expand")): \(title)"))
    }

    private func collapseHero() {
        withAnimation(reduceMotion ? .linear(duration: 0) : AppMotion.stateChange) {
            isCollapsed = true
        }
    }

    private func expandHero() {
        withAnimation(reduceMotion ? .linear(duration: 0) : AppMotion.stateChange) {
            isCollapsed = false
        }
    }

    private var eyebrowChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(AppColors.brandAccent)
                .frame(width: 4, height: 4)
                .overlay(
                    Circle()
                        .stroke(AppColors.brandAccent.opacity(0.45), lineWidth: 3)
                        .scaleEffect(1.6)
                        .opacity(0.35)
                )

            Text(verbatim: eyebrow.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.1)
                .lineLimit(1)
        }
        .foregroundStyle(AppColors.brandAccent)
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
        HStack(spacing: -16) {
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
        .frame(height: 84, alignment: .center)
    }

    @ViewBuilder
    private var iconPlate: some View {
        ZStack {
            // Soft accent aura behind the plate.
            RadialGradient(
                colors: [AppColors.brandAccent.opacity(0.24), .clear],
                center: .center,
                startRadius: 2,
                endRadius: 46
            )
            .frame(width: 96, height: 96)
            .allowsHitTesting(false)

            // Static orbit track plus a single bright arc that slowly spins.
            Circle()
                .stroke(AppColors.brandAccent.opacity(colorScheme == .dark ? 0.12 : 0.14), lineWidth: 1)
                .frame(width: 66, height: 66)

            Circle()
                .trim(from: 0.04, to: 0.70)
                .stroke(
                    AngularGradient(
                        colors: [
                            AppColors.brandAccent.opacity(0.0),
                            AppColors.brandAccent.opacity(0.85),
                            AppColors.brandAccentSecondary.opacity(0.65),
                            AppColors.brandAccent.opacity(0.0)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
                .frame(width: 66, height: 66)
                .rotationEffect(.degrees(ringSpin ? 360 : 0))
                .shadow(color: AppColors.brandAccent.opacity(0.45), radius: 3)

            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.accentBackground(colorScheme),
                            AppColors.brandAccent.opacity(colorScheme == .dark ? 0.07 : 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(AppColors.brandAccent.opacity(0.22), lineWidth: 1)
                }
                .frame(width: 54, height: 54)
                .shadow(color: AppColors.brandAccent.opacity(0.20), radius: 10, y: 3)

            if let system, let image = system.emuImage(size: 132) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
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
        .frame(width: 66, height: 66)
    }
}

// MARK: - Hero Resume Button

/// Primary action in the hero: resumes the newest played game. The cover art
/// stays in the shelf; this is the one obvious way to jump back in.
private struct HeroResumeButton: View {
    let rom: ROM
    let label: String
    let onLaunch: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var accent: Color { AppColors.brandAccent }
    private var foreground: Color {
        AppColors.textOnAccent(for: accent, colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: onLaunch) {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .black))
                    .scaleEffect(isHovered ? 1.15 : 1)

                Text(verbatim: label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))

                Text(verbatim: rom.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.78)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)
            }
            .foregroundStyle(foreground)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent, AppColors.brandAccentDimmed],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.20), lineWidth: 0.8)
            }
            .shadow(
                color: accent.opacity(isHovered ? 0.50 : 0.28),
                radius: isHovered ? 9 : 4,
                y: 2
            )
            .scaleEffect(isHovered && !reduceMotion ? 1.035 : 1)
            .animation(reduceMotion ? nil : AppMotion.micro, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(rom.displayName)
        .accessibilityLabel(Text(verbatim: "\(label) \(rom.displayName)"))
    }
}
