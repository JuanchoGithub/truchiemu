import SwiftUI

// MARK: - Filter Pill Settings Sheet

// Customization UI for the filter-chip bar. Lets the user pick which pills
// (both sort pills and filter pills) are visible and in what order. Pills
// that don't fit the bar are grouped under "Other" automatically, so no
// manual grouping choice is needed. Persists through
// `FilterPillPreferences.shared`.
//
// Reordering is an in-place drag (not a system drag session): the dragged row
// follows the pointer, the rows in between shift to open a gap, and the drop
// commits once. This shows the result before the mouse is released.
struct FilterPillSettingsSheet: View {
    @ObservedObject private var prefs = FilterPillPreferences.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private let rowHeight: CGFloat = 40
    /// Row content plus its 1 pt divider — the distance between two row tops.
    private var rowPitch: CGFloat { rowHeight + 1 }

    @State private var draggingPill: FilterPill?
    @State private var dragSourceIndex: Int = 0
    @State private var dragTargetIndex: Int = 0
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.localized("library.pillEditor.title"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(loc.localized("app.done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(prefs.order.enumerated()), id: \.element) { index, pill in
                        row(for: pill, index: index)
                    }
                }
                .padding(.vertical, 4)
                .coordinateSpace(name: "pillRows")
            }
            .scrollDisabled(draggingPill != nil)

            Divider()

            Text(loc.localized("library.pillEditor.description"))
                .font(.system(size: 11))
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 380, height: 460)
    }

    private func row(for pill: FilterPill, index: Int) -> some View {
        let isDragging = draggingPill == pill
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary(colorScheme))
                    .frame(width: 18, height: rowHeight)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(for: pill, at: index))
                    .help(loc.localized("gameToolbar.dragToReorder"))

                Image(systemName: pill.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.brandAccent)
                    .frame(width: 18)

                Text(pill.label)
                    .font(.body)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: Binding(
                    get: { prefs.isEnabled(pill) },
                    set: { prefs.setEnabled(pill, $0) }
                ))
                .labelsHidden()
                .accessibilityLabel(pill.label)
            }
            .padding(.horizontal, 12)
            .frame(height: rowHeight)
            .background {
                if isDragging {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.accentBackground(colorScheme))
                }
            }

            Divider()
                .padding(.leading, 46)
        }
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .offset(y: rowOffset(for: pill, index: index))
        .zIndex(isDragging ? 1 : 0)
        .shadow(color: .black.opacity(isDragging ? 0.25 : 0),
                radius: isDragging ? 8 : 0,
                y: isDragging ? 3 : 0)
        .animation(isDragging ? nil : .easeInOut(duration: 0.16), value: dragTargetIndex)
    }

    /// Vertical offset for one row while a drag is in progress. The dragged row
    /// follows the pointer; every row between the source and the target shifts
    /// by one row height so the drop position is visible.
    private func rowOffset(for pill: FilterPill, index: Int) -> CGFloat {
        guard let dragging = draggingPill else { return 0 }
        if pill == dragging { return dragTranslation }
        guard index != dragSourceIndex else { return 0 }
        if dragTargetIndex > dragSourceIndex,
           index > dragSourceIndex, index <= dragTargetIndex {
            return -rowPitch
        }
        if dragTargetIndex < dragSourceIndex,
           index >= dragTargetIndex, index < dragSourceIndex {
            return rowPitch
        }
        return 0
    }

    private func dragGesture(for pill: FilterPill, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("pillRows"))
            .onChanged { value in
                if draggingPill != pill {
                    draggingPill = pill
                    dragSourceIndex = index
                    dragTargetIndex = index
                }
                dragTranslation = value.translation.height
                let steps = Int((value.translation.height / rowPitch).rounded())
                let target = min(max(dragSourceIndex + steps, 0), prefs.order.count - 1)
                if target != dragTargetIndex {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        dragTargetIndex = target
                    }
                }
            }
            .onEnded { _ in
                let source = dragSourceIndex
                let target = dragTargetIndex
                withAnimation(.easeInOut(duration: 0.18)) {
                    if source != target {
                        prefs.move(from: source, to: target)
                    }
                    draggingPill = nil
                    dragTranslation = 0
                }
            }
    }
}
