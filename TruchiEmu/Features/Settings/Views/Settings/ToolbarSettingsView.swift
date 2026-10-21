import SwiftUI

struct ToolbarSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var preferences = GameToolbarPreferences.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.gameToolbar, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                previewSection
                behaviorSection
                groupOrderSection
                ForEach(preferences.groupOrder) { group in
                    itemsSection(group)
                }
                resetSection
                noMatchSection
            }
            .scrollContentBackground(.hidden)
            .formStyle(.grouped)
            .onChange(of: focusedSectionID) { _, newID in
                guard let id = newID else { return }
                withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
            }
            .onChange(of: scopedSectionID) { _, newScope in
                guard let id = newScope else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
                }
            }
        }
    }

    private var previewGroups: [(group: GameToolbarGroup, items: [GameToolbarItem])] {
        preferences.groupOrder.compactMap { group in
            let items = preferences.items(in: group).filter { preferences.isEnabled($0.id) }
            return items.isEmpty ? nil : (group, items)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if matchesSearch("toolbar preview layout order") && sectionVisible("section-preview") {
            Section(content: {
                if previewGroups.isEmpty {
                    Text(verbatim: loc.localized("gameToolbar.previewEmpty"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        previewToolbar
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(12)
                    }
                }
            }, header: {
                Label { Text(verbatim: loc.localized("gameToolbar.preview")) } icon: { Image(systemName: "eye") }
            }, footer: {
                Text(verbatim: loc.localized("gameToolbar.previewDescription"))
            })
            .id("section-preview")
        }
    }

    private var previewToolbar: some View {
        HStack(spacing: 4) {
            ForEach(Array(previewGroups.enumerated()), id: \.element.group) { index, entry in
                if index > 0 {
                    previewDivider
                }
                previewSegment(entry)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    AppColors.windowBackground(
                        colorScheme,
                        tinted: themeManager.tintedSurfacesEnabled
                    )
                    .opacity(0.92)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.cardBorder(colorScheme), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 12, x: 0, y: 4)
        .environment(\.toolbarCompactMode, .full)
    }

    @ViewBuilder
    private func previewSegment(_ entry: (group: GameToolbarGroup, items: [GameToolbarItem])) -> some View {
        switch entry.group {
        case .time:
            previewTimePod(entry.items)
        case .capture:
            previewCapturePod(entry.items)
        default:
            HStack(spacing: 4) {
                ForEach(entry.items) { item in
                    previewItem(item)
                }
            }
        }
    }

    private func previewTimePod(_ items: [GameToolbarItem]) -> some View {
        let rewind = items.first { $0.id == .rewind }
        let speeds = items.filter { $0.id == .slowMotion || $0.id == .fastForward }
        return Grid(horizontalSpacing: 4, verticalSpacing: 2) {
            if let rewind {
                GridRow {
                    previewItem(rewind, horizontal: true)
                        .gridCellColumns(max(1, speeds.count))
                }
            }
            if !speeds.isEmpty {
                GridRow {
                    ForEach(speeds) { item in
                        previewItem(item, textAsIcon: true)
                    }
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.cardBorder(colorScheme), lineWidth: 0.5)
        )
    }

    private func previewCapturePod(_ items: [GameToolbarItem]) -> some View {
        VStack(spacing: 2) {
            ForEach(items) { item in
                previewItem(item)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.cardBorder(colorScheme), lineWidth: 0.5)
        )
    }

    private func previewItem(
        _ item: GameToolbarItem,
        horizontal: Bool = false,
        textAsIcon: Bool = false
    ) -> some View {
        HStack(spacing: 0) {
            ToolbarButtonContent(
                icon: item.icon,
                label: previewLabel(for: item),
                horizontal: horizontal,
                textAsIcon: textAsIcon
            )
            .foregroundColor(item.id == .stop ? AppColors.error(colorScheme) : AppColors.textPrimary(colorScheme))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.id == .stop ? AppColors.error(colorScheme).opacity(0.15) : Color.clear)
            )

            if item.id == .fullscreen {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .frame(width: 12, height: 30)
            }
        }
    }

    private func previewLabel(for item: GameToolbarItem) -> String {
        switch item.id {
        case .fastForward:
            return "2x"
        case .slowMotion:
            return "0.5x"
        default:
            return loc.localized(item.labelKey)
        }
    }

    private var previewDivider: some View {
        Rectangle()
            .fill(AppColors.divider(colorScheme))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 1.5)
    }

    @ViewBuilder
    private var groupOrderSection: some View {
        if matchesSearch("toolbar groups order reorder layout") && sectionVisible("section-groups") {
            Section(content: {
                ForEach(preferences.groupOrder) { group in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                            .frame(width: 16, height: 24)
                            .contentShape(Rectangle())
                            .draggable(group.rawValue)
                            .help(loc.localized("gameToolbar.dragToReorder"))
                        Image(systemName: groupIcon(group))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.brandAccent)
                            .frame(width: 18)
                        Text(verbatim: loc.localized(group.localizationKey))
                            .font(.body)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { payload, _ in
                        guard let raw = payload.first,
                              let dragged = GameToolbarGroup(rawValue: raw) else { return false }
                        preferences.moveGroup(dragged, to: group)
                        return true
                    }
                }
            }, header: {
                Label { Text(verbatim: loc.localized("gameToolbar.groups")) } icon: { Image(systemName: "square.grid.2x2") }
            }, footer: {
                Text(verbatim: loc.localized("gameToolbar.groupsDescription"))
            })
            .id("section-groups")
        }
    }

    @ViewBuilder
    private var behaviorSection: some View {
        if matchesSearch("toolbar behavior auto hide delay pin visible keep") && sectionVisible("section-behavior") {
            Section(content: {
                SettingsRow(
                    loc.localized("gameToolbar.pinVisible"),
                    description: loc.localized("gameToolbar.pinVisibleDescription")
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.pinVisible },
                        set: { preferences.pinVisible = $0 }
                    ))
                    .labelsHidden()
                    .accessibilityLabel(loc.localized("gameToolbar.pinVisible"))
                }

                SettingsRow(
                    loc.localized("gameToolbar.autoHideDelay"),
                    description: loc.localized("gameToolbar.autoHideDelayDescription")
                ) {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { preferences.autoHideDelay },
                                set: { preferences.autoHideDelay = $0 }
                            ),
                            in: 1...15,
                            step: 0.5
                        )
                        .frame(width: 160)
                        .accessibilityLabel(loc.localized("gameToolbar.autoHideDelay"))
                        Text(verbatim: String(format: "%.1fs", preferences.autoHideDelay))
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }, header: {
                Label { Text(verbatim: loc.localized("gameToolbar.behavior")) } icon: { Image(systemName: "slider.horizontal.3") }
            }, footer: {
                Text(verbatim: loc.localized("gameToolbar.behaviorDescription"))
            })
            .id("section-behavior")
        }
    }

    @ViewBuilder
    private func itemsSection(_ group: GameToolbarGroup) -> some View {
        let items = preferences.items(in: group)
        let keywords = items.map { loc.localized($0.labelKey) }.joined(separator: " ") + " " + loc.localized(group.localizationKey)
        if !items.isEmpty && matchesSearch(keywords) && sectionVisible("section-\(group.rawValue)") {
            Section(content: {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                            .frame(width: 16, height: 24)
                            .contentShape(Rectangle())
                            .draggable(item.id.rawValue)
                            .help(loc.localized("gameToolbar.dragToReorder"))
                        SettingsRow(
                            loc.localized(item.labelKey),
                            description: item.isRequired ? loc.localized("gameToolbar.requiredDescription") : nil
                        ) {
                            Toggle("", isOn: Binding(
                                get: { preferences.isEnabled(item.id) },
                                set: { preferences.setEnabled(item.id, $0) }
                            ))
                            .labelsHidden()
                            .disabled(item.isRequired)
                            .accessibilityLabel(loc.localized(item.labelKey))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { payload, _ in
                        guard let raw = payload.first,
                              let dragged = GameToolbarItemID(rawValue: raw),
                              preferences.items(in: group).contains(where: { $0.id == dragged }) else { return false }
                        preferences.moveItem(dragged, to: item.id)
                        return true
                    }
                }
            }, header: {
                Label {
                    Text(verbatim: loc.localized(group.localizationKey))
                } icon: {
                    Image(systemName: groupIcon(group))
                }
            })
            .id("section-\(group.rawValue)")
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        if matchesSearch("toolbar reset defaults restore") && sectionVisible("section-reset") {
            Section {
                Button(loc.localized("gameToolbar.reset")) {
                    preferences.resetToDefaults()
                }
            } footer: {
                Text(verbatim: loc.localized("gameToolbar.resetDescription"))
            }
            .id("section-reset")
        }
    }

    @ViewBuilder
    private var noMatchSection: some View {
        if isSearching && !anySectionMatches {
            Section {
                Text(verbatim: loc.localized("general.noMatchingSettings") + " \"\(searchText)\"")
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }
        }
    }

    private var anySectionMatches: Bool {
        if matchesSearch("toolbar preview layout order") { return true }
        if matchesSearch("toolbar behavior auto hide delay pin visible keep") { return true }
        if matchesSearch("toolbar groups order reorder layout") { return true }
        for group in preferences.groupOrder {
            let items = preferences.items(in: group)
            let keywords = items.map { loc.localized($0.labelKey) }.joined(separator: " ") + " " + loc.localized(group.localizationKey)
            if matchesSearch(keywords) { return true }
        }
        if matchesSearch("toolbar reset defaults restore") { return true }
        return false
    }

    private func groupIcon(_ group: GameToolbarGroup) -> String {
        switch group {
        case .window: return "macwindow"
        case .playback: return "playpause.fill"
        case .state: return "tray.and.arrow.down.fill"
        case .capture: return "camera.fill"
        case .time: return "clock.arrow.circlepath"
        case .tools: return "wrench.and.screwdriver.fill"
        case .view: return "rectangle.expand.vertical"
        }
    }
}
