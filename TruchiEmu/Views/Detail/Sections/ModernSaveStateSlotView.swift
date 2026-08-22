import SwiftUI

struct ModernSaveStateSlotView: View {
    let slot: SlotInfo
    let rom: ROM
    @ObservedObject var saveStateManager: SaveStateManager
    @ObservedObject private var loc = LocalizationManager.shared
    var onDelete: () -> Void
    var onLaunchSlot: (Int, Int?) -> Void = { _, _ in }
    @State private var thumbnail: NSImage?
    @State private var showPlayButton = false
    @State private var isHovering = false
    @State private var requestRename = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ZStack {
                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(AppColors.cardBackgroundSubtle(colorScheme))
                            .overlay(
                                Image(systemName: slot.exists ? "externaldrive.fill" : "externaldrive")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppColors.textMuted(colorScheme))
                            )
                    }
                }
                .frame(width: 96, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if slot.exists && showPlayButton {
                    Button {
                        onLaunchSlot(slot.id, nil)
                    } label: {
                        ZStack {
                            Color.black.opacity(0.6)
                            VStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                Text("saveState.play")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .liquidGlassSheen(cornerRadius: 8)
                    .transition(.opacity)
                }
            }
            .overlay(
            RoundedRectangle(cornerRadius: 8)
                    .stroke(slot.exists ? AppColors.brandAccent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )

            SlotLabelWithRename(
                slot: slot,
                rom: rom,
                saveStateManager: saveStateManager,
                isHovering: isHovering,
                isEditingRequest: $requestRename,
                onRenamed: onDelete
            )

      // Reserve space for 3 text rows to prevent vertical misalignment
      // Show date or file size for saved slots, empty view for empty slots
      if let date = slot.formattedDate {
        Text(date)
          .font(.system(size: 9))
          .foregroundColor(AppColors.textMuted(colorScheme))
          .lineLimit(1)
      } else if let fileSize = slot.fileSize {
        Text(fileSize.formattedByteSize)
          .font(.system(size: 9))
          .foregroundColor(AppColors.textMuted(colorScheme))
      } else {
        // Empty slot - reserve same vertical space
        Text(" ")
          .font(.system(size: 9))
          .foregroundColor(.clear)
      }
    }
        .frame(width: 104)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture(count: 1) {
            if slot.exists {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showPlayButton = true
                }
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    if slot.exists {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showPlayButton = false
                        }
                        onLaunchSlot(slot.id, nil)
                    }
                }
        )
        .onChange(of: showPlayButton) { _, _ in
            if showPlayButton {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showPlayButton = false
                    }
                }
            }
        }
        .contextMenu {
            if slot.exists && slot.id >= 0 {
                Button {
                    requestRename = true
                } label: {
                    Label(loc.localized("savedStates.rename"), systemImage: "pencil")
                }
                Button(action: {
                    if slot.id >= 0 {
                        let gameKey = "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"
                        try? saveStateManager.deleteSlotWithProgressives(
                            gameName: gameKey,
                            systemID: rom.systemID ?? "",
                            slot: slot.id
                        )
                        onDelete()
                    }
                }) {
                    Label(loc.localized("saveState.delete"), systemImage: "trash")
                }
            }
        }
        .task {
            if slot.exists {
                thumbnail = saveStateManager.loadThumbnail(
                    gameName: "\(rom.displayName)__\(rom.id.uuidString.prefix(8))",
                    systemID: rom.systemID ?? "",
                    slot: slot.id
                )
            }
        }
    }
}

/// Renders the slot label for `ModernSaveStateSlotView`, swapping the plain
/// `Text` for the renameable `SlotRenameControl` when the slot is an
/// existing user slot (0-9). Empty and auto slots render the label as
/// before (no pencil affordance).
private struct SlotLabelWithRename: View {
    let slot: SlotInfo
    let rom: ROM
    @ObservedObject var saveStateManager: SaveStateManager
    var isHovering: Bool
    @Binding var isEditingRequest: Bool
    var onRenamed: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if slot.exists && slot.id >= 0 {
            HStack(spacing: 3) {
                SlotRenameControl(
                    slot: slot,
                    rom: rom,
                    saveStateManager: saveStateManager,
                    isHovering: isHovering,
                    isEditingRequest: $isEditingRequest,
                    onRenamed: onRenamed
                )
            }
        } else {
            Text(slot.displayName)
                .font(.caption)
                .fontWeight(slot.exists ? .semibold : .regular)
                .foregroundColor(slot.exists ? AppColors.textPrimary(colorScheme) : AppColors.textMuted(colorScheme))
        }
    }
}