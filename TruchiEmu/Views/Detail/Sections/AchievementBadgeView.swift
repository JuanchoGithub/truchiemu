import SwiftUI

struct AchievementBadgeView: View {
    let achievement: Achievement
    @ObservedObject private var cache = RABadgeCacheService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var badgeImage: NSImage? = nil

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                .fill(achievement.isUnlocked
                    ? AppColors.brandAccent.opacity(0.15)
                    : AppColors.cardBackgroundSubtle(colorScheme))
                .frame(width: 52, height: 52)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                Group {
                    if let badge = badgeImage {
                        Image(nsImage: badge)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "trophy.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.textMuted(colorScheme))
                    }
                }
                .frame(width: 40, height: 40)
                .cornerRadius(4)
                .grayscale(achievement.isUnlocked ? 0 : 1.0)
                .opacity(achievement.isUnlocked ? 1.0 : 0.4)
            }

            VStack(spacing: 2) {
                Text(achievement.displayTitle)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(achievement.isUnlocked ? AppColors.textPrimary(colorScheme) : AppColors.textSecondary(colorScheme))
                .frame(height: 22, alignment: .top)

                Text("\(achievement.points) \(loc.localized("achievement.pts"))")
                .font(.system(size: 8))
                .foregroundColor(achievement.isUnlocked ? AppColors.brandAccent : AppColors.textMuted(colorScheme))
            }
            .frame(width: 64)
            .help(achievement.title)
        }
        .onAppear { loadBadge() }
        .onChange(of: achievement.localBadgeURL) { _, _ in loadBadge() }
    }

    private func loadBadge() {
        guard let url = achievement.localBadgeURL else {
            badgeImage = nil
            return
        }
        Task {
            badgeImage = await ImageCache.shared.thumbnail(for: url, maxWidth: 64, maxHeight: 64)
        }
    }
}
