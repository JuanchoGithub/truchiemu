import SwiftUI

struct AchievementBadgeView: View {
    let achievement: Achievement
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(achievement.isUnlocked
                        ? Color.blue.opacity(0.2)
                        : AppColors.cardBackgroundSubtle(colorScheme))
                    .frame(width: 50, height: 50)

                Image(systemName: achievement.isUnlocked ? "trophy.fill" : "trophy")
                    .font(.system(size: 22))
                    .foregroundColor(achievement.isUnlocked ? .blue : AppColors.textMuted(colorScheme))
            }

            Text("\(achievement.points)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(achievement.isUnlocked ? .blue : AppColors.textMuted(colorScheme))

            Text(achievement.isUnlocked ? achievement.title : "???")
                .font(.system(size: 9))
                .lineLimit(1)
                .frame(width: 60)
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
    }
}