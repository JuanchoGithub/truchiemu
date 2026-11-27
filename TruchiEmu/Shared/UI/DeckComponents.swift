import SwiftUI

// MARK: - Deck Components
//
// Shared building blocks for the "deck" language introduced by the library and
// game-info redesigns: a small uppercase eyebrow capsule, counted stat tiles,
// a dotted ambient bed and a hero band that frames a page. The library and the
// detail window have local variants; new surfaces use these so the whole app
// reads as one product.

// MARK: - Eyebrow

/// Small uppercase tag above a title, e.g. "SETTINGS" or "NINTENDO".
struct DeckEyebrow: View {
    let text: String
    var tint: Color { AppColors.brandAccent }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(verbatim: text.uppercased())
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(1.1)
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.11))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
    }
}

// MARK: - Stat Tile

/// One counted cell: an icon, a bold value and a tiny uppercase unit. The
/// tiles are the app's way of showing live facts without a chart.
struct DeckStatItem: Identifiable {
    let id: String
    let icon: String
    let value: String
    let unit: String
    var tint: Color? = nil

    var effectiveTint: Color { tint ?? AppColors.brandAccent }
}

struct DeckStatTile: View {
    let item: DeckStatItem

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(item.effectiveTint)

                Text(verbatim: item.value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                    .lineLimit(1)
            }

            Text(verbatim: item.unit.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(AppColors.textTertiary(colorScheme))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 58, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(item.effectiveTint.opacity(colorScheme == .dark ? (isHovered ? 0.20 : 0.13) : (isHovered ? 0.16 : 0.10)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(item.effectiveTint.opacity(isHovered ? 0.32 : 0.16), lineWidth: 1)
        )
        .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1)
        .animation(reduceMotion ? nil : AppMotion.micro, value: isHovered)
        .onHover { isHovered = $0 }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.value) \(item.unit)"))
    }
}

// MARK: - Ambient Bed

/// Hairline dot grid, drawn once per hero update.
struct DeckDotField: View {
    var color: Color
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

/// Ambient bed behind a hero: an accent wash, one drifting secondary glow in
/// the top-trailing corner and a fading dot field. Only the glow's offset
/// animates, so the header never re-lays out.
private struct DeckAura: View, Equatable {
    let colorScheme: ColorScheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    static func == (lhs: DeckAura, rhs: DeckAura) -> Bool {
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

            DeckDotField(color: AppColors.textPrimary(colorScheme))
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

// MARK: - Hero Band

/// Header band that frames a page: icon plate, eyebrow, rounded title, an
/// optional caption and a rail of live stat tiles. Optional trailing content
/// keeps room for a page-level action.
///
/// `compact` folds the band to a thin strip that keeps only the plate and the
/// title, and overrides `height`. Page content uses it while the user scrolls
/// down, so the band stops taking vertical room without losing the page
/// identity.
struct DeckHeroBand: View {
    let icon: String
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var stats: [DeckStatItem] = []
    var height: CGFloat = 88
    var compact = false
    var trailing: AnyView? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var plateTilt: CGPoint = .zero

    private var flatLayer: Bool {
        title.isEmpty && subtitle == nil && stats.isEmpty
    }

    private var resolvedHeight: CGFloat {
        compact ? 44 : height
    }

    var body: some View {
        ZStack {
            if !flatLayer && !compact {
                DeckAura(colorScheme: colorScheme)
                    .equatable()
            }

            HStack(alignment: .center, spacing: compact ? 10 : 14) {
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

                VStack(alignment: .leading, spacing: compact ? 0 : 3) {
                    if !compact && !eyebrow.isEmpty {
                        DeckEyebrow(text: eyebrow)
                    }

                    Text(verbatim: title)
                        .font(.system(size: compact ? 15 : 26, weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.opacity)

                    if !compact, let subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer(minLength: 8)

                if !compact && !stats.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(stats) { DeckStatTile(item: $0) }
                    }
                    .layoutPriority(2)
                }

                if let trailing {
                    trailing
                }
            }
            .padding(.horizontal, compact ? 18 : 24)
            .padding(.vertical, compact ? 5 : 12)
        }
        .frame(height: resolvedHeight)
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
            RadialGradient(
                colors: [AppColors.brandAccent.opacity(0.22), .clear],
                center: .center,
                startRadius: 2,
                endRadius: compact ? 22 : 44
            )
            .frame(width: compact ? 44 : 88, height: compact ? 44 : 88)
            .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
                .fill(AppColors.accentBackground(colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
                        .strokeBorder(AppColors.brandAccent.opacity(0.18), lineWidth: 1)
                }
                .frame(width: compact ? 30 : 52, height: compact ? 30 : 52)

            Image(systemName: icon.isEmpty ? "square.grid.2x2" : icon)
                .font(.system(size: compact ? 14 : 22, weight: .semibold))
                .foregroundStyle(AppColors.brandAccent)
        }
        .frame(width: compact ? 32 : 56, height: compact ? 32 : 56)
    }
}

// MARK: - Group Label

/// Uppercase section label with a hairline rule that fills the remaining row.
struct DeckGroupLabel: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: text.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(AppColors.textTertiary(colorScheme))
                .lineLimit(1)

            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(height: 1)
        }
    }
}
