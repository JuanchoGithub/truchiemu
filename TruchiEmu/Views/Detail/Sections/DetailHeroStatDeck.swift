import SwiftUI

/// One cell in the game-info hero's instrument strip: an icon plate, a bold
/// value and a tiny uppercase unit. Mirrors the library hero's stat tiles so
/// the library and the detail window read as one product.
struct DetailHeroStatItem: Identifiable {
    let id: String
    let icon: String
    let value: String
    let unit: String
    var tint: Color = AppColors.brandAccent
}

struct DetailHeroStatDeck: View {
    let items: [DetailHeroStatItem]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(AppColors.divider(colorScheme))
                        .frame(width: 1, height: 28)
                }
                cell(item)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(AppColors.brandAccent.opacity(colorScheme == .dark ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.14 : 0.55), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private func cell(_ item: DetailHeroStatItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(item.tint)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(item.tint.opacity(colorScheme == .dark ? 0.20 : 0.13))
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item.value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(verbatim: item.unit.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.value) \(item.unit)"))
    }
}
