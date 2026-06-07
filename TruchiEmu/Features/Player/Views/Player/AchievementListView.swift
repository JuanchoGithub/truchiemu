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
@State private var viewMode: AchievementViewMode = .list
@State private var gridWidth: CGFloat = 700
@Environment(\.colorScheme) private var colorScheme

    private var displayedAchievements: [Achievement] {
        guard let game = raService.currentGame else { return [] }
        let filtered: [Achievement]
        switch selectedTab {
        case .core:
            filtered = game.achievements.filter { $0.category == .core }
        case .exclusive:
            filtered = game.achievements.filter { $0.category == .exclusive }
        case .unofficial:
            filtered = game.achievements.filter { $0.category == .unofficial }
        case .event:
            filtered = game.achievements.filter { $0.category == .event }
        case .locked:
            filtered = game.achievements.filter { !$0.isUnlocked }
        case .unlocked:
            filtered = game.achievements.filter { $0.isUnlocked }
        }
        return filtered.sorted {
            if $0.isUnlocked != $1.isUnlocked { return $0.isUnlocked }
            if $0.isUnlocked && $1.isUnlocked {
                if let d0 = $0.unlockDate, let d1 = $1.unlockDate { return d0 > d1 }
                if $0.unlockDate != nil { return true }
                if $1.unlockDate != nil { return false }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
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

            // Tab filter + view mode toggle
            HStack {
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
                }

                Spacer()

                Picker(selection: $viewMode) {
                    ForEach(AchievementViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

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
                    if viewMode == .grid {
                        achievementGridContent
                    } else {
                        achievementRowContent
                    }
                }
                .padding()
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
 .onAppear {
 if let game = raService.currentGame, !game.achievements.isEmpty {
 RABadgeCacheService.shared.prefetchBadges(for: game.achievements)
 }
 }
    }

    @ViewBuilder
    private var achievementGridContent: some View {
        let columns = [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: 12)]
        let chunkSize = max(1, Int(gridWidth) / (64 + 12))

        VStack(spacing: 16) {
            ForEach(Array(stride(from: 0, to: displayedAchievements.count, by: chunkSize)), id: \.self) { rowIndex in
                let chunk = Array(displayedAchievements[rowIndex..<(min(rowIndex + chunkSize, displayedAchievements.count))])

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(chunk, id: \.id) { achievement in
                        AchievementBadgeView(achievement: achievement, expandedAchievementID: Binding(
                            get: { expandedAchievement },
                            set: { expandedAchievement = $0 }
                        ))
                    }
                }

                if let expandedID = expandedAchievement,
                   let expanded = displayedAchievements.first(where: { $0.id == expandedID }),
                   chunk.contains(where: { $0.id == expandedID }) {
                    AchievementExpandedDetailView(achievement: expanded)
                        .transition(.opacity)
                }
            }
        }
        .padding()
        .background(GeometryReader { geo in
            Color.clear.onChange(of: geo.size.width) { _, newWidth in
                gridWidth = newWidth
            }
        })
    }

    @ViewBuilder
    private var achievementRowContent: some View {
        LazyVStack(spacing: 8) {
            ForEach(displayedAchievements) { achievement in
                AchievementRowView(achievement: achievement)
            }
        }
    }
}

// MARK: - Achievement Row View

struct AchievementRowView: View {
    let achievement: Achievement
    @ObservedObject private var cache = RABadgeCacheService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var badgeImage: NSImage? = nil
    @Environment(\.colorScheme) private var colorScheme

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

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(achievement.displayTitle)
                        .font(.body)
                        .fontWeight(achievement.isUnlocked ? .medium : .regular)
                        .foregroundColor(achievement.isUnlocked ? .primary : AppColors.textSecondary(colorScheme))

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
                    .lineLimit(2)

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
                }
            }

            Spacer()

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
