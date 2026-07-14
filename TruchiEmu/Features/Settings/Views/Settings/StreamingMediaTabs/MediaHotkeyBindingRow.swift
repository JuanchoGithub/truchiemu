import SwiftUI

/// Streaming & Media sub-tab binding row. Renders the section label on the
/// left and a full 3-column hotkey capture row (primary keyboard + secondary
/// keyboard + controller) on the right.
///
/// Captures are owned by `HotkeyActionRow`, the canonical row component used
/// by both the main Hotkeys settings page and these tab rows. This wrapper
/// only handles the label/cell layout for the tab's compact form section.
struct MediaHotkeyBindingRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    let action: HotkeyAction
    let sectionKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(loc.localized(sectionKey))
                    .font(.callout.weight(.medium))
                Spacer(minLength: 8)
                HotkeyActionRow(action: action)
            }
            Text(loc.localized("hotkeys.action." + action.rawValue))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}
