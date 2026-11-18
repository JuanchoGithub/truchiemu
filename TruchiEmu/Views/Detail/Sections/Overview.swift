import SwiftUI

extension GameDetailView {
    /// Narrative and media column. The fact sheet lives in the window's fixed
    /// inspector rail, so this column holds everything that benefits from the
    /// extra width.
    var overviewMainColumn: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            descriptionCard

            if !screenshotImages.isEmpty {
                mediaCard
            }

            playtimeCard

            recentSaveStatesPreview

            switchAddOnsCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Fixed inspector rail: progress, the fact sheet, and completion times.
    var overviewRail: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            if achievementsService.isEnabled && !gameAchievements.isEmpty {
                achievementsSummaryCard
            }

            infoCard

            howLongToBeatCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Description

    @ViewBuilder
    private var descriptionCard: some View {
        ModernSectionCard(
            title: loc.localized("gameDetail.about"),
            icon: "text.alignleft"
        ) {
            if let description = resolvedDescription {
                Text(description)
                    .font(.system(size: 13.5))
                    .foregroundColor(AppColors.textPrimary(colorScheme).opacity(0.9))
                    .lineSpacing(5.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
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

    /// Prefer the resolved description; fall back to the ROM's metadata so a
    /// cold SwiftData fault does not leave the card empty until the next open.
    private var resolvedDescription: String? {
        if let gameDescription, !gameDescription.isEmpty { return gameDescription }
        if let desc = currentROM.metadata?.description, !desc.isEmpty { return desc }
        return nil
    }

    // MARK: - Media

    private var mediaCard: some View {
        ModernSectionCard(
            title: loc.localized("gameInfo.screenshots"),
            icon: "photo.on.rectangle",
            badge: "\(screenshotImages.count)"
        ) {
            DetailMediaGallery(images: screenshotImages)
        }
    }

    // MARK: - Fact sheet

    private var infoCard: some View {
        ModernSectionCard(
            title: loc.localized("gameDetail.gameDetails"),
            icon: "info.circle"
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: AppSpacing.md)],
                alignment: .leading,
                spacing: AppSpacing.md
            ) {
                ForEach(specRows) { row in
                    DetailFactCell(icon: row.icon, label: row.label, value: row.value)
                }
            }
        }
    }

    /// Metadata as compact fact tiles. Each fact keeps its badge, a tiny
    /// uppercase label and a value that can wrap, so long developer and
    /// publisher names stay readable inside the narrow rail.
    private var specRows: [SpecRow] {
        let meta = currentROM.metadata
        var rows: [SpecRow] = []

        if !systemName.isEmpty {
            rows.append(SpecRow(id: "system", icon: "gamecontroller.fill",
                                label: loc.localized("gameInfo.system"), value: systemName))
        }
        if let developer = meta?.developer, !developer.isEmpty {
            rows.append(SpecRow(id: "developer", icon: "hammer.fill",
                                label: loc.localized("gameInfo.developer"), value: developer))
        }
        if let publisher = meta?.publisher, !publisher.isEmpty {
            rows.append(SpecRow(id: "publisher", icon: "building.2.fill",
                                label: loc.localized("gameInfo.publisher"), value: publisher))
        }
        if let year = meta?.year, !year.isEmpty {
            rows.append(SpecRow(id: "year", icon: "calendar",
                                label: loc.localized("gameInfo.year"), value: year))
        }
        if let genre = meta?.genre, !genre.isEmpty {
            rows.append(SpecRow(id: "genre", icon: "tag.fill",
                                label: loc.localized("gameInfo.genre"),
                                value: GenreManager.shared.effectiveDisplayName(for: genre)))
        }
        if let players = meta?.players, players > 0 {
            rows.append(SpecRow(id: "players", icon: "person.2.fill",
                                label: loc.localized("gameInfo.players"), value: "\(players)"))
        }
        if meta?.cooperative == true {
            rows.append(SpecRow(id: "coop", icon: "person.3.fill",
                                label: loc.localized("gameInfo.coop"), value: loc.localized("gameInfo.yes")))
        }
        if let esrb = meta?.esrbRating, !esrb.isEmpty {
            rows.append(SpecRow(id: "esrb", icon: "checkmark.shield.fill",
                                label: loc.localized("gameInfo.esrb"), value: esrb))
        }
        if let size = fileSize, !size.isEmpty {
            rows.append(SpecRow(id: "size", icon: "internaldrive.fill",
                                label: loc.localized("gameInfo.fileSize"), value: size))
        }

        return rows
    }

    // MARK: - Switch updates & DLC

    // Add-ons grouped under the shown game (one batch pass via
    // SwitchContentIdentifier.addOnGroups). Each row has an enable toggle;
    // disabled files stay in the library but are ignored.
    private var switchAddOns: [ROM] {
        guard currentROM.systemID == "switch", !currentROM.isSwitchAddOn else { return [] }
        // Single batch pass: per-ROM matching here is O(N^2) and hangs.
        let groups = SwitchContentIdentifier.addOnGroups(in: library.roms)
        return library.roms.filter { groups[$0.id] == currentROM.id }
            .sorted {
                ($0.switchContentType ?? "") < ($1.switchContentType ?? "")
                    || ($0.switchVersion ?? 0) < ($1.switchVersion ?? 0)
            }
    }

    @ViewBuilder
    private var switchAddOnsCard: some View {
        if !switchAddOns.isEmpty {
            ModernSectionCard(
                title: loc.localized("gameDetail.switchAddOns"),
                icon: "puzzlepiece.extension"
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(switchAddOns) { addOn in
                        HStack(spacing: 8) {
                            Text(addOn.switchContentType == "dlc"
                                ? loc.localized("gameDetail.switchDlc")
                                : loc.localized("gameDetail.switchUpdate"))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.textOnAccent(colorScheme))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.brandAccent)
                                .clipShape(Capsule())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(addOn.path.lastPathComponent)
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.textPrimary(colorScheme))
                                    .lineLimit(1)
                                if let version = addOn.switchVersion {
                                    Text("v\(version)")
                                        .font(.caption)
                                        .foregroundColor(AppColors.textSecondary(colorScheme))
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { addOn.switchEnabled },
                                set: { newValue in
                                    var updated = addOn
                                    updated.switchEnabled = newValue
                                    library.updateROM(updated)
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Playtime

    private var howLongToBeatCard: some View {
        HowLongToBeatCard(rom: currentROM)
    }

    @ViewBuilder
    private var playtimeCard: some View {
        let lastPlayed = currentROM.lastPlayed
        let times = currentROM.timesPlayed
        let total = currentROM.totalPlaytimeSeconds
        let showMeta = times > 0 || lastPlayed != nil

        // Only show if there is something meaningful to display.
        if lastPlayed != nil || times > 0 || total > 0 {
            ModernSectionCard(
                title: loc.localized("gameDetail.playtime"),
                icon: "clock",
                headerTrailing: AnyView(playPill)
            ) {
                HStack(alignment: .center, spacing: AppSpacing.xl) {
                    Text(verbatim: total > 0 ? GameDetailView.compactPlaytime(total) : "—")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .tracking(-1)
                        .monospacedDigit()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColors.brandAccent, AppColors.brandAccentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    if showMeta {
                        Rectangle()
                            .fill(AppColors.divider(colorScheme))
                            .frame(width: 1, height: 44)

                        VStack(alignment: .leading, spacing: 7) {
                            if times > 0 {
                                HStack(spacing: 7) {
                                    Image(systemName: "gamecontroller.fill")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(AppColors.brandAccent)
                                    Text(verbatim: "\(times)")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                                    Text(loc.localized("gameDetail.sessions"))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                                }
                            }

                            if let last = lastPlayed {
                                HStack(spacing: 7) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                                    Text(loc.localized("gameDetail.lastPlayedAt")
                                        .replacingOccurrences(of: "{date}", with: Self.relativeDateFormatter.localizedString(for: last, relativeTo: Date())))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var playPill: some View {
        Button {
            launchGame(disableAutoLoadOnStart: true)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(loc.localized("header.play"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundColor(AppColors.textOnAccent(colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(AppDecorativeGradients.buttonPrimary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .liquidGlassSheen()
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
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColors.brandAccent)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(AppColors.accentBackground(colorScheme)))
                    }
                    .buttonStyle(.plain)
                    .help(loc.localized("gameDetail.manageAllSaves"))
                )
            ) {
                HStack(alignment: .top, spacing: 12) {
                    ModernSaveStateSlotView(
                        slot: slot,
                        rom: currentROM,
                        saveStateManager: saveStateManager,
                        onDelete: { loadMostRecentSaveState() },
                        onLaunchSlot: { slotId, _ in
                            launchGame(slotToLoad: slotId)
                        }
                    )
                    .frame(width: 96)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(loc.localized("gameDetail.recentSaveHint"))
                            .font(.subheadline)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)

                        if let date = slot.modificationDate {
                            Text(loc.localized("gameDetail.lastSavedAt")
                                .replacingOccurrences(of: "{date}", with: Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())))
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            launchGame(slotToLoad: slot.id)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(loc.localized("header.continue"))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundColor(AppColors.textOnAccent(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(AppColors.brandAccent)
                            .clipShape(Capsule())
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .liquidGlassSheen()
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 0)
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
        let fraction = total > 0 ? Double(earned) / Double(total) : 0

        ModernSectionCard(
            title: loc.localized("gameDetail.achievementsSummary"),
            icon: "trophy"
        ) {
            VStack(spacing: AppSpacing.lg) {
                HStack(alignment: .center, spacing: 14) {
                    DetailProgressRing(
                        fraction: fraction,
                        tint: AppColors.warning(colorScheme),
                        size: 78,
                        lineWidth: 8
                    )

                    VStack(alignment: .leading, spacing: 9) {
                        achievementStat(
                            value: "\(earned)/\(total)",
                            label: loc.localized("gameDetail.achievements"),
                            icon: "trophy.fill"
                        )
                        achievementStat(
                            value: "\(earnedPts)",
                            label: loc.localized("gameDetail.points"),
                            icon: "star.fill"
                        )
                    }

                    Spacer(minLength: 0)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedSection = .achievements
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(loc.localized("gameDetail.viewAllAchievements"))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(AppColors.brandAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppColors.accentBackground(colorScheme))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func achievementStat(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(AppColors.warning(colorScheme))
                .frame(width: 18, height: 18)
                .background(Circle().fill(AppColors.warning(colorScheme).opacity(0.14)))

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                    .lineLimit(1)
                Text(verbatim: label.uppercased())
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .lineLimit(1)
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

    /// Short playtime for stat blocks ("45m", "7h 20m", "124h").
    static func compactPlaytime(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0h" }
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 || hours >= 10 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Supporting views

private struct SpecRow: Identifiable {
    let id: String
    let icon: String
    let label: String
    let value: String
}

/// Compact fact tile: tiny icon + uppercase label over a wrapping value.
/// Two or three of these fit the narrow right rail where a label/value row
/// would force the value into a truncated chip.
private struct DetailFactCell: View {
    let icon: String
    let label: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(verbatim: label.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(AppColors.textTertiary(colorScheme))

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary(colorScheme))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1)
        )
    }
}

/// Ring gauge for the achievement summary. The trim is animated so a refresh
/// after a play session sweeps to the new value instead of jumping.
private struct DetailProgressRing: View {
    let fraction: Double
    var tint: Color = AppColors.brandAccent
    var size: CGFloat = 78
    var lineWidth: CGFloat = 8

    @Environment(\.colorScheme) private var colorScheme

    private var clamped: Double {
        min(max(fraction, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(colorScheme == .dark ? 0.18 : 0.14), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, clamped))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint, tint.opacity(0.75)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(verbatim: "\(Int((clamped * 100).rounded()))%")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary(colorScheme))
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .animation(AppMotion.stateChange, value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(Int((clamped * 100).rounded()))%"))
    }
}
