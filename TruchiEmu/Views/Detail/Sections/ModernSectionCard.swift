import SwiftUI

struct ModernSectionCard<Content: View>: View {
    let title: String?
    let icon: String?
    var badge: String? = nil
    var showHeader: Bool = true
    var headerTrailing: AnyView? = nil
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String? = nil,
        icon: String? = nil,
        badge: String? = nil,
        showHeader: Bool = true,
        headerTrailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.showHeader = showHeader
        self.headerTrailing = headerTrailing
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader, let title = title {
                HStack(spacing: AppSpacing.md) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColors.brandAccent)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(AppColors.accentBackground(colorScheme))
                            )
                    }
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .textCase(.uppercase)
                        .tracking(0.7)
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xxs)
                            .background(AppColors.accentBackground(colorScheme))
                            .foregroundColor(AppColors.accentTint(colorScheme))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if let headerTrailing = headerTrailing {
                        headerTrailing
                    }
                }
                .padding(.bottom, AppSpacing.md)
                .overlay(alignment: .bottom) {
                    Divider()
                        .overlay(AppColors.divider(colorScheme))
                }
            }

            content
        }
        .padding(AppSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.cardBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}