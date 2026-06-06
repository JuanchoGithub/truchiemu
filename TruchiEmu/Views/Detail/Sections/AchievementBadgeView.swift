import SwiftUI

enum AchievementViewMode: String, CaseIterable {
    case grid
    case list

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }

    var localizedName: String {
        let loc = LocalizationManager.shared
        switch self {
        case .grid: return loc.localized("achievement.viewMode.grid")
        case .list: return loc.localized("achievement.viewMode.list")
        }
    }
}

struct AchievementBadgeView: View {
    let achievement: Achievement
    @Binding var expandedAchievementID: Int?
    @ObservedObject private var cache = RABadgeCacheService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var badgeImage: NSImage? = nil

    private var isExpanded: Bool { expandedAchievementID == achievement.id }

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
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isExpanded ? AppColors.brandAccent : Color.clear, lineWidth: 2)
            )

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
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedAchievementID == achievement.id {
                    expandedAchievementID = nil
                } else {
                    expandedAchievementID = achievement.id
                }
            }
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

struct AchievementExpandedDetailView: View {
    let achievement: Achievement
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var badgeImage: NSImage? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(achievement.isUnlocked ? AppColors.brandAccent.opacity(0.1) : AppColors.cardBackgroundSubtle(colorScheme))
                    .frame(width: 44, height: 44)

                Group {
                    if let badge = badgeImage {
                        Image(nsImage: badge)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                }
                .frame(width: 32, height: 32)
                .grayscale(achievement.isUnlocked ? 0 : 1.0)
                .opacity(achievement.isUnlocked ? 1.0 : 0.4)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(achievement.displayTitle)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.textPrimary(colorScheme))

                    if achievement.isUnlocked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(AppColors.brandAccent)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                }

                Text(achievement.isUnlocked ? achievement.description : loc.localized("achievement.hiddenUntilUnlocked"))
                    .font(.caption)
                    .foregroundColor(achievement.isUnlocked ? AppColors.textSecondary(colorScheme) : AppColors.textSecondaryNeutral(colorScheme))

                HStack(spacing: 12) {
                    if let unlockDate = achievement.unlockDate {
                        Label {
                            Text(unlockDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                        } icon: {
                            Image(systemName: "calendar")
                                .font(.caption2)
                        }
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    }

                    if achievement.isHardcore {
                        Label {
                            Text(loc.localized("achievement.hardcoreUnlock"))
                                .font(.caption2)
                        } icon: {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.caption2)
                        }
                        .foregroundColor(AppColors.warning(colorScheme))
                    }

                    Label {
                        Text(achievement.category.displayName)
                            .font(.caption2)
                    } icon: {
                        Image(systemName: categoryIcon)
                            .font(.caption2)
                    }
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))

                    Spacer()

                    Text("\(achievement.points) \(loc.localized("achievement.pts"))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(achievement.isUnlocked ? AppColors.brandAccent : AppColors.textSecondaryNeutral(colorScheme))
                }
            }
        }
        .padding(12)
        .background(AppColors.cardBackground(colorScheme))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.brandAccent.opacity(0.2), lineWidth: 1)
        )
        .id(achievement.id)
        .onAppear { loadBadge() }
        .onChange(of: achievement.id) { _, _ in
            badgeImage = nil
            loadBadge()
        }
    }

    private var categoryIcon: String {
        switch achievement.category {
        case .core: return "target"
        case .exclusive: return "star.circle"
        case .unofficial: return "wrench"
        case .event: return "calendar"
        }
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
