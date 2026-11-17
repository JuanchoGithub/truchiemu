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

// MARK: - Stat Chip

/// Capsule with a bold value and a muted unit, e.g. `68% with art`.
struct LibraryStatChip: View {
    let icon: String
    let value: String
    let unit: String
    var tint: Color = AppColors.brandAccent

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(verbatim: value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary(colorScheme))
            Text(verbatim: unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textTertiary(colorScheme))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1)
        )
        .fixedSize()
    }
}

// MARK: - Collection Hero

/// Header band above the library content. Owns collection identity, the live
/// counts for the current filter and the box-art coverage chips.
struct LibraryCollectionHero: View {
    let title: String
    let system: SystemInfo?
    let icon: String
    let games: Int
    let systems: Int
    let withArt: Int
    let favorites: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var appeared = false

    private var artPercent: Int {
        guard games > 0 else { return 0 }
        return Int((Double(withArt) / Double(games) * 100).rounded())
    }

    private var subtitle: String {
        let gamesText = "\(games.formatted()) \(unitText(games, pluralKey: "shell.unit.games"))"
        guard systems > 1 else { return gamesText }
        return "\(gamesText) · \(systems) \(unitText(systems, pluralKey: "shell.unit.systems"))"
    }

    /// Picks the singular key when the count is exactly one, so the hero never
    /// reads "1 games".
    private func unitText(_ count: Int, pluralKey: String) -> String {
        count == 1 ? loc.localized(pluralKey + ".one") : loc.localized(pluralKey)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            iconPlate

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)

                Text(verbatim: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if games > 0 {
                HStack(spacing: 6) {
                    LibraryStatChip(
                        icon: "photo.on.rectangle",
                        value: "\(artPercent)%",
                        unit: loc.localized("shell.unit.withArt")
                    )
                    if favorites > 0 {
                        LibraryStatChip(
                            icon: "heart.fill",
                            value: favorites.formatted(),
                            unit: loc.localized("shell.unit.favorites"),
                            tint: .pink
                        )
                    }
                }
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0) : AppMotion.entrance()) {
                appeared = true
            }
        }
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
