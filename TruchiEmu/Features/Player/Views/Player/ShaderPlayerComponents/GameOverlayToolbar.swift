import AppKit
import SwiftUI

private let fullscreenArrowWidth: CGFloat = 12

struct GameOverlayToolbar: View {
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject var windowController: StandaloneGameWindowController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var preferences = GameToolbarPreferences.shared
    @ObservedObject private var trainingManager = TrainingModeManager.shared
    @ObservedObject private var recordingService = StreamRecordingService.shared
    @ObservedObject private var guideViewModel: GameGuideViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var itemWidths: [GameToolbarItemID: CGFloat] = [:]
    @State private var measuredMoreWidth: CGFloat = 0
    @State private var stickyOverflowIDs: Set<GameToolbarItemID> = []

    @MainActor
    init(runner: EmulatorRunner, windowController: StandaloneGameWindowController) {
        self.runner = runner
        self.windowController = windowController
        _guideViewModel = ObservedObject(wrappedValue: windowController.gameGuideViewModel)
    }

    private var focusedIndex: Int? {
        windowController.isGamepadToolbarMode ? windowController.gamepadToolbarFocusedIndex : nil
    }

    private var allAvailableItems: [GameToolbarItem] {
        GameToolbarModel.availableItems(
            runner: runner,
            windowController: windowController,
            preferences: preferences
        )
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let mode = compactMode(for: width)
            let composition = compose(width: width, mode: mode, stickyOverflowIDs: stickyOverflowIDs)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Spacer(minLength: 8)
                    toolbar(composition: composition, mode: mode)
                    Spacer(minLength: 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "toolbarRoot")
            .environment(\.toolbarCompactMode, mode)
            .onPreferenceChange(ToolbarHitRectPreferenceKey.self) { rect in
                windowController.updateToolbarHitRect(rect)
            }
            .onAppear {
                publish(composition)
                initializeStickyOverflow(width: width, mode: mode)
                if preferences.pinVisible && !windowController.isToolbarVisible {
                    windowController.showToolbar()
                }
            }
            .onChange(of: composition.focusOrder) { _, _ in publish(composition) }
            .onChange(of: preferences.pinVisible) { _, pinned in
                if pinned && !windowController.isToolbarVisible {
                    windowController.showToolbar()
                } else if !pinned {
                    windowController.resumeToolbarAutoHide()
                }
            }
            .onChange(of: composition.overflow.isEmpty) { _, isEmpty in
                windowController.toolbarHasMore = !isEmpty
                if isEmpty {
                    windowController.isToolbarMoreShown = false
                }
            }
            .onChange(of: windowController.isToolbarMoreShown) { _, isShown in
                if isShown {
                    windowController.cancelToolbarAutoHide()
                } else {
                    windowController.resumeToolbarAutoHide()
                }
            }
            .onChange(of: width) { oldWidth, newWidth in
                updateStickyOverflow(oldWidth: oldWidth, newWidth: newWidth)
            }
        }
    }

    private func toolbar(composition: ToolbarComposition, mode: ToolbarCompactMode) -> some View {
        let indices = focusIndices(composition.focusOrder)
        let hasOverflow = !composition.overflow.isEmpty

        return HStack(spacing: itemSpacing(mode)) {
            ForEach(Array(composition.segments.enumerated()), id: \.element.id) { index, segment in
                if index > 0 {
                    divider(mode)
                }
                segmentView(segment, indices: indices, mode: mode)
            }

            if !composition.segments.isEmpty && hasOverflow {
                divider(mode)
            }

            if hasOverflow {
                moreButton(items: composition.overflow, mode: mode)
                    .gamepadToolbarFocus(index: composition.focusOrder.count, focusedIndex: focusedIndex)
            }
        }
        .padding(.horizontal, containerPaddingH(mode))
        .padding(.vertical, containerPaddingV(mode))
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ToolbarHitRectPreferenceKey.self,
                    value: proxy.frame(in: .named("toolbarRoot"))
                )
            }
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.cardBorder(colorScheme), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 12, x: 0, y: 4)
        .background(measurementRow(mode: mode))
        .popover(isPresented: toolbarPopoverBinding, arrowEdge: .top) {
            Group {
                if windowController.isSlotPickerShown {
                    SaveStatesBrowserView(
                        runner: runner,
                        isPresented: $windowController.isSlotPickerShown,
                        disabled: windowController.saveStatesDisabled,
                        onLoadCompleted: {
                            if windowController.isGamepadToolbarMode {
                                windowController.exitGamepadToolbarMode()
                            }
                        }
                    )
                } else if windowController.isRecordStreamPickerShown {
                    RecordStreamPickerPopover(
                        runner: runner,
                        isDropdownShown: $windowController.isRecordStreamPickerShown
                    )
                }
            }
            .onDisappear { windowController.resumeToolbarAutoHide() }
        }
        .onHover { windowController.toolbarHoverChanged($0) }
    }

    private var toolbarPopoverBinding: Binding<Bool> {
        Binding(
            get: {
                windowController.isSlotPickerShown || windowController.isRecordStreamPickerShown
            },
            set: { presented in
                if !presented {
                    windowController.isSlotPickerShown = false
                    windowController.isRecordStreamPickerShown = false
                }
            }
        )
    }

    @ViewBuilder
    private func segmentView(
        _ segment: ToolbarSegment,
        indices: [GameToolbarItemID: Int],
        mode: ToolbarCompactMode
    ) -> some View {
        switch segment {
        case .items(_, let items):
            flexibleCluster(items, indices: indices, mode: mode)
        case .time(_, let items):
            timePod(items: items, indices: indices, mode: mode)
        case .capture(_, let items):
            capturePod(items: items, indices: indices, mode: mode)
        }
    }

    private func flexibleCluster(
        _ items: [GameToolbarItem],
        indices: [GameToolbarItemID: Int],
        mode: ToolbarCompactMode
    ) -> some View {
        HStack(spacing: itemSpacing(mode)) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 && items[index - 1].group != item.group {
                    divider(mode)
                }
                focusedItem(item, indices: indices)
            }
        }
    }

    private func timePod(
        items: [GameToolbarItem],
        indices: [GameToolbarItemID: Int],
        mode: ToolbarCompactMode
    ) -> some View {
        let rewind = items.first { $0.id == .rewind }
        let speeds = items.filter { $0.id == .slowMotion || $0.id == .fastForward }
        let contentWidth = max(0, timePodWidth(items, mode: mode) - podPadding * 2)

        return VStack(spacing: 2) {
            if let rewind {
                focusedItem(rewind, indices: indices, horizontal: true)
                    .frame(maxWidth: .infinity)
            }
            if !speeds.isEmpty {
                HStack(spacing: itemSpacing(mode)) {
                    ForEach(speeds) { item in
                        focusedItem(item, indices: indices, textAsIcon: true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: contentWidth)
        .padding(podPadding)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.cardBorder(colorScheme), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private func capturePod(
        items: [GameToolbarItem],
        indices: [GameToolbarItemID: Int],
        mode: ToolbarCompactMode
    ) -> some View {
        let contentWidth = max(0, capturePodWidth(items, mode: mode) - podPadding * 2)
        return VStack(spacing: 2) {
            ForEach(items) { item in
                focusedItem(item, indices: indices)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: contentWidth)
        .padding(podPadding)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.cardBorder(colorScheme), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func focusedItem(
        _ item: GameToolbarItem,
        indices: [GameToolbarItemID: Int],
        horizontal: Bool = false,
        textAsIcon: Bool = false
    ) -> some View {
        if let index = indices[item.id] {
            GameToolbarItemView(
                item: item,
                runner: runner,
                windowController: windowController,
                horizontal: horizontal,
                textAsIcon: textAsIcon
            )
            .gamepadToolbarFocus(index: index, focusedIndex: focusedIndex)
        } else {
            GameToolbarItemView(
                item: item,
                runner: runner,
                windowController: windowController,
                horizontal: horizontal,
                textAsIcon: textAsIcon
            )
        }
    }

    private func focusIndices(_ order: [GameToolbarItemID]) -> [GameToolbarItemID: Int] {
        Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
    }

    private var podPadding: CGFloat { 3 }

    private func moreButton(items: [GameToolbarItem], mode: ToolbarCompactMode) -> some View {
        ToolbarButton(
            icon: "ellipsis",
            label: loc.localized("toolbar.more"),
            active: windowController.isToolbarMoreShown,
            action: { windowController.isToolbarMoreShown = true }
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ToolbarMoreWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(ToolbarMoreWidthPreferenceKey.self) { measuredMoreWidth = $0 }
        .popover(isPresented: $windowController.isToolbarMoreShown, arrowEdge: .top) {
            ToolbarOverflowView(
                items: items,
                runner: runner,
                windowController: windowController,
                isPresented: $windowController.isToolbarMoreShown
            )
            .environment(\.toolbarCompactMode, .full)
            .onDisappear { windowController.resumeToolbarAutoHide() }
        }
    }

    private func divider(_ mode: ToolbarCompactMode) -> some View {
        Rectangle()
            .fill(AppColors.divider(colorScheme))
            .frame(width: 1, height: dividerHeight(mode))
            .padding(.horizontal, 1.5)
    }

    private func measurementRow(mode: ToolbarCompactMode) -> some View {
        HStack(spacing: itemSpacing(mode)) {
            ForEach(allAvailableItems) { item in
                let info = GameToolbarPresentationResolver.resolve(
                    item: item,
                    runner: runner,
                    windowController: windowController
                )
                ToolbarButtonContent(
                    icon: info.icon,
                    label: info.label,
                    badge: info.badge,
                    horizontal: item.id == .rewind,
                    textAsIcon: item.id == .slowMotion || item.id == .fastForward
                )
                .fixedSize()
                .padding(.trailing, item.id == .fullscreen ? fullscreenArrowWidth : 0)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ToolbarItemWidthPreferenceKey.self,
                            value: [item.id: proxy.size.width]
                        )
                    }
                )
            }
        }
        .fixedSize()
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onPreferenceChange(ToolbarItemWidthPreferenceKey.self) { itemWidths = $0 }
    }

    private func publish(_ composition: ToolbarComposition) {
        let ids = composition.focusOrder
        if windowController.toolbarInlineItemIDs != ids {
            windowController.toolbarInlineItemIDs = ids
        }
        let hasMore = !composition.overflow.isEmpty
        if windowController.toolbarHasMore != hasMore {
            windowController.toolbarHasMore = hasMore
        }
    }

    private func updateStickyOverflow(oldWidth: CGFloat, newWidth: CGFloat) {
        guard oldWidth > 0 else { return }
        let availableIDs = Set(allAvailableItems.map(\.id))
        var next = stickyOverflowIDs

        if newWidth < oldWidth {
            let oldComposition = compose(
                width: oldWidth,
                mode: compactMode(for: oldWidth),
                stickyOverflowIDs: []
            )
            next.formUnion(flexibleOverflowIDs(oldComposition))
        }

        let newMode = compactMode(for: newWidth)
        let rawComposition = compose(width: newWidth, mode: newMode, stickyOverflowIDs: [])
        if rawComposition.overflow.isEmpty {
            next = []
        } else {
            let newComposition = compose(
                width: newWidth,
                mode: newMode,
                stickyOverflowIDs: next
            )
            next.formUnion(flexibleOverflowIDs(newComposition))
        }

        next.formIntersection(availableIDs)
        if next != stickyOverflowIDs {
            stickyOverflowIDs = next
        }
    }

    private func initializeStickyOverflow(width: CGFloat, mode: ToolbarCompactMode) {
        guard width > 0 else { return }
        let composition = compose(width: width, mode: mode, stickyOverflowIDs: [])
        let availableIDs = Set(allAvailableItems.map(\.id))
        let next = flexibleOverflowIDs(composition).intersection(availableIDs)
        if next != stickyOverflowIDs {
            stickyOverflowIDs = next
        }
    }

    private func flexibleOverflowIDs(_ composition: ToolbarComposition) -> Set<GameToolbarItemID> {
        let timeIDs: Set<GameToolbarItemID> = [.rewind, .slowMotion, .fastForward]
        return Set(composition.overflow.map(\.id)).subtracting(timeIDs)
    }

    private func compose(width: CGFloat, mode: ToolbarCompactMode, stickyOverflowIDs: Set<GameToolbarItemID> = []) -> ToolbarComposition {
        let available = ordered(allAvailableItems)
        guard !available.isEmpty else { return .empty }

        let timeIDSet: Set<GameToolbarItemID> = [.rewind, .slowMotion, .fastForward]
        let orderedTimeIDs = preferences.itemOrder.filter { timeIDSet.contains($0) }
        let captureIDs: [GameToolbarItemID] = [.record]
        let allTime = orderedTimeIDs.compactMap { id in available.first { $0.id == id } }
        let rewindItem = allTime.first { $0.id == .rewind }
        let time = [rewindItem].compactMap { $0 } + allTime.filter { $0.id != .rewind }
        let capture = captureIDs.compactMap { id in available.first { $0.id == id } }

        func makeSplit(time: [GameToolbarItem], excludedIDs: Set<GameToolbarItemID> = []) -> ToolbarSplit {
            let fixedIDs = Set((time + capture).map(\.id)).union(excludedIDs)
            let flexible = available.filter { !fixedIDs.contains($0.id) }
            let reserved = reservedPodWidth(time: time, capture: capture, mode: mode)
            let contentWidth = max(0, width - containerPaddingH(mode) * 2 - 16 - reserved)
            return splitFlexibleItems(flexible, contentWidth: contentWidth, mode: mode)
        }

        let stickyItems = available.filter {
            stickyOverflowIDs.contains($0.id) && !timeIDSet.contains($0.id) && !captureIDs.contains($0.id)
        }
        let timePriority = allTime.map(\.priority).min() ?? Int.max
        var inlineTime = time
        var forcedOverflow = stickyItems
        var split = makeSplit(time: inlineTime, excludedIDs: stickyOverflowIDs)

        let shouldMoveTimeToOverflow = !inlineTime.isEmpty && (
            mode != .full ||
            split.overflow.contains { $0.priority > timePriority }
        )
        if shouldMoveTimeToOverflow {
            forcedOverflow = stickyItems + inlineTime
            inlineTime = []
            split = makeSplit(time: [], excludedIDs: Set(allTime.map(\.id)).union(stickyOverflowIDs))
        }

        let inline = ordered(split.inline)
        let inlineByGroup = Dictionary(grouping: inline, by: \.group)
        var segments: [ToolbarSegment] = []
        for group in preferences.groupOrder {
            if group == .time, !inlineTime.isEmpty {
                segments.append(.time(group, inlineTime))
            } else if group == .capture, !capture.isEmpty {
                segments.append(.capture(group, capture))
            } else if let items = inlineByGroup[group], !items.isEmpty {
                segments.append(.items(group, items))
            }
        }
        let knownGroups = Set(preferences.groupOrder)
        for group in GameToolbarGroup.allCases where !knownGroups.contains(group) {
            if let items = inlineByGroup[group], !items.isEmpty {
                segments.append(.items(group, items))
            }
        }

        return ToolbarComposition(
            segments: segments,
            overflow: ordered(split.overflow + forcedOverflow),
            focusOrder: segments.flatMap { $0.items.map(\.id) }
        )
    }

    private func splitFlexibleItems(
        _ available: [GameToolbarItem],
        contentWidth: CGFloat,
        mode: ToolbarCompactMode
    ) -> ToolbarSplit {
        guard !available.isEmpty else { return ToolbarSplit(inline: [], overflow: []) }

        let primary = available.filter(\.isPrimary)
        let candidates = available.filter { !$0.isPrimary }

        if measuredWidth(available, includeMore: false, mode: mode) <= contentWidth {
            return ToolbarSplit(inline: available, overflow: [])
        }

        var inline = primary
        while measuredWidth(inline, includeMore: true, mode: mode) > contentWidth {
            let removable = inline.filter { !$0.isRequired }
            guard let lowest = removable.min(by: { $0.priority < $1.priority }) else { break }
            inline.removeAll { $0.id == lowest.id }
        }
        if inline.isEmpty {
            inline = Array(primary.prefix(1))
        }

        for item in candidates.sorted(by: { $0.priority > $1.priority }) {
            let trial = ordered(inline + [item])
            if measuredWidth(trial, includeMore: true, mode: mode) <= contentWidth {
                inline = trial
            } else {
                break
            }
        }

        let inlineIDs = Set(inline.map(\.id))
        let overflow = available.filter { !inlineIDs.contains($0.id) }
        return ToolbarSplit(inline: inline, overflow: overflow)
    }

    private func reservedPodWidth(
        time: [GameToolbarItem],
        capture: [GameToolbarItem],
        mode: ToolbarCompactMode
    ) -> CGFloat {
        var reserved: CGFloat = 0
        if !time.isEmpty {
            reserved += timePodWidth(time, mode: mode) + dividerWidth + itemSpacing(mode) * 2
        }
        if !capture.isEmpty {
            reserved += capturePodWidth(capture, mode: mode) + dividerWidth + itemSpacing(mode) * 2
        }
        return reserved
    }

    private func timePodWidth(_ items: [GameToolbarItem], mode: ToolbarCompactMode) -> CGFloat {
        let rewind = items.first { $0.id == .rewind }
        let slow = items.first { $0.id == .slowMotion }
        let fast = items.first { $0.id == .fastForward }

        let bottomWidth: CGFloat
        if slow != nil && fast != nil {
            bottomWidth = itemWidth(.slowMotion, mode: mode) + itemWidth(.fastForward, mode: mode) + itemSpacing(mode)
        } else {
            bottomWidth = (slow.map { itemWidth($0.id, mode: mode) } ?? 0)
                + (fast.map { itemWidth($0.id, mode: mode) } ?? 0)
        }

        let topWidth = rewind.map { itemWidth($0.id, mode: mode) } ?? 0
        return max(topWidth, bottomWidth) + podPadding * 2
    }

    private func capturePodWidth(_ items: [GameToolbarItem], mode: ToolbarCompactMode) -> CGFloat {
        let contentWidth = items.map { itemWidth($0.id, mode: mode) }.max() ?? 0
        return contentWidth + podPadding * 2
    }

    private func measuredWidth(
        _ items: [GameToolbarItem],
        includeMore: Bool,
        mode: ToolbarCompactMode
    ) -> CGFloat {
        var total: CGFloat = 0
        var previousGroup: GameToolbarGroup?
        for item in items {
            if let previousGroup, previousGroup != item.group {
                total += dividerWidth + itemSpacing(mode)
            }
            total += itemWidth(item.id, mode: mode)
            total += itemSpacing(mode)
            previousGroup = item.group
        }
        if includeMore {
            total += dividerWidth + itemSpacing(mode) + moreWidth(mode: mode) + itemSpacing(mode)
        }
        return total
    }

    private func ordered(_ items: [GameToolbarItem]) -> [GameToolbarItem] {
        let groupRank = Dictionary(uniqueKeysWithValues: preferences.groupOrder.enumerated().map { ($0.element, $0.offset) })
        let itemRank = Dictionary(uniqueKeysWithValues: preferences.itemOrder.enumerated().map { ($0.element, $0.offset) })
        return items.sorted {
            let firstGroup = groupRank[$0.group] ?? Int.max
            let secondGroup = groupRank[$1.group] ?? Int.max
            if firstGroup != secondGroup { return firstGroup < secondGroup }
            return (itemRank[$0.id] ?? Int.max) < (itemRank[$1.id] ?? Int.max)
        }
    }

    private func itemWidth(_ id: GameToolbarItemID, mode: ToolbarCompactMode) -> CGFloat {
        if let measured = itemWidths[id] {
            return measured
        }
        switch mode {
        case .full: return 62
        case .compact: return 40
        case .iconOnly: return 30
        }
    }

    private func moreWidth(mode: ToolbarCompactMode) -> CGFloat {
        if measuredMoreWidth > 0 { return measuredMoreWidth }
        switch mode {
        case .full: return 60
        case .compact: return 44
        case .iconOnly: return 32
        }
    }

    private var dividerWidth: CGFloat { 4 }

    private func compactMode(for width: CGFloat) -> ToolbarCompactMode {
        if width >= 980 { return .full }
        if width >= 700 { return .compact }
        return .iconOnly
    }

    private func itemSpacing(_ mode: ToolbarCompactMode) -> CGFloat {
        switch mode {
        case .full: return 4
        case .compact: return 2
        case .iconOnly: return 0
        }
    }

    private func containerPaddingH(_ mode: ToolbarCompactMode) -> CGFloat {
        switch mode {
        case .full: return 10
        case .compact: return 8
        case .iconOnly: return 4
        }
    }

    private func containerPaddingV(_ mode: ToolbarCompactMode) -> CGFloat {
        switch mode {
        case .full: return 6
        case .compact: return 5
        case .iconOnly: return 4
        }
    }

    private func dividerHeight(_ mode: ToolbarCompactMode) -> CGFloat {
        switch mode {
        case .full: return 28
        case .compact: return 22
        case .iconOnly: return 18
        }
    }
}

private struct ToolbarSplit {
    let inline: [GameToolbarItem]
    let overflow: [GameToolbarItem]
}

private enum ToolbarSegment: Identifiable {
    case items(GameToolbarGroup, [GameToolbarItem])
    case time(GameToolbarGroup, [GameToolbarItem])
    case capture(GameToolbarGroup, [GameToolbarItem])

    var id: GameToolbarGroup {
        switch self {
        case .items(let group, _), .time(let group, _), .capture(let group, _):
            return group
        }
    }

    var items: [GameToolbarItem] {
        switch self {
        case .items(_, let items), .time(_, let items), .capture(_, let items):
            return items
        }
    }
}

private struct ToolbarComposition {
    let segments: [ToolbarSegment]
    let overflow: [GameToolbarItem]
    let focusOrder: [GameToolbarItemID]

    static let empty = ToolbarComposition(
        segments: [],
        overflow: [],
        focusOrder: []
    )
}

private struct ToolbarItemWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [GameToolbarItemID: CGFloat] = [:]

    static func reduce(value: inout [GameToolbarItemID: CGFloat], nextValue: () -> [GameToolbarItemID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct ToolbarMoreWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ToolbarHitRectPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
    }
}

private struct GameToolbarItemView: View {
    let item: GameToolbarItem
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject var windowController: StandaloneGameWindowController
    var horizontal: Bool = false
    var textAsIcon: Bool = false

    private var presentation: GameToolbarPresentation {
        GameToolbarPresentationResolver.resolve(
            item: item,
            runner: runner,
            windowController: windowController
        )
    }

    private var button: some View {
        let info = presentation
        return ToolbarButton(
            icon: info.icon,
            label: info.label,
            danger: item.id == .stop,
            disabled: info.disabled,
            active: info.active,
            badge: info.badge,
            horizontal: horizontal,
            textAsIcon: textAsIcon,
            action: { windowController.performToolbarItem(item.id) }
        )
    }

    var body: some View {
        if item.id == .record {
            RecordStreamButton(
                runner: runner,
                isDropdownShown: $windowController.isRecordStreamPickerShown
            )
        } else if item.id == .fullscreen {
            FullscreenToolbarButton(
                item: item,
                runner: runner,
                windowController: windowController
            )
        } else {
            button
        }
    }
}

private struct FullscreenToolbarButton: View {
    let item: GameToolbarItem
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject var windowController: StandaloneGameWindowController
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAutoFullscreen = false

    private var presentation: GameToolbarPresentation {
        GameToolbarPresentationResolver.resolve(
            item: item,
            runner: runner,
            windowController: windowController
        )
    }

    var body: some View {
        let info = presentation
        HStack(spacing: 0) {
            ToolbarButton(
                icon: info.icon,
                label: info.label,
                disabled: info.disabled,
                active: info.active,
                action: { windowController.performToolbarItem(.fullscreen) }
            )
            HoverButton(action: { showAutoFullscreen.toggle() }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .frame(width: fullscreenArrowWidth, height: 30)
                    .contentShape(Rectangle())
            }
            .help(loc.localized("toolbar.autoFullscreen"))
            .accessibilityLabel(loc.localized("toolbar.autoFullscreen"))
            .popover(isPresented: $showAutoFullscreen, arrowEdge: .top) {
                AutoFullscreenPopover(windowController: windowController)
            }
        }
        .onChange(of: showAutoFullscreen) { _, shown in
            if shown {
                windowController.cancelToolbarAutoHide()
            } else {
                windowController.resumeToolbarAutoHide()
            }
        }
    }
}

private struct AutoFullscreenPopover: View {
    @ObservedObject var windowController: StandaloneGameWindowController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            windowController.toggleAutoFullscreen()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(verbatim: loc.localized("toolbar.autoFullscreen"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 12)
                if windowController.autoFullscreenEnabled {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.brandAccent)
                }
            }
            .foregroundColor(AppColors.textPrimary(colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 240)
        .padding(6)
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
    }
}

private struct ToolbarOverflowView: View {
    let items: [GameToolbarItem]
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject var windowController: StandaloneGameWindowController
    @Binding var isPresented: Bool
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var focusIndex = 0
    @State private var hoveredIndex: Int?

    private func presentation(for item: GameToolbarItem) -> GameToolbarPresentation {
        GameToolbarPresentationResolver.resolve(
            item: item,
            runner: runner,
            windowController: windowController
        )
    }

    private func perform(_ item: GameToolbarItem) {
        let source: GameToolbarActionSource = windowController.isGamepadToolbarMode ? .gamepad : .mouse
        let id = item.id
        isPresented = false

        if id == .load || id == .record {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                windowController.performToolbarItem(id, source: source)
            }
        } else {
            windowController.performToolbarItem(id, source: source)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let info = presentation(for: item)
                        let isFocused = windowController.isGamepadToolbarMode && focusIndex == index
                        let isHovered = hoveredIndex == index
                        if index > 0 && items[index - 1].group != item.group {
                            Divider().opacity(0.5)
                        }
                        Button {
                            perform(item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: info.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 18)
                                Text(verbatim: info.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if info.disabled {
                                    Text(verbatim: loc.localized("toolbar.unavailable"))
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.textTertiary(colorScheme))
                                } else if info.active {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppColors.brandAccent)
                                }
                                if let badge = info.badge {
                                    Text(verbatim: badge)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(AppColors.textSecondary(colorScheme))
                                }
                            }
                            .foregroundColor(info.disabled ? AppColors.textTertiary(colorScheme) : (item.id == .stop ? AppColors.error(colorScheme) : AppColors.textPrimary(colorScheme)))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isFocused
                                          ? AppColors.brandAccent.opacity(0.16)
                                          : (isHovered && !info.disabled ? Color.primary.opacity(0.06) : Color.clear))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isFocused ? AppColors.brandAccent : Color.clear, lineWidth: 2)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(info.disabled)
                        .help(info.label)
                        .onHover { hovering in
                            withAnimation(.easeOut(duration: 0.1)) {
                                if hovering {
                                    hoveredIndex = index
                                } else if hoveredIndex == index {
                                    hoveredIndex = nil
                                }
                            }
                        }
                        .id(index)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(width: 260)
            .frame(maxHeight: 420)
            .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onReceive(GamepadNavContextStack.shared.focusPublisher) { _ in
                refreshFocus()
                if focusIndex >= 0 {
                    proxy.scrollTo(focusIndex, anchor: .center)
                }
            }
        }
        .gamepadSheetNav(
            isPresented: $isPresented,
            itemCount: items.count,
            columnCount: 1,
            onSelect: { index in
                guard items.indices.contains(index) else { return }
                perform(items[index])
            }
        )
    }

    private func refreshFocus() {
        if let ctx = GamepadNavContextStack.shared.topActive() as? GamepadSheetContext,
           ctx.itemCount == items.count {
            focusIndex = ctx.focusIndex
        }
    }
}

extension View {
    func gamepadToolbarFocus(index: Int, focusedIndex: Int?) -> some View {
        self.overlay(alignment: .center) {
            if let focused = focusedIndex, focused == index {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.brandAccent, lineWidth: 2)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
    }
}
