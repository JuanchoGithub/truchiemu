import SwiftUI

// MARK: - Slot Picker Sheet

/// Sheet that shows all save slots (0-9) with thumbnails and info
struct SlotPickerSheet: View {
    @ObservedObject var runner: EmulatorRunner
    @Binding var showSlotPicker: Bool
    @State private var slotInfoList: [SlotInfo] = []
    @State private var slotThumbnails: [Int: NSImage] = [:]
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Save State Slots", systemImage: "externaldrive")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { showSlotPicker = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "number.circle.fill").foregroundColor(.blue)
                    Text("Slot \(runner.currentSlot)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                
                Spacer()
                
                if runner.supportsSaveStates {
                    Label("Available", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("Unavailable", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            Toggle(isOn: Binding(
                get: { AppSettings.getBool("saveState_compress", defaultValue: false) },
                set: { AppSettings.setBool("saveState_compress", value: $0) }
            )) {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox").foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Compress Save States").font(.subheadline)
                        Text("Reduces disk space but may take slightly longer to save and load.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            
            Divider()
            
            if runner.supportsSaveStates {
                slotsGrid
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Save states unavailable")
                        .font(.headline)
                    Text("This emulation core doesn't support save states. Try using the game's built-in save feature instead.")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .padding(40)
            }
            
            Divider()
            
            HStack {
                Button(action: { runner.previousSlot(); showSlotPicker = false }) {
                    Label("Previous", systemImage: "minus.circle").font(.subheadline)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: { runner.nextSlot(); showSlotPicker = false }) {
                    Label("Next", systemImage: "plus.circle").font(.subheadline)
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                ForEach(0..<10) { slot in
                    SlotCardView(slot: slot, slotInfo: slotInfo(for: slot), thumbnail: slotThumbnails[slot], isCurrentSlot: slot == runner.currentSlot, onSave: { saveToSlot(slot) }, onLoad: { loadFromSlot(slot) }, onDelete: { deleteFromSlot(slot) })
                }
            }
            .padding()
        }
    }
    
    private func slotInfo(for slot: Int) -> SlotInfo? { slotInfoList.first { $0.id == slot } }
    private func refreshSlotInfo() { guard let rom = runner.rom else { return }; slotInfoList = runner.saveManager.allSlotInfo(gameName: rom.displayName, systemID: rom.systemID ?? "default") }
    private func loadThumbnails() {
        guard let rom = runner.rom else { return }
        let systemID = rom.systemID ?? "default"
        for slot in 0..<10 {
            if let thumbnail = runner.saveManager.loadThumbnail(gameName: rom.displayName, systemID: systemID, slot: slot) {
                slotThumbnails[slot] = thumbnail
            }
        }
    }
    private func saveToSlot(_ slot: Int) { let success = runner.saveState(slot: slot); if success { refreshSlotInfo(); loadThumbnails() } }
    private func loadFromSlot(_ slot: Int) { let success = runner.loadState(slot: slot); if success { showSlotPicker = false } }
    private func deleteFromSlot(_ slot: Int) {
        guard let rom = runner.rom else { return }
        do {
            try runner.saveManager.deleteState(gameName: rom.displayName, systemID: rom.systemID ?? "default", slot: slot)
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
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill).frame(height: 80).clipped()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 80)
                        .overlay(VStack {
                            Image(systemName: slotInfo?.exists == true ? "square.and.arrow.down" : "plus.circle")
                                .font(.system(size: 24)).foregroundColor(.secondary)
                            Text(slotInfo?.exists == true ? "Preview unavailable" : "No save in this slot")
                                .font(.caption2).foregroundColor(.secondary)
                        })
                }
                if isCurrentSlot {
                    VStack { HStack { Image(systemName: "chevron.right.circle.fill").foregroundColor(.blue).font(.caption); Spacer() }; Spacer() }
                        .padding(4)
                }
            }
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isCurrentSlot ? Color.blue : Color.gray.opacity(0.25), lineWidth: 1.5))
            
            HStack {
                Text("Slot \(slot)").font(.caption).fontWeight(isCurrentSlot ? .bold : .medium).foregroundColor(isCurrentSlot ? .blue : .primary)
                Spacer()
                if slotInfo?.exists == true { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundColor(.green) }
            }
            
            if let info = slotInfo, info.exists, let size = info.fileSize {
                Text(size.formattedByteSize).font(.caption2).foregroundColor(.secondary)
            }
            
            HStack(spacing: 4) {
                Button(action: onSave) { Image(systemName: "square.and.arrow.down").font(.caption) }
                    .buttonStyle(.borderless).help("Save to Slot \(slot)")
                Button(action: onLoad) { Image(systemName: "square.and.arrow.up").font(.caption) }
                    .buttonStyle(.borderless).disabled(slotInfo?.exists != true).help("Load from Slot \(slot)")
                Button(action: onDelete) { Image(systemName: "trash").font(.caption) }
                    .buttonStyle(.borderless).disabled(slotInfo?.exists != true).help("Delete Slot \(slot)")
            }
            .foregroundColor(.secondary)
        }
        .padding(6)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}