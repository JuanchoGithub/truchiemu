import SwiftUI

extension GameDetailView {
    var overviewSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            descriptionCard

            if !screenshotImages.isEmpty {
                screenshotsCarousel
            }

            infoGrid

            playtimeCard

            recentSaveStatesPreview

            if achievementsService.isEnabled && !gameAchievements.isEmpty {
                achievementsSummaryCard
            }
        }
    }

    // MARK: - Description

    @ViewBuilder
    private var descriptionCard: some View {
        if let description = gameDescription, !description.isEmpty {
            ModernSectionCard(showHeader: false) {
                Text(description)
                    .font(.body)
                    .foregroundColor(AppColors.textPrimary(colorScheme).opacity(0.85))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ModernSectionCard(showHeader: false) {
                HStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .foregroundColor(AppColors.textMuted(colorScheme))
                    Text(loc.localized("gameDetail.noDescription"))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Screenshots carousel

    private var screenshotsCarousel: some View {
        ModernSectionCard(
            title: loc.localized("gameInfo.screenshots"),
            icon: "photo.on.rectangle"
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(screenshotImages.indices, id: \.self) { index in
                        Image(nsImage: screenshotImages[index])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 240, height: 160)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                            )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Info grid

    @ViewBuilder
    private var infoGrid: some View {
        let meta = currentROM.metadata
        let hasAnyField = meta?.developer != nil
            || meta?.publisher != nil
            || currentROM.metadata?.year != nil
            || meta?.genre != nil
            || (meta?.players ?? 0) > 0
            || meta?.cooperative == true
            || meta?.esrbRating != nil

        if hasAnyField {
            ModernSectionCard(
                title: loc.localized("gameDetail.gameInfo"),
                icon: "info.circle"
            ) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppSpacing.lg),
                        GridItem(.flexible(), spacing: AppSpacing.lg)
                    ],
                    alignment: .leading,
                    spacing: AppSpacing.md
                ) {
                    if let dev = meta?.developer {
                        infoField(loc.localized("gameInfo.developer"), dev)
                    }
                    if let pub = meta?.publisher {
                        infoField(loc.localized("gameInfo.publisher"), pub)
                    }
                    if let year = currentROM.metadata?.year {
                        infoField(loc.localized("gameInfo.year"), year)
                    }
                    if let genre = meta?.genre {
                        infoField(loc.localized("gameInfo.genre"), GenreManager.shared.effectiveDisplayName(for: genre))
                    }
                    if (meta?.players ?? 0) > 0 {
                        infoField(loc.localized("gameInfo.players"), "\(meta?.players ?? 1)")
                    }
                    if meta?.cooperative == true {
                        infoField(loc.localized("gameInfo.coop"), loc.localized("gameInfo.yes"))
                    }
                    if let esrb = meta?.esrbRating {
                        infoField(loc.localized("gameInfo.esrb"), esrb)
                    }
                }
            }
        }
    }

    private func infoField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textTertiary(colorScheme))
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textPrimary(colorScheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Playtime

    @ViewBuilder
    private var playtimeCard: some View {
        let lastPlayed = currentROM.lastPlayed
        let times = currentROM.timesPlayed
        let total = currentROM.totalPlaytimeSeconds

        // Only show if there is something meaningful to display.
        if lastPlayed != nil || times > 0 || total > 0 {
            ModernSectionCard(
                title: loc.localized("gameDetail.playtime"),
                icon: "clock"
            ) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let last = lastPlayed {
                            Text(loc.localized("gameDetail.lastPlayedAt")
                                .replacingOccurrences(of: "{date}", with: Self.relativeDateFormatter.localizedString(for: last, relativeTo: Date())))
                                .font(.subheadline)
                                .foregroundColor(AppColors.textPrimary(colorScheme))
                        }
                        Text(playtimeSummary(times: times, total: total))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    Spacer()
                    Button {
                        launchGame(disableAutoLoadOnStart: true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text(loc.localized("header.play"))
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.textOnAccent(colorScheme))
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppDecorativeGradients.buttonPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func playtimeSummary(times: Int, total: Double) -> String {
        var parts: [String] = []
        if times > 0 {
            parts.append(loc.localized("gameDetail.playCount")
                .replacingOccurrences(of: "{count}", with: "\(times)"))
        }
        if total > 0, let played = Self.playtimeFormatter.string(from: total) {
            parts.append(played)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Recent save states

    private var recentSaveStatesPreview: some View {
        guard let slot = mostRecentSaveSlot, slot.exists else { return AnyView(EmptyView()) }

        return AnyView(
            ModernSectionCard(
                title: loc.localized("gameDetail.recentSaves"),
                icon: "externaldrive",
                headerTrailing: AnyView(
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSection = .savedStates
                        }
                    } label: {
                        Text(loc.localized("gameDetail.manageAllSaves"))
                            .font(.caption)
                            .foregroundColor(AppColors.brandAccent)
                    }
                    .buttonStyle(.plain)
                )
            ) {
                HStack(spacing: 12) {
                    ModernSaveStateSlotView(
                        slot: slot,
                        rom: currentROM,
                        saveStateManager: saveStateManager,
                        onDelete: { loadMostRecentSaveState() },
                        onLaunchSlot: { slotId, _ in
                            launchGame(slotToLoad: slotId)
                        }
                    )
                    .frame(width: 104)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.localized("gameDetail.recentSaveHint"))
                            .font(.subheadline)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                        if let date = slot.modificationDate {
                            Text(loc.localized("gameDetail.lastSavedAt")
                                .replacingOccurrences(of: "{date}", with: Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())))
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                    }
                    Spacer()
                    Button {
                        launchGame(slotToLoad: slot.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                            Text(loc.localized("header.continue"))
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.textOnAccent(colorScheme))
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.brandAccent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        )
    }

    // MARK: - Achievements summary

    @ViewBuilder
    private var achievementsSummaryCard: some View {
        let earned = unlockedAchievementCount
        let total = gameAchievements.count
        let earnedPts = earnedPoints
        let totalPts = totalAchievementPoints

        ModernSectionCard(
            title: loc.localized("gameDetail.achievementsSummary"),
            icon: "trophy",
            headerTrailing: AnyView(
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedSection = .achievements
                    }
                } label: {
                    Text(loc.localized("gameDetail.viewAllAchievements"))
                        .font(.caption)
                        .foregroundColor(AppColors.brandAccent)
                }
                .buttonStyle(.plain)
            )
        ) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(earned)/\(total) · \(earnedPts)/\(totalPts) \(loc.localized("gameDetail.points"))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                    if total > 0 {
                        ProgressView(value: Double(earned), total: Double(total))
                            .frame(width: 160)
                            .tint(AppColors.brandAccent)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Formatters

    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current
        f.dateTimeStyle = .named
        return f
    }()

    private static let playtimeFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        return f
    }()
}
