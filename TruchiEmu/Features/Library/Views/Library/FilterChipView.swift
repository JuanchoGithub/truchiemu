import SwiftUI

// MARK: - Filter Chip View
//
// Thin wrapper over `LibraryChip` so every filter pill shares one shape and
// one hover/active treatment. The option still owns its icon, label, tooltip
// and per-filter active color.

struct FilterChipView: View {
    let option: GameFilterOption
    let isActive: Bool
    var fillsWidth: Bool = false
    let action: () -> Void

    var body: some View {
        LibraryChip(
            icon: option.icon,
            title: option.label,
            isActive: isActive,
            tint: option.activeColor,
            fillsWidth: fillsWidth,
            tooltip: option.tooltip,
            action: action
        )
    }
}
