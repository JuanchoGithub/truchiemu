import SwiftUI

// MARK: - Slot Picker Sheet

// Sheet that shows all save slots (-1 auto + 0-9) with thumbnails and info
struct SlotPickerSheet: View {
    @ObservedObject var runner: EmulatorRunner
    @Binding var showSlotPicker: Bool
    @State private var slotInfoList: [SlotInfo] = []
    @State private var slotThumbnails: [Int: NSImage] = [:]
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(loc.localized("slot.title"), systemImage: "externaldrive")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { showSlotPicker = false }) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "number.circle.fill").foregroundColor(AppColors.brandAccent)
                    Text(loc.localized("toolbar.selectSaveSlot"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppColors.brandAccent.opacity(0.1))
                .cornerRadius(12)
                
                Spacer()
                
                if runner.supportsSaveStates {
                    Label(loc.localized("slot.available"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
            .foregroundColor(AppColors.success(colorScheme))
        } else {
            Label(loc.localized("slot.unavailable"), systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundColor(AppColors.warning(colorScheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            Toggle(isOn: Binding(
                get: { AppSettings.getBool("saveState_compress", defaultValue: false) },
                set: { AppSettings.setBool("saveState_compress", value: $0) }
            )) {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox").foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("slot.compressSaveStates")).font(.subheadline)
            Text(loc.localized("slot.compressSaveStatesInfo"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            
Divider()
      
      if runner.supportsSaveStates {
        VStack(spacing: 0) {
          Spacer().frame(height: 12) // Add padding at the top of the first row
          slotsGrid
        }
      } else {
                VStack(spacing: 16) {
                    Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    Text(loc.localized("slot.saveStatesUnavailable"))
                        .font(.headline)
                    Text(loc.localized("slot.saveStatesUnavailableDetail"))
.font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .padding(40)
            }
            
            Divider()
            
            HStack {
                Button(action: { runner.previousSlot(); showSlotPicker = false }) {
                    Label(loc.localized("slot.previous"), systemImage: "minus.circle").font(.subheadline)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: { runner.nextSlot(); showSlotPicker = false }) {
                    Label(loc.localized("slot.next"), systemImage: "plus.circle").font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear { refreshSlotInfo(); loadThumbnails() }
    }
    
    @ViewBuilder
    var slotsGrid: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    SlotCardView(slot: -1, slotInfo: slotInfo(for: -1), thumbnail: slotThumbnails[-1], isCurrentSlot: -1 == runner.currentSlot, onSave: { saveToSlot(-1) }, onLoad: { loadFromSlot(-1) }, onDelete: { deleteFromSlot(-1) })
                    Spacer()
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    ForEach(0...9, id: \.self) { slot in
                        SlotCardView(slot: slot, slotInfo: slotInfo(for: slot), thumbnail: slotThumbnails[slot], isCurrentSlot: slot == runner.currentSlot, onSave: { saveToSlot(slot) }, onLoad: { loadFromSlot(slot) }, onDelete: { deleteFromSlot(slot) })
                    }
                }
            }
            .padding()
        }
    }
    
    private func slotInfo(for slot: Int) -> SlotInfo? { slotInfoList.first { $0.id == slot } }
    private func refreshSlotInfo() { guard let rom = runner.rom else { return }; let gameKey = "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"; slotInfoList = runner.saveManager.allSlotInfo(gameName: gameKey, systemID: rom.systemID ?? "default") }
    private func loadThumbnails() {
        guard let rom = runner.rom else { return }
        let systemID = rom.systemID ?? "default"
        let gameKey = "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"
        for slot in -1...9 {
            if let thumbnail = runner.saveManager.loadThumbnail(gameName: gameKey, systemID: systemID, slot: slot) {
                slotThumbnails[slot] = thumbnail
            }
        }
    }
    private func saveToSlot(_ slot: Int) { let success = runner.saveState(slot: slot); if success { refreshSlotInfo(); loadThumbnails() } }
    private func loadFromSlot(_ slot: Int) { let success = runner.loadState(slot: slot); if success { showSlotPicker = false } }
    private func deleteFromSlot(_ slot: Int) {
        guard let rom = runner.rom else { return }
        do {
            let gameKey = "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"
            try runner.saveManager.deleteState(gameName: gameKey, systemID: rom.systemID ?? "default", slot: slot)
            slotThumbnails[slot] = nil; refreshSlotInfo()
        } catch { LoggerService.debug(category: "SaveState", "Error deleting state: \(error)") }
    }
}

struct SlotCardView: View {
    let slot: Int
    let slotInfo: SlotInfo?
    let thumbnail: NSImage?
    let isCurrentSlot: Bool
    let onSave: () -> Void
    let onLoad: () -> Void
    let onDelete: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill).frame(height: 80).clipped()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 80)
                .overlay(VStack {
Image(systemName: slotInfo?.exists == true ? "square.and.arrow.down" : "plus.circle")
                .font(.system(size: 24)).foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    Text(slot == -1 ? loc.localized("toolbar.systemAutoSave") : (slotInfo?.exists == true ? loc.localized("slot.previewUnavailable") : loc.localized("slot.noSaveInSlot")))
.font(.caption2).foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                })
                }
                if isCurrentSlot {
                    VStack { HStack { Image(systemName: "chevron.right.circle.fill").foregroundColor(AppColors.brandAccent).font(.caption); Spacer() }; Spacer() }
                        .padding(4)
                }
            }
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isCurrentSlot ? AppColors.brandAccent : Color.gray.opacity(0.25), lineWidth: 1.5))
            
HStack {
            Text(slot == -1 ? loc.localized("toolbar.slotAuto") : slotInfo?.displayName ?? "Slot \(slot)").font(.caption).fontWeight(isCurrentSlot ? .bold : .medium).foregroundColor(isCurrentSlot ? AppColors.brandAccent : .primary)
      Spacer()
      if slotInfo?.exists == true { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundColor(AppColors.success(colorScheme)) }
    }
    
    if let info = slotInfo, info.exists, let timestamp = info.formattedDate {
      Text(timestamp)
        .font(.system(size: 9))
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                .lineLimit(1)
    } else {
      Text(" ")
        .font(.system(size: 9))
        .foregroundColor(.clear)
    }
    
    if let info = slotInfo, info.exists, let size = info.fileSize {
      Text(size.formattedByteSize).font(.caption2).foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
    } else {
      Text(" ").font(.caption2).foregroundColor(.clear)
    }
    
        HStack(spacing: 4) {
            if slot != -1 {
                Button(action: onSave) { Image(systemName: "square.and.arrow.down").font(.caption) }
                .buttonStyle(.borderless).help(loc.localized("slot.saveToSlot"))
            }
            Button(action: onLoad) { Image(systemName: "square.and.arrow.up").font(.caption) }
            .buttonStyle(.borderless).disabled(slotInfo?.exists != true).help(loc.localized("slot.loadFromSlot"))
            if slot != -1 {
                Button(action: onDelete) { Image(systemName: "trash").font(.caption) }
                .buttonStyle(.borderless).disabled(slotInfo?.exists != true).help(loc.localized("slot.deleteSlot"))
            }
        }
            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
        }
        .padding(6)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}