import SwiftUI

/// Small stat pill: icon plate + bold value + tiny uppercase unit.
/// Used at the top of each section card to show live counts without
/// opening the full hero deck.
struct DetailStatBadge: View {
    let icon: String
    let value: String
    let unit: String
    var tint: Color = AppColors.brandAccent

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.13))
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(verbatim: unit.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1)
        )
    }
}
