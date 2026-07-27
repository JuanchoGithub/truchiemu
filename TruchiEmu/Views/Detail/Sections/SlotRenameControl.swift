import SwiftUI

/// Compact inline rename affordance for save state slots.
///
/// Renders the slot's current label next to a pencil button. The pencil
/// appears whenever `isHovering` is true (lifted to the parent so the whole
/// slot can be the hover target). Clicking the pencil, OR triggering the
/// edit entry via `isEditingRequest`, exposes an editable text field bound
/// to the slot's display name; committing (Enter or Save) calls
/// `SaveStateManager.setSlotName` and `onRenamed`, clearing the saved
/// name when the field is left empty (slot returns to "Slot N").
///
/// Only user slots (id >= 0) are renamable; the auto slot (-1) renders
/// nothing.
struct SlotRenameControl: View {
    let slot: SlotInfo
    let rom: ROM
    @ObservedObject var saveStateManager: SaveStateManager
    var isHovering: Bool
    /// Two-way binding used to drive edit mode from outside (e.g. a context
    /// menu item). Parent sets to `true` to begin editing; control sets back
    /// to `false` on commit/cancel.
    @Binding var isEditingRequest: Bool
    var onRenamed: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isEditing = false

    private var gameKey: String {
        "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"
    }

    @ViewBuilder
    var body: some View {
        if slot.id >= 0 {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 3) {
            if isEditing {
                SlotRenameEditor(
                    initialText: slot.customName ?? "",
                    onSave: { commit($0) },
                    onCancel: { cancelEditing() }
                )
                .frame(width: 120)
            } else {
                Text(slot.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                    .lineLimit(1)

                if isHovering {
                    Button {
                        startEditing()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .buttonStyle(.plain)
                    .help(loc.localized("savedStates.rename"))
                    .transition(.opacity)
                }
            }
        }
        .onChange(of: isEditingRequest) { _, requested in
            if requested && !isEditing {
                startEditing()
            }
        }
    }

    private func startEditing() {
        isEditing = true
    }

    private func commit(_ newValue: String) {
        saveStateManager.setSlotName(newValue, gameName: gameKey, systemID: rom.systemID ?? "", slot: slot.id)
        isEditing = false
        isEditingRequest = false
        onRenamed()
    }

    private func cancelEditing() {
        isEditing = false
        isEditingRequest = false
    }
}

/// Inline editable field with Enter-to-commit and Esc-to-cancel, pre-populated
/// with the slot's current custom name (or empty placeholder).
private struct SlotRenameEditor: View {
    let initialText: String
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @State private var text: String = ""
    @State private var hasAppeared = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: $text, prompt: Text(verbatim: "Slot name"))
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { onSave(text) }
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }
                .onAppear {
                    if !hasAppeared {
                        text = initialText
                        hasAppeared = true
                        isFocused = true
                    }
                }

            Button {
                onSave(text)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.brandAccent)
            }
            .buttonStyle(.plain)
            .help(loc.localized("savedStates.saveSlotName"))

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            .help(loc.localized("savedStates.cancelSlotName"))
        }
    }
}
