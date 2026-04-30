import SwiftUI

extension GameDetailView {
    var coreSection: some View {
        ModernSectionCard(title: "Core", icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu").foregroundColor(AppColors.textSecondary(colorScheme))
                    Text("Emulation Core").foregroundColor(AppColors.textSecondary(colorScheme)).font(.caption)
                    Spacer()
                    if installedCores.isEmpty {
                        Text("No cores installed").font(.caption).foregroundColor(AppColors.textMuted(colorScheme))
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

                Divider().overlay(AppColors.divider(colorScheme))

                Toggle(isOn: $applyCoreToSystem) {
                    HStack {
                        Image(systemName: "globe").foregroundColor(AppColors.textSecondary(colorScheme))
                        Text("Apply to system default").foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                if applyCoreToSystem {
                    Text("This will change the default core for all \(systemName) games. The current game will no longer use a custom core override.")
                        .font(.caption).foregroundColor(AppColors.textMuted(colorScheme)).lineSpacing(2)
                } else {
                    Text("Only this game will use the selected core.")
                        .font(.caption).foregroundColor(AppColors.textMuted(colorScheme)).lineSpacing(2)
                }

                Divider().overlay(AppColors.divider(colorScheme))

                HStack {
                    Spacer()
                    Button { applyCoreConfiguration() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: applyCoreToSystem ? "globe" : "gamecontroller")
                            Text(applyCoreToSystem ? "Set System Default" : "Set for This Game")
                        }
                        .foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 8).background(Color.accentColor.opacity(0.6)).cornerRadius(8)
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
                        Text("Loading achievements...").font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                } else if gameAchievements.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.circle").font(.system(size: 30)).foregroundColor(AppColors.textMuted(colorScheme))
                        Text("No achievements available").font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
                        Text("Game may not have RetroAchievements data").font(.caption).foregroundColor(AppColors.textMuted(colorScheme))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                } else {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(unlockedAchievementCount)/\(gameAchievements.count)").font(.title2).fontWeight(.bold).foregroundColor(AppColors.textPrimary(colorScheme))
                            Text("Achievements").font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(earnedPoints)/\(totalAchievementPoints)").font(.title2).fontWeight(.bold).foregroundColor(AppColors.textPrimary(colorScheme))
                            Text("Points").font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                        Spacer()
                        let progress = gameAchievements.isEmpty ? 0.0 : Double(unlockedAchievementCount) / Double(gameAchievements.count)
                        ProgressView(value: progress).tint(.blue).frame(width: 100)
                    }

                    Divider().overlay(AppColors.divider(colorScheme))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(gameAchievements.prefix(6)) { achievement in AchievementBadgeView(achievement: achievement) }
                            if gameAchievements.count > 6 {
                                Text("+\(gameAchievements.count - 6) more").font(.caption).foregroundColor(AppColors.textMuted(colorScheme)).frame(width: 60)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}