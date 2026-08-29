import SwiftUI

// MARK: - Library Sort Picker

// Reusable sort selector for the library. Single source of truth for both
// the macOS Sort menu (in `TruchiEmuApp`) and the filter-chip bar (in
// `LibraryGridView`). The picker persists the selection and posts
// `.sortChanged`; the parent view reads the active order via the binding
// and re-sorts the library on `.sortChanged`.
//
// Three styles:
//   - `.menu`     : rows for the macOS Sort sub-menu (with "Other" label).
//   - `.chips`    : primary chips rendered inline in the filter-chip bar.
//   - `.popover`  : "Other" popover contents mirroring `OtherFiltersPopover`.
//
// Each non-`.name` order cycles through three states on click:
//   inactive → descending → ascending → inactive.
// `.name` is the implicit default and is not rendered as a pill.
//
// Adding a new sort order = add a `LibrarySortOrder` case and (optionally)
// append it to `primary` or `other`. The picker renders the new option
// automatically. Do not add a third call site.

struct LibrarySortPicker: View {
    @Binding var currentOrder: LibrarySortOrder
    @Binding var ascending: Bool
    var style: Style
    var keyboardShortcuts: [LibrarySortOrder: KeyboardShortcut] = [:]

    enum Style {
        case menu
        case chips
        case popover
    }

    var body: some View {
        switch style {
        case .menu:
            menuBody
        case .chips:
            chipsBody
        case .popover:
            popoverBody
        }
    }

    // MARK: - Menu (NSMenu) variant

    private var menuBody: some View {
        Group {
            ForEach(LibrarySortOrder.primary) { order in
                SortRow(
                    order: order,
                    currentOrder: currentOrder,
                    ascending: ascending,
                    style: .menu,
                    keyboardShortcut: keyboardShortcuts[order]
                )
            }
            Divider()
            Text(LocalizationManager.shared.localized("library.otherSort"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            ForEach(LibrarySortOrder.other) { order in
                SortRow(
                    order: order,
                    currentOrder: currentOrder,
                    ascending: ascending,
                    style: .menu,
                    keyboardShortcut: keyboardShortcuts[order]
                )
            }
        }
    }

    // MARK: - Chips variant (primary only — the rest live in the popover)

    private var chipsBody: some View {
        HStack(spacing: 6) {
            ForEach(LibrarySortOrder.primary) { order in
                SortRow(
                    order: order,
                    currentOrder: currentOrder,
                    ascending: ascending,
                    style: .chips,
                    keyboardShortcut: nil
                )
            }
        }
    }

    // MARK: - Popover variant (other only — mirrors `OtherFiltersPopover`)

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(LibrarySortOrder.other) { order in
                SortRow(
                    order: order,
                    currentOrder: currentOrder,
                    ascending: ascending,
                    style: .popover,
                    keyboardShortcut: nil
                )
            }
        }
    }
}

// MARK: - Sort Row

private struct SortRow: View {
    let order: LibrarySortOrder
    let currentOrder: LibrarySortOrder
    let ascending: Bool
    let style: LibrarySortPicker.Style
    let keyboardShortcut: KeyboardShortcut?

    @ObservedObject private var loc = LocalizationManager.shared
    @State private var isHovered: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    /// nil = not active (the `.name` fallback is in effect).
    private var phase: Phase? {
        if order != currentOrder { return nil }
        return ascending ? .ascending : .descending
    }

    private enum Phase { case ascending, descending }

    var body: some View {
        switch style {
        case .menu:
            menuRow
        case .chips:
            chipRow
        case .popover:
            popoverRow
        }
    }

    // MARK: NSMenu row

    private var menuRow: some View {
        Group {
            if let phase {
                Button {
                    cycle()
                } label: {
                    Label("\(loc.localized(order.localizationKey)) \(arrow(phase))", systemImage: order.icon)
                }
                .keyboardShortcut(keyboardShortcut)
            } else {
                Button(loc.localized(order.localizationKey)) {
                    setActive(ascending: false)
                }
                .keyboardShortcut(keyboardShortcut)
            }
        }
    }

    // MARK: Capsule chip row (matches existing sort-chip styling)

    private var chipRow: some View {
        Button {
            cycle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .medium))
                    .scaleEffect(phase != nil ? 1.1 : 1)
                Text(loc.localized(order.localizationKey))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(phase != nil ? AppColors.textOnAccent(colorScheme) : (isHovered ? AppColors.brandAccent : AppColors.textSecondaryNeutral(colorScheme)))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .background(
                Capsule()
                    .fill(phase != nil ? AppColors.brandAccent : (isHovered ? AppColors.brandAccent.opacity(0.12) : AppColors.cardBackgroundSubtle(colorScheme)))
                    .scaleEffect(isHovered ? 1.05 : 1)
                    .shadow(color: phase != nil ? AppColors.brandAccent.opacity(0.3) : (isHovered ? AppColors.brandAccent.opacity(0.2) : .clear), radius: isHovered ? 4 : 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if shouldAnimate {
                withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
            } else {
                isHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.2), value: phase)
    }

    // MARK: Popover row (matches `FilterChipView` so the "Other" popover
    // shows a uniform list of capsule pills).

    private var popoverRow: some View {
        Button {
            cycle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .medium))
                    .scaleEffect(phase != nil ? 1.1 : 1)
                Text(loc.localized(order.localizationKey))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .foregroundColor(phase != nil ? .white : (isHovered ? AppColors.brandAccent : .secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                Capsule()
                    .fill(phase != nil ? AppColors.brandAccent : (isHovered ? AppColors.brandAccent.opacity(0.12) : AppColors.cardBackgroundSubtle(colorScheme)))
                    .scaleEffect(isHovered ? 1.05 : 1)
                    .shadow(color: phase != nil ? AppColors.brandAccent.opacity(0.3) : (isHovered ? AppColors.brandAccent.opacity(0.2) : .clear), radius: isHovered ? 4 : 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if shouldAnimate {
                withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
            } else {
                isHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.2), value: phase)
    }

    private var iconName: String {
        guard let phase else { return order.icon }
        return phase == .ascending ? "arrow.up" : "arrow.down"
    }

    private func arrow(_ phase: Phase) -> String {
        phase == .ascending ? "↑" : "↓"
    }

    private var tooltip: String {
        let label = loc.localized(order.localizationKey)
        switch phase {
        case .descending: return "Sorting by \(label) ↓ — click for ascending, click again to clear"
        case .ascending:  return "Sorting by \(label) ↑ — click to clear"
        case nil:         return "Click to sort by \(label) ↓"
        }
    }

    /// Three-state cycle: inactive → descending → ascending → inactive.
    /// Descending = most recent first / most played / longest to beat.
    private func cycle() {
        switch phase {
        case nil:
            setActive(ascending: false)
        case .descending:
            setActive(ascending: true)
        case .ascending:
            clear()
        }
    }

    private func setActive(ascending: Bool) {
        AppSettings.setString(LibrarySortOrder.orderKey, value: order.rawValue)
        AppSettings.setBool(LibrarySortOrder.ascendingKey, value: ascending)
        NotificationCenter.default.post(name: .sortChanged, object: nil)
    }

    private func clear() {
        AppSettings.setString(LibrarySortOrder.orderKey, value: LibrarySortOrder.name.rawValue)
        AppSettings.setBool(LibrarySortOrder.ascendingKey, value: false)
        NotificationCenter.default.post(name: .sortChanged, object: nil)
    }
}
