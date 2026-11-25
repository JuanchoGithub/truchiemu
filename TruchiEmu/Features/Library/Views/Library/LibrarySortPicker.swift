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
    /// When false, the system sorts (`.systemName` / `.systemAge`) are left
    /// out of the rendered options — they only make sense where a collection
    /// can span multiple systems (callers hide them in system views).
    var includeSystemSorts: Bool = true
    /// Orders that the caller renders elsewhere. This keeps a promoted pill
    /// out of the "Other" popover after the user moves it to the main row.
    var excludedSortOrders: Set<LibrarySortOrder> = []
    /// Optional commit handler. When provided, the picker updates the bindings
    /// and calls this instead of persisting to the global AppSettings keys and
    /// posting `.sortChanged`. Callers use this to scope persistence (e.g.
    /// per-category). When nil, default global behavior is used.
    var onCommit: ((LibrarySortOrder, Bool) -> Void)? = nil

    enum Style {
        case menu
        case chips
        case popover
    }

    /// Primary orders after the system-sort and caller exclusion rules.
    private var visiblePrimary: [LibrarySortOrder] {
        let orders = includeSystemSorts
            ? LibrarySortOrder.primary
            : LibrarySortOrder.primary.filter { !$0.isSystemSort }
        return orders.filter { !excludedSortOrders.contains($0) }
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
            ForEach(visiblePrimary) { order in
                SortRow(
                    order: order,
                    currentOrder: $currentOrder,
                    ascending: $ascending,
                    style: .menu,
                    keyboardShortcut: keyboardShortcuts[order],
                    onCommit: onCommit
                )
            }
            Divider()
            Text(LocalizationManager.shared.localized("library.otherSort"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            ForEach(LibrarySortOrder.other.filter { !excludedSortOrders.contains($0) }) { order in
                SortRow(
                    order: order,
                    currentOrder: $currentOrder,
                    ascending: $ascending,
                    style: .menu,
                    keyboardShortcut: keyboardShortcuts[order],
                    onCommit: onCommit
                )
            }
        }
    }

    // MARK: - Chips variant (primary only — the rest live in the popover)

    private var chipsBody: some View {
        HStack(spacing: 6) {
            ForEach(visiblePrimary) { order in
                SortRow(
                    order: order,
                    currentOrder: $currentOrder,
                    ascending: $ascending,
                    style: .chips,
                    keyboardShortcut: nil,
                    onCommit: onCommit
                )
            }
        }
    }

    // MARK: - Popover variant (other only — mirrors `OtherFiltersPopover`)

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(LibrarySortOrder.other.filter { !excludedSortOrders.contains($0) }) { order in
                SortRow(
                    order: order,
                    currentOrder: $currentOrder,
                    ascending: $ascending,
                    style: .popover,
                    keyboardShortcut: nil,
                    onCommit: onCommit
                )
            }
        }
    }
}

// MARK: - Sort Row

struct SortRow: View {
    let order: LibrarySortOrder
    @Binding var currentOrder: LibrarySortOrder
    @Binding var ascending: Bool
    let style: LibrarySortPicker.Style
    let keyboardShortcut: KeyboardShortcut?
    var onCommit: ((LibrarySortOrder, Bool) -> Void)? = nil

    @ObservedObject private var loc = LocalizationManager.shared

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

    // MARK: Capsule chip row (shared `LibraryChip` styling)

    private var chipRow: some View {
        LibraryChip(
            icon: iconName,
            title: loc.localized(order.localizationKey),
            isActive: phase != nil,
            tooltip: tooltip,
            action: { cycle() }
        )
    }

    // MARK: Popover row (stretched, same `LibraryChip` styling)

    private var popoverRow: some View {
        LibraryChip(
            icon: iconName,
            title: loc.localized(order.localizationKey),
            isActive: phase != nil,
            fillsWidth: true,
            tooltip: tooltip,
            action: { cycle() }
        )
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
        currentOrder = order
        self.ascending = ascending
        if let onCommit {
            onCommit(order, ascending)
        } else {
            AppSettings.setString(LibrarySortOrder.orderKey, value: order.rawValue)
            AppSettings.setBool(LibrarySortOrder.ascendingKey, value: ascending)
            NotificationCenter.default.post(name: .sortChanged, object: nil)
        }
    }

    private func clear() {
        currentOrder = .name
        ascending = false
        if let onCommit {
            onCommit(.name, false)
        } else {
            AppSettings.setString(LibrarySortOrder.orderKey, value: LibrarySortOrder.name.rawValue)
            AppSettings.setBool(LibrarySortOrder.ascendingKey, value: false)
            NotificationCenter.default.post(name: .sortChanged, object: nil)
        }
    }
}
