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
    
    private var displayedAchievements: [Achievement] {
        guard let game = raService.currentGame else { return [] }
        switch selectedTab {
        case .core:
            return game.achievements.filter { $0.category == .core }
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
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(totalPoints) / \(maxPoints)")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text(loc.localized("achievement.points"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    ProgressView(value: maxPoints > 0 ? Double(totalPoints) / Double(maxPoints) : 0)
                        .progressViewStyle(.linear)
                    
                    Text("\(raService.currentGame?.achievements.filter { $0.isUnlocked }.count ?? 0) \(loc.localized("achievement.unlockedOf")) \(raService.currentGame?.achievements.count ?? 0) \(loc.localized("achievement.unlockedSuffix"))")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                                .background(selectedTab == tab ? Color.accentColor : Color.secondary.opacity(0.2))
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
                        .foregroundColor(.secondary)
                    Text(loc.localized("achievement.noAchievements"))
                        .foregroundColor(.secondary)
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
                        .foregroundColor(.orange)
                    Text(loc.localized("achievement.hardcoreModeActive"))
                        .font(.caption)
                        .foregroundColor(.orange)
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
    var body: some View {
        HStack(spacing: 12) {
            // Badge
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(achievement.isUnlocked ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Group {
                    if let localURL = achievement.localBadgeURL, let nsImage = NSImage(contentsOf: localURL) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
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
                    .foregroundColor(achievement.isUnlocked ? .primary : .secondary)
                
                if isExpanded && achievement.isUnlocked {
                    Text(achievement.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let unlockDate = achievement.unlockDate {
                        Text("\(loc.localized("achievement.unlockedDate")) \(unlockDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if !achievement.isUnlocked {
                    Text(loc.localized("achievement.hiddenUntilUnlocked"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Points badge
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(achievement.points)")
                    .font(.headline)
                    .foregroundColor(achievement.isUnlocked ? .accentColor : .secondary)
                Text(loc.localized("achievement.pts"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(achievement.isUnlocked ? Color.accentColor.opacity(0.05) : Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Achievement Tabs

enum AchievementTab: CaseIterable {
    case core
    case unofficial
    case event
    case unlocked
    case locked
    
    var title: String {
        let loc = LocalizationManager.shared
        switch self {
        case .core: return loc.localized("achievement.core")
        case .unofficial: return loc.localized("achievement.unofficial")
        case .event: return loc.localized("achievement.events")
        case .unlocked: return loc.localized("achievement.unlocked")
        case .locked: return loc.localized("achievement.locked")
        }
    }
    
    var icon: String {
        switch self {
        case .core: return "target"
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