import SwiftUI

// MARK: - Toolbar Settings

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
        Group {
            if contentLoaded {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            if !isSearching {
                                statPillsRow
                            }

                            settingsCard(
                                id: "section-preview",
                                title: loc.localized("gameToolbar.preview"),
                                icon: "eye",
                                keywords: "toolbar preview layout order"
                            ) {
                                previewSectionContent
                            }

                            settingsCard(
                                id: "section-behavior",
                                title: loc.localized("gameToolbar.behavior"),
                                icon: "slider.horizontal.3",
                                keywords: "toolbar behavior auto hide delay pin visible keep"
                            ) {
                                behaviorSectionContent
                            }

                            settingsCard(
                                id: "section-groups",
                                title: loc.localized("gameToolbar.groups"),
                                icon: "square.grid.2x2",
                                keywords: "toolbar groups order reorder layout"
                            ) {
                                groupOrderSectionContent
                            }

                            ForEach(preferences.groupOrder) { group in
                                settingsCard(
                                    id: "section-\(group.rawValue)",
                                    title: loc.localized(group.localizationKey),
                                    icon: groupIcon(group),
                                    keywords: itemsSectionKeywords(group)
                                ) {
                                    itemsSectionContent(group)
                                }
                            }

                            settingsCard(
                                id: "section-reset",
                                title: loc.localized("gameToolbar.reset"),
                                icon: "arrow.counterclockwise",
                                keywords: "toolbar reset defaults restore"
                            ) {
                                resetSectionContent
                            }

                            if isSearching && !anySectionMatches {
                                noResultsView
                            }

                            Spacer(minLength: AppSpacing.xl5)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                .scrollContentBackground(.hidden)
                .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .navigationTitle(loc.localized("settings.gameToolbar"))
        .onAppear {
            contentLoaded = true
        }
    }

    @State private var contentLoaded = false

    // MARK: - Stat Pills

    private var statPillsRow: some View {
        HStack(spacing: AppSpacing.md) {
            SettingsStatPill(item: .init(
                id: "groups",
                number: "\(preferences.groupOrder.count)",
                label: "groups",
                icon: "square.grid.2x2"
            ))
            SettingsStatPill(item: .init(
                id: "items",
                number: "\(preferences.groupOrder.flatMap { preferences.items(in: $0) }.count)",
                label: "items",
                icon: "slider.horizontal.3"
            ))
        }
        .padding(.bottom, AppSpacing.xs)
    }

    // MARK: - Card Helper

    @ViewBuilder
    private func settingsCard<Content: View>(
        id: String,
        title: String,
        icon: String,
        keywords: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if sectionVisible(id) && matchesSearch(keywords) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                    Text(title)
                        .font(AppTypography.headingSmall)
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                }
                content()
            }
            .padding(AppSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.xl)
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.xl)
                            .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                    )
            )
            .cardHoverEffect(colorScheme: colorScheme)
            .id(id)
        }
    }

    // MARK: - Section Content

    private var previewSectionContent: some View {
        Group {
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
        }
    }

    private var behaviorSectionContent: some View {
        Group {
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
        }
    }

    private var groupOrderSectionContent: some View {
        Group {
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
        }
    }

    private func itemsSectionContent(_ group: GameToolbarGroup) -> some View {
        let items = preferences.items(in: group)
        return Group {
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
        }
    }

    private var resetSectionContent: some View {
        Group {
            Button(loc.localized("gameToolbar.reset")) {
                preferences.resetToDefaults()
            }
        }
    }

    // MARK: - Preview (moved from Form section)

    private var previewGroups: [(group: GameToolbarGroup, items: [GameToolbarItem])] {
        preferences.groupOrder.compactMap { group in
            let items = preferences.items(in: group).filter { preferences.isEnabled($0.id) }
            return items.isEmpty ? nil : (group, items)
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

    // MARK: - Helpers

    private var noResultsView: some View {
        VStack {
            Text(verbatim: loc.localized("general.noMatchingSettings") + " \"\(searchText)\"")
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity)
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

    private func itemsSectionKeywords(_ group: GameToolbarGroup) -> String {
        let items = preferences.items(in: group)
        return items.map { loc.localized($0.labelKey) }.joined(separator: " ") + " " + loc.localized(group.localizationKey)
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
