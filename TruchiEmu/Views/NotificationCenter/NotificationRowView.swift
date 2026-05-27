import SwiftUI

struct NotificationRowView: View {
    let entry: NotificationEntry
    var compact: Bool = false
    var onAction: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isActionHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppGradients.accent)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !entry.isRead {
                        Circle()
                            .fill(AppColors.brandAccent)
                            .frame(width: 6, height: 6)
                    }
                    Text(entry.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                        .lineLimit(1)
                }

                Text(relativeTimeString(for: entry.createdAt))
                    .font(.system(size: 9))
                    .foregroundColor(AppColors.textTertiary(colorScheme))
            }

            Spacer(minLength: 4)

            if let actionLabel = entry.actionLabel {
                Button {
                    onAction?()
                } label: {
                    Text(actionLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.brandAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(AppColors.brandAccent.opacity(isActionHovering ? 0.15 : 0.08))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(AppAnimations.quick) {
                        isActionHovering = hovering
                    }
                }
            }

            if !compact {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(entry.isRead ? Color.clear : AppColors.accentBackground(colorScheme).opacity(0.3))
        )
    }

    private func relativeTimeString(for date: Date) -> String {
        let loc = LocalizationManager.shared
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return loc.localized("notifications.timeJustNow")
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return String(format: loc.localized("notifications.timeMinutesAgo"), mins)
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return String(format: loc.localized("notifications.timeHoursAgo"), hours)
        } else {
            let days = Int(interval / 86400)
            return String(format: loc.localized("notifications.timeDaysAgo"), days)
        }
    }
}
