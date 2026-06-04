import SwiftUI

extension GameDetailView {
    var savedStatesSection: some View {
        ModernSectionCard(
            title: loc.localized("savedStates.title"),
            icon: "externaldrive",
            badge: slotInfoList.filter { $0.exists }.isEmpty ? nil : "\(slotInfoList.filter { $0.exists }.count)"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                let autoSlot = slotInfoList.first { $0.id == -1 }
                let userSlots = slotInfoList.filter { $0.id >= 0 }
                let existingSlots = slotInfoList.filter { $0.exists }
                let emptyUserSlots = slotInfoList.filter { !$0.exists && $0.id >= 0 }.prefix(10)
                let showUserSlots = userSlots.isEmpty ? Array(emptyUserSlots) : userSlots

                if slotInfoList.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive.slash").font(.system(size: 30)).foregroundColor(AppColors.textTertiary(colorScheme))
                        Text(loc.localized("savedStates.noSavedStates")).font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("savedStates.savedStatesCreatedDuringGameplay")).font(.caption).foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                    .padding(.vertical, AppSpacing.xs)
                } else {
                    VStack(spacing: 12) {
                        if let autoSlot = autoSlot {
                            HStack {
                                Spacer()
                                slotView(for: autoSlot)
                                Spacer()
                            }
                        }

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                            spacing: 12
                        ) {
                            ForEach(showUserSlots, id: \.id) { slot in
                                slotView(for: slot)
                            }
                        }
                    }
                }

                if !existingSlots.isEmpty {
                    Divider().overlay(AppColors.divider(colorScheme))
                    HStack {
                        Text("\(existingSlots.count) \(loc.localized("savedStates.saveStateCount"))").font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        Spacer()
                        let totalSize = existingSlots.reduce(0) { $0 + ($1.fileSize ?? 0) }
                        if totalSize > 0 {
                            Text(Int64(totalSize).formattedByteSize).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
    }

    @ViewBuilder
    private func slotView(for slot: SlotInfo) -> some View {
        let progressives = progressiveSlots[slot.id] ?? []
        if !progressives.isEmpty {
            ProgressiveSlotStackView(
                slot: slot,
                progressives: progressives,
                rom: currentROM,
                saveStateManager: saveStateManager,
                onDelete: { loadSlotInfo() },
                onLaunchSlot: { slotId, progVersion in
                    launchGame(slotToLoad: slotId, progressiveVersion: progVersion)
                }
            )
        } else {
            ModernSaveStateSlotView(
                slot: slot,
                rom: currentROM,
                saveStateManager: saveStateManager,
                onDelete: { loadSlotInfo() },
                onLaunchSlot: { slotId, _ in
                    launchGame(slotToLoad: slotId)
                }
            )
        }
    }
}

private struct ProgressiveSlotStackView: View {
    let slot: SlotInfo
    let progressives: [SlotInfo]
    let rom: ROM
    @ObservedObject var saveStateManager: SaveStateManager
    var onDelete: () -> Void
    var onLaunchSlot: (Int, Int?) -> Void
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    private var sortedProgressives: [SlotInfo] {
        progressives.sorted { ($0.progressiveVersion ?? 0) < ($1.progressiveVersion ?? 0) }
    }

    private var stackedThumbnailView: some View {
        let displayCount = min(sortedProgressives.count, 4)
        let visible = Array(sortedProgressives.suffix(displayCount))
        let offsetStep: CGFloat = 5

        return ZStack(alignment: .topLeading) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, prog in
                if let v = prog.progressiveVersion {
                    progressiveThumbnailView(for: prog, version: v, isLarge: true)
                        .offset(x: CGFloat(index) * offsetStep, y: CGFloat(index) * (offsetStep * 0.75))
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(slot.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                Text("(\(progressives.count))")
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppColors.textTertiary(colorScheme))
            }

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(sortedProgressives, id: \.progressiveVersion) { prog in
                        if let v = prog.progressiveVersion {
                            progressiveRowView(for: prog, version: v)
                        }
                    }
                }
            } else {
                stackedThumbnailView
            }
        }
        .padding(6)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        }
    }

    @ViewBuilder
    private func progressiveRowView(for info: SlotInfo, version: Int) -> some View {
        HStack(spacing: 8) {
            progressiveThumbnailView(for: info, version: version, isLarge: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("#\(version)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.textPrimary(colorScheme))

                if let date = info.formattedDate {
                    Text(date)
                        .font(.system(size: 8))
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                }

                if let size = info.fileSize {
                    Text(Int64(size).formattedByteSize)
                        .font(.system(size: 8))
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                }
            }

            Spacer()

            Button {
                onLaunchSlot(slot.id, version)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.brandAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func progressiveThumbnailView(for info: SlotInfo, version: Int, isLarge: Bool) -> some View {
        let thumb = saveStateManager.loadProgressiveThumbnail(gameName: "\(rom.displayName)__\(rom.id.uuidString.prefix(8))", systemID: rom.systemID ?? "", slot: slot.id, version: version)
        ZStack {
            if let thumb = thumb {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: isLarge ? 96 : 40, height: isLarge ? 72 : 30)
                    .clipped()
            } else {
                Rectangle()
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
                    .frame(width: isLarge ? 96 : 40, height: isLarge ? 72 : 30)
                    .overlay(
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: isLarge ? 20 : 10))
                            .foregroundColor(AppColors.textMuted(colorScheme))
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppColors.brandAccent.opacity(0.3), lineWidth: 1)
        )
        .overlay(
            Text("#\(version)")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(2),
            alignment: .topLeading
        )
        .contextMenu {
            Button(action: {
                try? saveStateManager.deleteProgressiveState(gameName: rom.displayName, systemID: rom.systemID ?? "", slot: slot.id, version: version)
                onDelete()
            }) {
                Label(loc.localized("saveState.delete"), systemImage: "trash")
            }
        }
    }
}
