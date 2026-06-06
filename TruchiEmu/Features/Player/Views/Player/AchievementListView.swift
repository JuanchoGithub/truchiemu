import SwiftUI

// MARK: - Achievement List View

// Displays all achievements for the current game.
// Accessible from the in-game HUD or game detail view.
struct AchievementListView: View {
    @ObservedObject var raService = RetroAchievementsService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: AchievementTab = .core
    @State private var expandedAchievement: Int?
	@Environment(\.colorScheme) private var colorScheme
    
    private var displayedAchievements: [Achievement] {
        guard let game = raService.currentGame else { return [] }
        switch selectedTab {
        case .core:
            return game.achievements.filter { $0.category == .core }
        case .exclusive:
            return game.achievements.filter { $0.category == .exclusive }
        case .unofficial:
            return game.achievements.filter { $0.category == .unofficial }
        case .event:
            return game.achievements.filter { $0.category == .event }
        case .locked:
            return game.achievements.filter { !$0.isUnlocked }
        case .unlocked:
            return game.achievements.filter { $0.isUnlocked }
        }
    }
    
    private var totalPoints: Int {
        guard let game = raService.currentGame else { return 0 }
        return game.achievements.filter { $0.isUnlocked }.reduce(0) { $0 + $1.points }
    }
    
    private var maxPoints: Int {
        guard let game = raService.currentGame else { return 0 }
        return game.totalPoints
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            if let game = raService.currentGame {
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(game.title)
                                .font(.headline)
                            Text("\(game.consoleName)")
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(totalPoints) / \(maxPoints)")
                                .font(.title3)
                                .fontWeight(.bold)
                        Text(loc.localized("achievement.points"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                    }
                    
                    ProgressView(value: maxPoints > 0 ? Double(totalPoints) / Double(maxPoints) : 0)
                        .progressViewStyle(.linear)
                    
            Text("\(raService.currentGame?.achievements.filter { $0.isUnlocked }.count ?? 0) \(loc.localized("achievement.unlockedOf")) \(raService.currentGame?.achievements.count ?? 0) \(loc.localized("achievement.unlockedSuffix"))")
                .font(.caption)
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .padding()
                
                Divider()
            }
            
            // Tab filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AchievementTab.allCases, id: \.self) { tab in
                        Button(action: { selectedTab = tab }) {
                            Label(tab.title, systemImage: tab.icon)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedTab == tab ? AppColors.brandAccent : AppColors.cardBackground(colorScheme))
                                .foregroundColor(selectedTab == tab ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            Divider()
            
            // Achievement list
            if displayedAchievements.isEmpty {
                VStack(spacing: 12) {
            Image(systemName: selectedTab == .unlocked ? "lock.fill" : "trophy.fill")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            Text(loc.localized("achievement.noAchievements"))
                .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedAchievements) { achievement in
                            AchievementRowView(
                                achievement: achievement,
                                isExpanded: expandedAchievement == achievement.id
                            )
                            .onTapGesture {
                                withAnimation {
                                    if expandedAchievement == achievement.id {
                                        expandedAchievement = nil
                                    } else {
                                        expandedAchievement = achievement.id
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            
            // Footer
            if raService.hardcoreMode {
                Divider()
                HStack {
            Image(systemName: "shield.lefthalf.filled.fill")
                .foregroundColor(AppColors.warning(colorScheme))
            Text(loc.localized("achievement.hardcoreModeActive"))
                .font(.caption)
                .foregroundColor(AppColors.warning(colorScheme))
                }
                .padding()
            }
        }
        .navigationTitle(loc.localized("achievement.achievementsTitle"))
    }
}

// MARK: - Achievement Row View

struct AchievementRowView: View {
    let achievement: Achievement
    let isExpanded: Bool
    @ObservedObject private var cache = RABadgeCacheService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var badgeImage: NSImage? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Badge
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
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(achievement.displayTitle)
                    .font(.body)
                    .fontWeight(achievement.isUnlocked ? .medium : .regular)
                    .foregroundColor(achievement.isUnlocked ? .primary : AppColors.textSecondary(colorScheme))
                
                if isExpanded && achievement.isUnlocked {
                    Text(achievement.description)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    
                    if let unlockDate = achievement.unlockDate {
                    Text("\(loc.localized("achievement.unlockedDate")) \(unlockDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                } else if !achievement.isUnlocked {
                    Text(loc.localized("achievement.hiddenUntilUnlocked"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
            }
            
            Spacer()
            
            // Points badge
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(achievement.points)")
                    .font(.headline)
                    .foregroundColor(achievement.isUnlocked ? AppColors.brandAccent : AppColors.textSecondaryNeutral(colorScheme))
                Text(loc.localized("achievement.pts"))
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }
        }
        .padding(12)
        .background(achievement.isUnlocked ? AppColors.brandAccent.opacity(0.05) : AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(8)
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

// MARK: - Achievement Tabs

enum AchievementTab: CaseIterable {
    case core
    case exclusive
    case unofficial
    case event
    case unlocked
    case locked

    var title: String {
        let loc = LocalizationManager.shared
        switch self {
        case .core: return loc.localized("achievement.core")
        case .exclusive: return loc.localized("achievement.exclusive")
        case .unofficial: return loc.localized("achievement.unofficial")
        case .event: return loc.localized("achievement.events")
        case .unlocked: return loc.localized("achievement.unlocked")
        case .locked: return loc.localized("achievement.locked")
        }
    }

    var icon: String {
        switch self {
        case .core: return "target"
        case .exclusive: return "star.circle"
        case .unofficial: return "wrench"
        case .event: return "calendar"
        case .unlocked: return "trophy.fill"
        case .locked: return "lock.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        AchievementListView()
    }
}