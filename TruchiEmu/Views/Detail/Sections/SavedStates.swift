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
                            ModernSaveStateSlotView(
                                slot: autoSlot,
                                rom: currentROM,
                                saveStateManager: saveStateManager,
                                onDelete: { loadSlotInfo() },
                                onLaunchSlot: { slotId in launchGame(slotToLoad: slotId) }
                            )
                            Spacer()
                        }
                    }

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                        spacing: 12
                    ) {
                        ForEach(showUserSlots, id: \.id) { slot in
                            ModernSaveStateSlotView(
                                slot: slot,
                                rom: currentROM,
                                saveStateManager: saveStateManager,
                                onDelete: { loadSlotInfo() },
                                onLaunchSlot: { slotId in launchGame(slotToLoad: slotId) }
                            )
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
}
