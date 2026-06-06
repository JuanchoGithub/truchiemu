import SwiftUI

extension GameDetailView {
    var coreSection: some View {
        ModernSectionCard(title: loc.localized("core.title"), icon: "cpu") {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "cpu").foregroundColor(AppColors.brandAccent).frame(width: 20)
                    Text(loc.localized("core.emulationCore"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary(colorScheme))
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
                .padding(.vertical, AppSpacing.xs)

                Divider().overlay(AppColors.divider(colorScheme))

                HStack {
                    Image(systemName: "globe").foregroundColor(AppColors.brandAccent).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("core.applyToSystemDefault"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                    Spacer()
                    Toggle("", isOn: $applyCoreToSystem)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                }
                .padding(.vertical, AppSpacing.xs)

                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "info.circle").foregroundColor(AppColors.textMuted(colorScheme)).font(.caption)
                    Text(applyCoreToSystem
                         ? loc.localized("core.changeSystemCoreWarning").replacingOccurrences(of: "{0}", with: systemName)
                         : loc.localized("core.onlyThisGameUsesSelectedCore"))
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                        .lineSpacing(2)
                }
                .padding(.vertical, AppSpacing.xs)

                Divider().overlay(AppColors.divider(colorScheme))

                HStack {
                    Spacer()
                    Button {
                        if let coreID = activeCoreID {
                            openWindow(id: "core-options", value: coreID)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3")
                            Text(loc.localized("gameInfo.coreOptions"))
                        }
                        .font(.subheadline)
                        .foregroundColor(AppColors.brandAccent)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.brandAccent.opacity(0.15))
                        .cornerRadius(AppRadius.md)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCoreID == nil || installedCores.isEmpty)

                    Button { applyCoreConfiguration() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: applyCoreToSystem ? "globe" : "gamecontroller")
                            Text(applyCoreToSystem ? loc.localized("core.setSystemDefault") : loc.localized("core.setForThisGame"))
                        }
                        .font(.subheadline)
                        .foregroundColor(AppColors.textOnAccent(colorScheme))
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.brandAccent)
                        .cornerRadius(AppRadius.md)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCoreID == nil || installedCores.isEmpty)
                }
                .padding(.vertical, AppSpacing.xs)
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
            VStack(alignment: .leading, spacing: 0) {
                if isAchievementsLoading {
                    HStack(spacing: AppSpacing.md) {
                        ProgressView().controlSize(.small)
                        Text(loc.localized("achievement.loadingAchievements")).font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.xl)
                } else if let mismatchStatus = currentROM.raMatchStatus, mismatchStatus.hasPrefix("mismatch") {
                    VStack(spacing: AppSpacing.md) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(AppColors.warning(colorScheme))
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text(loc.localized("achievement.versionMismatch"))
                                    .font(.headline)
                                    .foregroundColor(AppColors.textPrimary(colorScheme))
                                Text(loc.localized("achievement.romVersionMismatchInfo"))
                                    .font(.caption)
                                    .foregroundColor(AppColors.textTertiary(colorScheme))
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
                    .padding(.vertical, AppSpacing.sm)
                } else if let matchStatus = currentROM.raMatchStatus, matchStatus == "not_supported" {
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "trophy.circle").font(.system(size: 30)).foregroundColor(AppColors.textMuted(colorScheme))
                        Text(loc.localized("achievement.noAchievements")).font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("achievement.gameNotSupported")).font(.caption).foregroundColor(AppColors.textTertiary(colorScheme))
                        Button {
                            findInRA()
                        } label: {
                            Label(loc.localized("achievement.searchRetroAchievements"), systemImage: "magnifyingglass")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, AppSpacing.xxs)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.xl)
                } else if gameAchievements.isEmpty {
                    VStack(spacing: AppSpacing.sm) {
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
                        .padding(.top, AppSpacing.xxs)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.xl)
                } else {
                    HStack(spacing: AppSpacing.xl2) {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text("\(unlockedAchievementCount)/\(gameAchievements.count)").font(.title2).fontWeight(.bold).foregroundColor(AppColors.textPrimary(colorScheme))
                            Text(loc.localized("achievement.achievements")).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text("\(earnedPoints)/\(totalAchievementPoints)").font(.title2).fontWeight(.bold).foregroundColor(AppColors.textPrimary(colorScheme))
                            Text(loc.localized("achievement.points")).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                        Spacer()
                        let progress = gameAchievements.isEmpty ? 0.0 : Double(unlockedAchievementCount) / Double(gameAchievements.count)
                        ProgressView(value: progress).frame(width: 100)

                        Picker(selection: $achievementViewMode) {
                            ForEach(AchievementViewMode.allCases, id: \.self) { mode in
                                Image(systemName: mode.icon).tag(mode)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)
                    }.padding(.vertical, AppSpacing.xs)

                    Divider().overlay(AppColors.divider(colorScheme))

                    if achievementViewMode == .grid {
                        achievementGridView
                    } else {
                        achievementListView
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var achievementGridView: some View {
        let sorted = sortedAchievements
        let columns = [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: AppSpacing.xl)]
        let chunkSize = max(1, Int(achievementGridWidth) / (64 + Int(AppSpacing.xl)))

        VStack(spacing: AppSpacing.xl2) {
            ForEach(Array(stride(from: 0, to: sorted.count, by: chunkSize)), id: \.self) { rowIndex in
                let chunk = Array(sorted[rowIndex..<(min(rowIndex + chunkSize, sorted.count))])

                LazyVGrid(columns: columns, spacing: AppSpacing.xl2) {
                    ForEach(chunk, id: \.id) { achievement in
                        AchievementBadgeView(achievement: achievement, expandedAchievementID: $expandedAchievementID)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedAchievementID == achievement.id {
                                        expandedAchievementID = nil
                                    } else {
                                        expandedAchievementID = achievement.id
                                    }
                                }
                            }
                    }
                }

                if let expandedID = expandedAchievementID,
                   let expandedAchievement = sorted.first(where: { $0.id == expandedID }),
                   chunk.contains(where: { $0.id == expandedID }) {
                    AchievementExpandedDetailView(achievement: expandedAchievement)
                        .transition(.opacity)
                }
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .background(GeometryReader { geo in
            Color.clear.onChange(of: geo.size.width) { _, newWidth in
                achievementGridWidth = newWidth
            }
        })
    }

    @ViewBuilder
    private var achievementListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(sortedAchievements) { achievement in
                    AchievementRowView(achievement: achievement)
                }
            }
            .padding(.vertical, AppSpacing.sm)
        }
    }

    private var sortedAchievements: [Achievement] {
        gameAchievements.sorted {
            if $0.isUnlocked != $1.isUnlocked {
                return $0.isUnlocked
            }
            if $0.isUnlocked && $1.isUnlocked {
                if let d0 = $0.unlockDate, let d1 = $1.unlockDate {
                    return d0 > d1
                }
                if $0.unlockDate != nil { return true }
                if $1.unlockDate != nil { return false }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func loadAchievementViewMode() {
        let perGameKey = "achievementViewMode_\(currentROM.id.uuidString)"
        if let perGame = AppSettings.getString(perGameKey),
           let mode = AchievementViewMode(rawValue: perGame) {
            achievementViewMode = mode
        } else if let global = AppSettings.getString("achievementViewMode"),
                  let mode = AchievementViewMode(rawValue: global) {
            achievementViewMode = mode
        } else {
            achievementViewMode = .grid
        }
    }
}
