import SwiftUI

// "Other" popover for the filter-chip bar. Contains the non-primary filter
// chips plus the non-primary sort order (Last Added). Triggered by the
// chip-bar "Other" button. The combined content is intentional: both
// filters and sort orders that aren't promoted to the chip-bar "main list".

struct OtherFiltersPopover: View {
    @Binding var activeFilters: Set<String>
    let onToggle: (GameFilterOption) -> Void
    @Binding var sortOrder: LibrarySortOrder
    @Binding var sortAscending: Bool

    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(loc.localized("library.otherFilters"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(GameFilterOption.otherFilters) { option in
                    FilterChipView(
                        option: option,
                        isActive: activeFilters.contains(option.rawValue),
                        fillsWidth: true,
                        action: { onToggle(option) }
                    )
                    .help(option.tooltip)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            // Last Added sort row — reuses the same popover so the chip bar
            // only carries one "Other" entry.
            LibrarySortPicker(
                currentOrder: $sortOrder,
                ascending: $sortAscending,
                style: .popover
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(minWidth: 200)
    }
}
