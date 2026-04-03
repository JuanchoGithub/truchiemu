import SwiftUI

// MARK: - Slot Picker Sheet

/// Sheet that shows all save slots (0-9) with thumbnails and info
/// Allows user to save, load, or delete from any slot
struct SlotPickerSheet: View {
    @ObservedObject var runner: EmulatorRunner
    @Binding var showSlotPicker: Bool
    @State private var slotInfoList: [SlotInfo] = []
    @State private var slotThumbnails: [Int: NSImage] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Save State Slots")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Close") {
                    showSlotPicker = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            
            Divider()
            
            // Current slot indicator
            HStack {
                Text("Current Slot: \(runner.currentSlot)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if runner.supportsSaveStates {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Save States Supported")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Not Supported")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Compression toggle
            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "compress_save_states") },
                set: { UserDefaults.standard.set($0, forKey: "compress_save_states") }
            )) {
                HStack {
                    Image(systemName: "archivebox")
                    Text("Compress Save States")
                }
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
            
            // Slot grid or unsupported message
            if runner.supportsSaveStates {
                slotsGrid
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Save states are not supported for this core")
                        .font(.headline)
                    Spacer()
                }
                .padding(40)
            }
            
            Divider()
            
            // Footer actions
            HStack {
                Button(action: { runner.previousSlot(); showSlotPicker = false }) {
                    Label("Previous Slot", systemImage: "minus.circle")
                }
                
                Spacer()
                
                Button(action: { runner.nextSlot(); showSlotPicker = false }) {
                    Label("Next Slot", systemImage: "plus.circle")
                }
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            refreshSlotInfo()
            loadThumbnails()
        }
    }
    
    // MARK: - Slot Grid View
    
    @ViewBuilder
    var slotsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                spacing: 12
            ) {
                ForEach(0..<10) { slot in
                    SlotCardView(
                        slot: slot,
                        slotInfo: slotInfo(for: slot),
                        thumbnail: slotThumbnails[slot],
                        isCurrentSlot: slot == runner.currentSlot,
                        onSave: { saveToSlot(slot) },
                        onLoad: { loadFromSlot(slot) },
                        onDelete: { deleteFromSlot(slot) }
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helpers
    
    private func slotInfo(for slot: Int) -> SlotInfo? {
        slotInfoList.first { $0.id == slot }
    }
    
    private func refreshSlotInfo() {
        guard let rom = runner.rom else { return }
        let systemID = rom.systemID ?? "default"
        slotInfoList = runner.saveManager.allSlotInfo(gameName: rom.displayName, systemID: systemID)
    }
    
    private func loadThumbnails() {
        guard let rom = runner.rom else { return }
        let systemID = rom.systemID ?? "default"
        
        for slot in 0..<10 {
            if let thumbnail = runner.saveManager.loadThumbnail(
                gameName: rom.displayName,
                systemID: systemID,
                slot: slot
            ) {
                slotThumbnails[slot] = thumbnail
            }
        }
    }
    
    private func saveToSlot(_ slot: Int) {
        let success = runner.saveState(slot: slot)
        if success {
            refreshSlotInfo()
            loadThumbnails()
        }
    }
    
    private func loadFromSlot(_ slot: Int) {
        let success = runner.loadState(slot: slot)
        if success {
            showSlotPicker = false
        }
    }
    
    private func deleteFromSlot(_ slot: Int) {
        guard let rom = runner.rom else { return }
        let systemID = rom.systemID ?? "default"
        
        do {
            try runner.saveManager.deleteState(
                gameName: rom.displayName,
                systemID: systemID,
                slot: slot
            )
            slotThumbnails[slot] = nil
            refreshSlotInfo()
        } catch {
            LoggerService.debug(category: "SaveState", "Error deleting state: \(error)")
        }
    }
}

// MARK: - Slot Card View

/// Individual slot card showing thumbnail, slot number, and actions
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
            // Thumbnail area
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 80)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 80)
                        .overlay(
                            VStack {
                                Image(systemName: slotInfo?.exists == true ? "square.and.arrow.down" : "plus.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                                Text(slotInfo?.exists == true ? "No Preview" : "Empty")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        )
                }
                
                // Current slot indicator
                if isCurrentSlot {
                    VStack {
                        HStack {
                            Image(systemName: "chevron.right.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isCurrentSlot ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
            )
            
            // Slot label
            HStack {
                Text("Slot \(slot)")
                    .font(.caption)
                    .fontWeight(isCurrentSlot ? .bold : .medium)
                    .foregroundColor(isCurrentSlot ? .blue : .primary)
                
                Spacer()
                
                if slotInfo?.exists == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            // File size
            if let info = slotInfo, info.exists, let size = info.fileSize {
                Text(size.formattedByteSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Action buttons
            HStack(spacing: 4) {
                Button(action: onSave) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Save to Slot \(slot)")
                
                Button(action: onLoad) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(slotInfo?.exists != true)
                .help("Load from Slot \(slot)")
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(slotInfo?.exists != true)
                .help("Delete Slot \(slot)")
            }
            .foregroundColor(.secondary)
        }
        .padding(6)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}