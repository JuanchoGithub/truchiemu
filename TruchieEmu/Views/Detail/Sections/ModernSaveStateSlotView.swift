import SwiftUI

// MARK: - Modern Save State Slot View

struct ModernSaveStateSlotView: View {
    let slot: SlotInfo
    let rom: ROM
    @ObservedObject var saveStateManager: SaveStateManager
    var onDelete: () -> Void
    var onLaunchSlot: (Int) -> Void = { _ in }
    @State private var thumbnail: NSImage?
    @State private var showPlayButton = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var slotBgColor: Color {
        colorScheme == .dark ? .white.opacity(0.05) : .secondary.opacity(0.04)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Thumbnail or placeholder
                ZStack {
                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(slotBgColor)
                            .overlay(
                                Image(systemName: slot.exists ? "externaldrive.fill" : "externaldrive")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.3))
                            )
                    }
                }
                .frame(width: 70, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Play button overlay (appears on single-click for saved slots)
                if slot.exists && showPlayButton {
                    Button {
                        onLaunchSlot(slot.id)
                    } label: {
                        ZStack {
                            Color.black.opacity(0.6)
                            VStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                Text("Play")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(slot.exists ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )

            // Slot number
            Text(slot.displayName)
                .font(.caption)
                .fontWeight(slot.exists ? .semibold : .regular)
                .foregroundColor(slot.exists ? .white.opacity(0.85) : .white.opacity(0.4))

            // Date and size info
            if let date = slot.formattedDate {
                Text(date)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            } else if let fileSize = slot.fileSize {
                Text(fileSize.formattedByteSize)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(width: 74)
        // Single tap: show play button
        .onTapGesture(count: 1) {
            if slot.exists {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showPlayButton = true
                }
            }
        }
        // Double tap: launch game and load this slot directly
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    if slot.exists {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showPlayButton = false
                        }
                        onLaunchSlot(slot.id)
                    }
                }
        )
        // Dismiss play button when tapping elsewhere
        .onChange(of: showPlayButton) { _, _ in
            if showPlayButton {
                // Auto-dismiss after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showPlayButton = false
                    }
                }
            }
        }
        .contextMenu {
            if slot.exists {
                Button(action: {
                    if slot.id >= 0 {
                        try? saveStateManager.deleteState(
                            gameName: rom.displayName,
                            systemID: rom.systemID ?? "",
                            slot: slot.id
                        )
                        onDelete()
                    }
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .task {
            if slot.exists {
                thumbnail = saveStateManager.loadThumbnail(
                    gameName: rom.displayName,
                    systemID: rom.systemID ?? "",
                    slot: slot.id
                )
            }
        }
    }
}