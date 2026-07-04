import SwiftUI

struct HotkeysTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var hotkeyManager = HotkeyConfigManager.shared
    @State private var listeningAction: HotkeyAction?
    @State private var listeningSlot: KeySlot = .primary
    @Binding var searchText: String

    enum KeySlot { case primary, secondary }

    var body: some View {
        Form {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                    ForEach(Array(captureActions.enumerated()), id: \.offset) { index, action in
                        hotkeyGridRow(action: action, isLast: index == captureActions.count - 1)
                    }
                }
            } header: {
                Label(loc.localized("settings.media.hotkeys.captureOnly"), systemImage: "keyboard")
            } footer: {
                HStack {
                    Text(loc.localized("settings.media.hotkeys.allShortcuts"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
    }

    private var captureActions: [HotkeyAction] {
        [.screenshot, .shareSinglePress, .shareLongPress]
    }

    @ViewBuilder
    private func hotkeyGridRow(action: HotkeyAction, isLast: Bool) -> some View {
        let cfg = hotkeyManager.config[action] ?? .unbound
        GridRow {
            Text(loc.localized(action.localizationKey))
                .lineLimit(1)
                .gridColumnAlignment(.leading)
            HStack(spacing: 8) {
                HotkeyCaptureButton(
                    binding: cfg.primary,
                    isListening: listeningAction == action && listeningSlot == .primary,
                    conflicts: hotkeyManager.findConflicts(for: cfg.primary, excluding: action),
                    onCapture: { captured in
                        hotkeyManager.update(action, primary: captured)
                        listeningAction = nil
                    },
                    onStartListening: {
                        listeningAction = action
                        listeningSlot = .primary
                    },
                    onClear: {
                        hotkeyManager.update(action, primary: .none)
                    }
                )
                HotkeyCaptureButton(
                    binding: cfg.secondary,
                    isListening: listeningAction == action && listeningSlot == .secondary,
                    conflicts: hotkeyManager.findConflicts(for: cfg.secondary, excluding: action),
                    onCapture: { captured in
                        hotkeyManager.update(action, secondary: captured)
                        listeningAction = nil
                    },
                    onStartListening: {
                        listeningAction = action
                        listeningSlot = .secondary
                    },
                    onClear: {
                        hotkeyManager.update(action, secondary: .none)
                    }
                )
            }
            .gridColumnAlignment(.trailing)
        }
        .padding(.vertical, AppSpacing.xxs)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .overlay(AppColors.divider(colorScheme))
            }
        }
    }
}