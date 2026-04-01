import SwiftUI

// MARK: - Achievement List View

/// Displays all achievements for the current game.
/// Accessible from the in-game HUD or game detail view.
struct AchievementListView: View {
    @ObservedObject var raService = RetroAchievementsService.shared
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
                            Text("points")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Progress bar
                    ProgressView(value: maxPoints > 0 ? Double(totalPoints) / Double(maxPoints) : 0)
                        .progressViewStyle(.linear)
                    
                    Text("\(raService.currentGame?.achievements.filter { $0.isUnlocked }.count ?? 0) of \(raService.currentGame?.achievements.count ?? 0) unlocked")
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
                    Text("No achievements")
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
                    Text("Hardcore Mode Active")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding()
            }
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Achievement Row View

struct AchievementRowView: View {
    let achievement: Achievement
    let isExpanded: Bool
    @State private var badgeImage: NSImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // Badge
            Group {
                if let badge = badgeImage {
                    Image(nsImage: badge)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: achievement.isUnlocked ? "trophy.fill" : "lock.fill")
                        .font(.system(size: 24))
                        .foregroundColor(achievement.isUnlocked ? .yellow : .secondary)
                }
            }
            .frame(width: 40, height: 40)
            .opacity(achievement.isUnlocked ? 1.0 : 0.5)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(achievement.isUnlocked ? achievement.title : "???")
                    .font(.body)
                    .foregroundColor(achievement.isUnlocked ? .primary : .secondary)
                
                if isExpanded && achievement.isUnlocked {
                    Text(achievement.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let unlockDate = achievement.unlockDate {
                        Text("Unlocked \(unlockDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if !achievement.isUnlocked {
                    Text("Hidden until unlocked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Points badge
            VStack {
                Text("\(achievement.points)")
                    .font(.headline)
                    .foregroundColor(achievement.isUnlocked ? .accentColor : .secondary)
                Text("pts")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(achievement.isUnlocked ? Color.accentColor.opacity(0.05) : Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .onAppear {
            loadBadge()
        }
    }
    
    private func loadBadge() {
        guard let url = achievement.isUnlocked ? achievement.badgeURL : achievement.badgeLockedURL else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    self.badgeImage = image
                }
            }
        }.resume()
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
        switch self {
        case .core: return "Core"
        case .unofficial: return "Unofficial"
        case .event: return "Events"
        case .unlocked: return "Unlocked"
        case .locked: return "Locked"
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