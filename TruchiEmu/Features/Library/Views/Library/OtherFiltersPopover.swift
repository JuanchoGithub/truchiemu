import SwiftUI

struct OtherFiltersPopover: View {
    @Binding var activeFilters: Set<String>
    let onToggle: (GameFilterOption) -> Void

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
                        action: { onToggle(option) }
                    )
                    .help(option.tooltip)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(minWidth: 200)
    }
}
