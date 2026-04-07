import SwiftUI

// MARK: - Saved States Section Component

struct SavedStatesSection: View {
    let rom: ROM
    let library: ROMLibrary
    let slotInfoList: [SlotInfo]
    var onSlotDelete: (() -> Void)? = nil
    var onLaunchSlot: ((Int) -> Void)? = nil
    @StateObject private var saveStateManager = SaveStateManager()
    @Environment(\.colorScheme) private var colorScheme
    private var t: ThemeColors { ThemeColors.for(colorScheme) }

    var body: some View {
        ModernSectionCard(
            title: "Saved States",
            icon: "externaldrive",
            badge: savedSlotCount > 0 ? "\(savedSlotCount)" : nil
        ) {
            VStack(alignment: .leading, spacing: 14) {
                let existingSlots = slotInfoList.filter { $0.exists }
                let emptySlots = slotInfoList.filter { !$0.exists && $0.id >= 0 }.prefix(10)
                let showSlots = existingSlots.isEmpty ? Array(emptySlots) : slotInfoList.filter { $0.id >= 0 }

                if showSlots.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive.slash")
                            .font(.system(size: 30))
                            .foregroundColor(t.iconMuted)
                        Text("No saved states")
                            .font(.subheadline)
                            .foregroundColor(t.textSecondary)
                        Text("Save states created during gameplay")
                            .font(.caption)
                            .foregroundColor(t.textMuted)
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
                                rom: rom,
                                saveStateManager: saveStateManager,
                                onDelete: { onSlotDelete?() },
                                onLaunchSlot: { slotId in onLaunchSlot?(slotId) }
                            )
                        }
                    }
                }

                if !existingSlots.isEmpty {
                    Divider().overlay(t.divider)

                    HStack {
                        Text("\(existingSlots.count) save state(s)")
                            .font(.caption)
                            .foregroundColor(t.textSecondary)
                        Spacer()
                        let totalSize = existingSlots.reduce(0) { $0 + ($1.fileSize ?? 0) }
                        if totalSize > 0 {
                            Text(Int64(totalSize).formattedByteSize)
                                .font(.caption)
                                .foregroundColor(t.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var savedSlotCount: Int {
        slotInfoList.filter { $0.exists && $0.id >= 0 }.count
    }
}