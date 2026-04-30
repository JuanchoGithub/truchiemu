import SwiftUI

struct ModernSectionCard<Content: View>: View {
    let title: String?
    let icon: String?
    var badge: String? = nil
    var showHeader: Bool = true
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String? = nil,
        icon: String? = nil,
        badge: String? = nil,
        showHeader: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.showHeader = showHeader
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader, let title = title {
                HStack(spacing: AppSpacing.sm) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                            .font(.body)
                    }
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    if let badge = badge {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xxs)
                            .background(AppColors.accentBackground(colorScheme))
                            .foregroundColor(AppColors.accentTint(colorScheme))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.bottom, AppSpacing.sm)
                .overlay(alignment: .bottom) {
                    Divider()
                        .overlay(AppColors.divider(colorScheme))
                }
            }

            content
        }
        .padding(AppSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(AppColors.cardBackground(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl)
                        .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
        )
    }
}