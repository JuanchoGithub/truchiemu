import SwiftUI

extension GameDetailView {
    var coreSection: some View {
        ModernSectionCard(title: "Core", icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu").foregroundColor(.white.opacity(0.5))
                    Text("Emulation Core").foregroundColor(.white.opacity(0.5)).font(.caption)
                    Spacer()
                    if installedCores.isEmpty {
                        Text("No cores installed").font(.caption).foregroundColor(.white.opacity(0.3))
                    } else {
                        Picker("Core", selection: $selectedCoreID) {
                            ForEach(installedCores) { core in
                                Text(core.metadata.displayName).tag(core.id as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                Divider().overlay(dividerColor)

                Toggle(isOn: $applyCoreToSystem) {
                    HStack {
                        Image(systemName: "globe").foregroundColor(.white.opacity(0.5))
                        Text("Apply to system default").foregroundColor(.white.opacity(0.85))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                if applyCoreToSystem {
                    Text("This will change the default core for all \(systemName) games. The current game will no longer use a custom core override.")
                        .font(.caption).foregroundColor(.white.opacity(0.4)).lineSpacing(2)
                } else {
                    Text("Only this game will use the selected core.")
                        .font(.caption).foregroundColor(.white.opacity(0.4)).lineSpacing(2)
                }

                Divider().overlay(dividerColor)

                HStack {
                    Spacer()
                    Button { applyCoreConfiguration() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: applyCoreToSystem ? "globe" : "gamecontroller")
                            Text(applyCoreToSystem ? "Set System Default" : "Set for This Game")
                        }
                        .foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 8).background(Color.blue.opacity(0.6)).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCoreID == nil || installedCores.isEmpty)
                }
            }
        }
        .onAppear { applyCoreToSystem = !currentROM.useCustomCore }
    }

    func applyCoreConfiguration() {
        guard let sysID = currentROM.systemID, let coreID = selectedCoreID, !coreID.isEmpty else { return }
        if applyCoreToSystem {
            sysPrefs.setPreferredCoreID(coreID, for: sysID)
            var updated = currentROM; updated.useCustomCore = false; updated.selectedCoreID = nil
            library.updateROM(updated)
            useCustomCore = false
        } else {
            var updated = currentROM; updated.useCustomCore = true; updated.selectedCoreID = coreID
            library.updateROM(updated)
            useCustomCore = true
        }
    }

    var achievementsSection: some View {
        ModernSectionCard(
            title: "Achievements",
            icon: "trophy",
            badge: gameAchievements.isEmpty ? nil : "\(unlockedAchievementCount)/\(gameAchievements.count)"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if isAchievementsLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading achievements...").font(.subheadline).foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                } else if gameAchievements.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.slash").font(.system(size: 30)).foregroundColor(.white.opacity(0.3))
                        Text("No achievements available").font(.subheadline).foregroundColor(.white.opacity(0.5))
                        Text("Game may not have RetroAchievements data").font(.caption).foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                } else {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(unlockedAchievementCount)/\(gameAchievements.count)").font(.title2).fontWeight(.bold).foregroundColor(.white)
                            Text("Achievements").font(.caption).foregroundColor(.white.opacity(0.5))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(earnedPoints)/\(totalAchievementPoints)").font(.title2).fontWeight(.bold).foregroundColor(.white)
                            Text("Points").font(.caption).foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                        let progress = gameAchievements.isEmpty ? 0.0 : Double(unlockedAchievementCount) / Double(gameAchievements.count)
                        ProgressView(value: progress).tint(.blue).frame(width: 100)
                    }

                    Divider().overlay(dividerColor)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(gameAchievements.prefix(6)) { achievement in AchievementBadgeView(achievement: achievement) }
                            if gameAchievements.count > 6 {
                                Text("+\(gameAchievements.count - 6) more").font(.caption).foregroundColor(.white.opacity(0.4)).frame(width: 60)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}