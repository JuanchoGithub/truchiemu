import SwiftUI

/// One gamepad affordance in the bottom hint bar.
struct TVModeHint: Identifiable {
    let glyph: String
    let label: String
    /// Wide glyphs (L1/R1, arrows, START) use a capsule instead of a circle.
    var wide: Bool = false

    var id: String { "\(glyph)|\(label)" }
}

/// Console-style control legend pinned to the bottom of TV mode. The hints are
/// contextual: systems, games and the detail page each show the buttons that
/// actually do something on that page.
struct TVModeHintBar: View {
    let hints: [TVModeHint]
    let sortLabel: String?
    let theme: TVModeSettings.Theme

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tvModeScale) private var scale

    var body: some View {
        let palette = TVModePalette(theme: theme, colorScheme: colorScheme)
        HStack(spacing: 20 * scale) {
            ForEach(hints) { hint in
                HStack(spacing: 7 * scale) {
                    glyph(hint.glyph, wide: hint.wide, palette: palette)
                    Text(verbatim: hint.label)
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 20 * scale)

            if let sortLabel {
                HStack(spacing: 7 * scale) {
                    glyph("L3", wide: true, palette: palette)
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9 * scale, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Text(verbatim: sortLabel)
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .frame(height: 26 * scale)
        .padding(.top, 12 * scale)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.clear, palette.panelStroke, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
    }

    private func glyph(_ text: String, wide: Bool, palette: TVModePalette) -> some View {
        Text(verbatim: text)
            .font(.system(size: 9.5 * scale, weight: .heavy, design: .rounded))
            .foregroundStyle(palette.textPrimary)
            .frame(width: wide ? nil : 20 * scale, height: 20 * scale)
            .padding(.horizontal, wide ? 7 * scale : 0)
            .background(glyphBackground(wide: wide, palette: palette))
    }

    @ViewBuilder
    private func glyphBackground(wide: Bool, palette: TVModePalette) -> some View {
        if wide {
            Capsule()
                .fill(palette.panelFillStrong)
                .overlay(Capsule().strokeBorder(palette.panelStroke, lineWidth: 1 * scale))
        } else {
            Circle()
                .fill(palette.panelFillStrong)
                .overlay(Circle().strokeBorder(palette.panelStroke, lineWidth: 1 * scale))
        }
    }
}
