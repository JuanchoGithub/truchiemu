import SwiftUI

extension GameDetailView {
    var coreSection: some View {
        ModernSectionCard(title: loc.localized("core.title"), icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu").foregroundColor(AppColors.textSecondary(colorScheme))
                    Text(loc.localized("core.emulationCore")).foregroundColor(AppColors.textSecondary(colorScheme)).font(.caption)
                    Spacer()
                    if installedCores.isEmpty {
                        Text(loc.localized("core.noCoresInstalled")).font(.caption).foregroundColor(AppColors.textMuted(colorScheme))
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
                        Text(loc.localized("core.applyToSystemDefault")).foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                if applyCoreToSystem {
                    Text(loc.localized("core.changeSystemCoreWarning").replacingOccurrences(of: "{0}", with: systemName))
                        .font(.caption).foregroundColor(AppColors.textMuted(colorScheme)).lineSpacing(2)
                } else {
                    Text(loc.localized("core.onlyThisGameUsesSelectedCore"))
                        .font(.caption).foregroundColor(AppColors.textMuted(colorScheme)).lineSpacing(2)
                }

                Divider().overlay(AppColors.divider(colorScheme))

                HStack {
                    Spacer()
                    Button { applyCoreConfiguration() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: applyCoreToSystem ? "globe" : "gamecontroller")
                            Text(applyCoreToSystem ? loc.localized("core.setSystemDefault") : loc.localized("core.setForThisGame"))
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
            title: loc.localized("gameDetail.achievements"),
            icon: "trophy",
            badge: gameAchievements.isEmpty ? nil : "\(unlockedAchievementCount)/\(gameAchievements.count)"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if isAchievementsLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(loc.localized("achievement.loadingAchievements")).font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                } else if let mismatchStatus = currentROM.raMatchStatus, mismatchStatus.hasPrefix("mismatch") {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loc.localized("achievement.versionMismatch"))
                                    .font(.headline)
                                    .foregroundColor(AppColors.textPrimary(colorScheme))
                                Text(loc.localized("achievement.romVersionMismatchInfo"))
                                    .font(.caption)
                                    .foregroundColor(AppColors.textMuted(colorScheme))
                                    .lineLimit(3)
                            }
                            Spacer()
                        }
                        if let raGameId = currentROM.raGameId {
                            Button {
                                if let url = URL(string: "https://retroachievements.org/game/\(raGameId)") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Text(loc.localized("achievement.viewOnRetroAchievements"))
                                    .font(.caption)
                            }
                            .buttonStyle(.link)
                        }
                        Button {
                            findInRA()
                        } label: {
                            Label(loc.localized("achievement.findDifferentVersion"), systemImage: "magnifyingglass")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 8)
                } else if let matchStatus = currentROM.raMatchStatus, matchStatus == "not_supported" {
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.circle").font(.system(size: 30)).foregroundColor(AppColors.textMuted(colorScheme))
                        Text(loc.localized("achievement.noAchievements")).font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("achievement.gameNotSupported")).font(.caption).foregroundColor(AppColors.textMuted(colorScheme))
                        Button {
                            findInRA()
                        } label: {
                            Label(loc.localized("achievement.searchRetroAchievements"), systemImage: "magnifyingglass")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                } else if gameAchievements.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.circle").font(.system(size: 30)).foregroundColor(AppColors.textMuted(colorScheme))
                        Text(loc.localized("achievement.noAchievementsAvailable")).font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("achievement.gameMayNotHaveRAData")).font(.caption).foregroundColor(AppColors.textMuted(colorScheme))
                        Button {
                            findInRA()
                        } label: {
                            Label(loc.localized("achievement.searchRetroAchievements"), systemImage: "magnifyingglass")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                } else {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(unlockedAchievementCount)/\(gameAchievements.count)").font(.title2).fontWeight(.bold).foregroundColor(AppColors.textPrimary(colorScheme))
                            Text(loc.localized("achievement.achievements")).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(earnedPoints)/\(totalAchievementPoints)").font(.title2).fontWeight(.bold).foregroundColor(AppColors.textPrimary(colorScheme))
                            Text(loc.localized("achievement.points")).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                        Spacer()
                        let progress = gameAchievements.isEmpty ? 0.0 : Double(unlockedAchievementCount) / Double(gameAchievements.count)
                        ProgressView(value: progress).tint(.blue).frame(width: 100)
                    }

                    Divider().overlay(AppColors.divider(colorScheme))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: 16)], spacing: 20) {
                        ForEach(gameAchievements) { achievement in
                            AchievementBadgeView(achievement: achievement)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}