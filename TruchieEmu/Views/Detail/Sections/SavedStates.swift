import SwiftUI

extension GameDetailView {
    var savedStatesSection: some View {
        ModernSectionCard(
            title: "Saved States",
            icon: "externaldrive",
            badge: slotInfoList.filter { $0.exists && $0.id >= 0 }.isEmpty ? nil : "\(slotInfoList.filter { $0.exists && $0.id >= 0 }.count)"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                let existingSlots = slotInfoList.filter { $0.exists }
                let emptySlots = slotInfoList.filter { !$0.exists && $0.id >= 0 }.prefix(10)
                let showSlots = existingSlots.isEmpty ? Array(emptySlots) : slotInfoList.filter { $0.id >= 0 }

                if showSlots.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive.slash").font(.system(size: 30)).foregroundColor(.white.opacity(0.3))
                        Text("No saved states").font(.subheadline).foregroundColor(.white.opacity(0.5))
                        Text("Save states created during gameplay").font(.caption).foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                        spacing: 12
                    ) {
                        ForEach(showSlots.filter { $0.id >= 0 }, id: \.id) { slot in
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

                if !existingSlots.isEmpty {
                    Divider().overlay(dividerColor)
                    HStack {
                        Text("\(existingSlots.count) save state(s)").font(.caption).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        let totalSize = existingSlots.reduce(0) { $0 + ($1.fileSize ?? 0) }
                        if totalSize > 0 {
                            Text(Int64(totalSize).formattedByteSize).font(.caption).foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
            }
        }
    }
}