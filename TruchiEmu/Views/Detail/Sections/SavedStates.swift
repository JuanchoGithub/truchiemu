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

                            if expandedProgressiveSlotID == autoSlot.id {
                                ProgressiveSaveStateExpandedView(
                                    slot: autoSlot,
                                    progressives: progressiveSlots[autoSlot.id] ?? [],
                                    rom: currentROM,
                                    saveStateManager: saveStateManager,
                                    onDelete: { loadSlotInfo() },
                                    onLaunchSlot: { slotId, progVersion in
                                        launchGame(slotToLoad: slotId, progressiveVersion: progVersion)
                                    }
                                )
                                .transition(.opacity)
                            }
                        }

                        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
                        let chunkSize = 5
                        ForEach(Array(stride(from: 0, to: showUserSlots.count, by: chunkSize)), id: \.self) { rowIndex in
                            let chunk = Array(showUserSlots[rowIndex..<min(rowIndex + chunkSize, showUserSlots.count)])

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(chunk, id: \.id) { slot in
                                    slotView(for: slot)
                                }
                            }

                            if let expandedID = expandedProgressiveSlotID,
                               let expandedSlot = chunk.first(where: { $0.id == expandedID }) {
                                ProgressiveSaveStateExpandedView(
                                    slot: expandedSlot,
                                    progressives: progressiveSlots[expandedSlot.id] ?? [],
                                    rom: currentROM,
                                    saveStateManager: saveStateManager,
                                    onDelete: { loadSlotInfo() },
                                    onLaunchSlot: { slotId, progVersion in
                                        launchGame(slotToLoad: slotId, progressiveVersion: progVersion)
                                    }
                                )
                                .transition(.opacity)
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
                },
                expandedSlotID: $expandedProgressiveSlotID
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
    @Binding var expandedSlotID: Int?
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false
    @State private var requestRename = false

    private var isExpanded: Bool { expandedSlotID == slot.id }

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
                    ProgressiveThumbnailView(
                        saveStateManager: saveStateManager,
                        rom: rom,
                        slotID: slot.id,
                        version: v,
                        isLarge: true,
                        onDelete: onDelete,
                        onRequestRename: { requestRename = true }
                    )
                    .offset(x: CGFloat(index) * offsetStep, y: CGFloat(index) * (offsetStep * 0.75))
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                SlotRenameControl(
                    slot: slot,
                    rom: rom,
                    saveStateManager: saveStateManager,
                    isHovering: isHovering,
                    isEditingRequest: $requestRename,
                    onRenamed: onDelete
                )
                Text("(\(progressives.count))")
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppColors.textTertiary(colorScheme))
            }

            stackedThumbnailView
        }
        .padding(6)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            if slot.id >= 0 {
                Button {
                    requestRename = true
                } label: {
                    Label(loc.localized("savedStates.rename"), systemImage: "pencil")
                }
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedSlotID = isExpanded ? nil : slot.id
            }
        }
    }
}

private struct ProgressiveSaveStateExpandedView: View {
    let slot: SlotInfo
    let progressives: [SlotInfo]
    let rom: ROM
    @ObservedObject var saveStateManager: SaveStateManager
    var onDelete: () -> Void
    var onLaunchSlot: (Int, Int?) -> Void
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false
    @State private var requestRename = false

    private var sortedProgressives: [SlotInfo] {
        progressives.sorted { ($0.progressiveVersion ?? 0) < ($1.progressiveVersion ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SlotRenameControl(
                    slot: slot,
                    rom: rom,
                    saveStateManager: saveStateManager,
                    isHovering: isHovering,
                    isEditingRequest: $requestRename,
                    onRenamed: onDelete
                )
                Text("(\(progressives.count))")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                Spacer()
            }

            VStack(spacing: 6) {
                ForEach(sortedProgressives, id: \.progressiveVersion) { prog in
                    if let v = prog.progressiveVersion {
                        progressiveRowView(for: prog, version: v)
                    }
                }
            }
        }
        .padding(12)
        .background(AppColors.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.brandAccent.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            if slot.id >= 0 {
                Button {
                    requestRename = true
                } label: {
                    Label(loc.localized("savedStates.rename"), systemImage: "pencil")
                }
            }
        }
    }

    @ViewBuilder
    private func progressiveRowView(for info: SlotInfo, version: Int) -> some View {
        HStack(spacing: 12) {
            ProgressiveThumbnailView(
                saveStateManager: saveStateManager,
                rom: rom,
                slotID: slot.id,
                version: version,
                isLarge: true,
                onDelete: onDelete,
                onRequestRename: { requestRename = true }
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("#\(version)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                if let date = info.formattedDate {
                    Text(date)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                }
                if let size = info.fileSize {
                    Text(Int64(size).formattedByteSize)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                }
            }

            Spacer()

            Button {
                onLaunchSlot(slot.id, version)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppColors.brandAccent)
            }
            .buttonStyle(.plain)
            .liquidGlassSheen()
        }
        .padding(.vertical, 4)
    }
}

private struct ProgressiveThumbnailView: View {
    let saveStateManager: SaveStateManager
    let rom: ROM
    let slotID: Int
    let version: Int
    let isLarge: Bool
    var onDelete: () -> Void
    var onRequestRename: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        let gameName = "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"
        let systemID = rom.systemID ?? ""
        let thumb = saveStateManager.loadProgressiveThumbnail(gameName: gameName, systemID: systemID, slot: slotID, version: version)
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
            if slotID >= 0 {
                Button {
                    onRequestRename()
                } label: {
                    Label(loc.localized("savedStates.rename"), systemImage: "pencil")
                }
            }
            Button(action: {
                let gameKey = "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"
                try? saveStateManager.deleteProgressiveState(gameName: gameKey, systemID: rom.systemID ?? "", slot: slotID, version: version)
                onDelete()
            }) {
                Label(loc.localized("saveState.delete"), systemImage: "trash")
            }
        }
    }
}
