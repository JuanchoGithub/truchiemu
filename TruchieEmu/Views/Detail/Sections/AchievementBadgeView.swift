import SwiftUI

// MARK: - Achievement Badge View

struct AchievementBadgeView: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 4) {
            // Badge image
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(achievement.isUnlocked
                        ? Color.blue.opacity(0.2)
                        : Color.white.opacity(0.05))
                    .frame(width: 50, height: 50)

                Image(systemName: achievement.isUnlocked ? "trophy.fill" : "trophy")
                    .font(.system(size: 22))
                    .foregroundColor(achievement.isUnlocked ? .blue : .white.opacity(0.3))
            }

            // Points
            Text("\(achievement.points)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(achievement.isUnlocked ? .blue : .white.opacity(0.4))

            // Title
            Text(achievement.isUnlocked ? achievement.title : "???")
                .font(.system(size: 9))
                .lineLimit(1)
                .frame(width: 60)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}