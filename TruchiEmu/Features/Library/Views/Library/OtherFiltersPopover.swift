import SwiftUI

// "Other" popover for the filter-chip bar. Contains the pills that don't fit
// inline plus the Last Added sort row. Triggered by the chip-bar "Other"
// button.
struct OtherFiltersPopover: View {
    let pills: [FilterPill]
    @Binding var activeFilters: Set<String>
    let onToggle: (GameFilterOption) -> Void
    @Binding var sortOrder: LibrarySortOrder
    @Binding var sortAscending: Bool
    var excludedSortOrders: Set<LibrarySortOrder> = []
    var onCommit: ((LibrarySortOrder, Bool) -> Void)? = nil

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
                ForEach(pills) { pill in
                    switch pill {
                    case .filter(let option):
                        FilterChipView(
                            option: option,
                            isActive: activeFilters.contains(option.rawValue),
                            fillsWidth: true,
                            action: { onToggle(option) }
                        )
                        .help(option.tooltip)
                    case .sort(let order):
                        SortRow(
                            order: order,
                            currentOrder: $sortOrder,
                            ascending: $sortAscending,
                            style: .popover,
                            keyboardShortcut: nil,
                            onCommit: onCommit
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            // Last Added normally lives here. It is excluded after the user
            // promotes it to the main row.
            LibrarySortPicker(
                currentOrder: $sortOrder,
                ascending: $sortAscending,
                style: .popover,
                excludedSortOrders: excludedSortOrders,
                onCommit: onCommit
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(minWidth: 200)
    }
}
