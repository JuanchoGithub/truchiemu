import SwiftUI

/// Main-Settings page that hosts every TV-Mode preference currently split
/// between the in-TV-mode `TVModeSettingsView` sheet and the two leftover
/// `GeneralSettingsView` sections. Built so the user has one obvious place
/// to configure the launcher experience before (or instead of) entering it.
struct TVModeMainSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var gamepadNav = GamepadNavConfigManager.shared

    @State private var tvModeSystemIconStyle: String = "default"
    @State private var showScreenPicker: Bool = false
    @State private var generation: Int = 0  // forces re-read of TVModeSettings getters
    @State private var expandedSections: Set<String> = []

    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.tvMode, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    private var hasMatchingSections: Bool {
        guard isSearching else { return true }
        return matchesSearch("launch TV Mode default startup systems sidebar")
            || matchesSearch("theme bold muted boxart style appearance")
            || matchesSearch("display screen external monitor multi display remember reset")
            || matchesSearch("collections smart entries favorites recent retro achievements hidden mame systems")
            || matchesSearch("system icon controller emulator tile")
            || matchesSearch("gamepad controller button remap X Y SELECT enter TV mode")
    }

    var body: some View {
        Group {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        // ★ Behavior
                        settingsCard(
                            id: "section-tvModeBehavior",
                            title: loc.localized("settings.tvModeBehavior"),
                            icon: "play.rectangle",
                            keywords: "launch TV Mode default startup systems sidebar"
                        ) {
                            Toggle(loc.localized("tvMode.settings.launchInTVMode"), isOn: Binding(
                                get: { TVModeSettings.launchInTVMode },
                                set: { TVModeSettings.setLaunchInTVMode($0) }
                            ))
                            Text(loc.localized("tvMode.settings.launchInTVModeDescription"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                        }

                        // ★ Theme (with visual preview cards) + inline system-icon style picker
                        settingsCard(
                            id: "section-tvModeTheme",
                            title: loc.localized("settings.tvModeTheme"),
                            icon: "paintpalette.fill",
                            keywords: "theme bold muted boxart style appearance system icon controller emulator tile"
                        ) {
                            themePreviewRow
                            iconStyleRow
                            Text(loc.localized("settings.tvModeThemeDescription"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                        }

                        // ★ Display
                        settingsCard(
                            id: "section-tvModeDisplay",
                            title: loc.localized("settings.tvModeDisplay"),
                            icon: "display",
                            keywords: "display screen external monitor multi display remember reset"
                        ) {
                            Picker(loc.localized("tvMode.settings.screenSelection"), selection: Binding(
                                get: { TVModeSettings.screenSelectionMode },
                                set: { TVModeSettings.setScreenSelectionMode($0) }
                            )) {
                                ForEach(TVModeSettings.ScreenSelectionMode.allCases) { mode in
                                    Text(loc.localized(mode.locKey)).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)

                            LabeledContent(loc.localized("tvMode.settings.rememberedScreen")) {
                                Text(rememberedScreenSummary)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            HStack {
                                SettingsActionButton(loc.localized("settings.tvModePickDefaultScreen")) {
                                    showScreenPicker = true
                                }

                                SettingsActionButton(loc.localized("tvMode.settings.resetScreen")) {
                                    TVModeSettings.resetRememberedScreen()
                                    generation &+= 1
                                }
                                .disabled(TVModeSettings.rememberedScreenID == nil)
                            }

                            Text(loc.localized("settings.tvModeDisplayDescription"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                        }

                        // ★ Visible collections (collapsed by default, expands on search hit)
                        settingsCard(
                            id: "section-tvModeCollections",
                            title: loc.localized("tvMode.settings.shownEntries"),
                            icon: "square.stack.3d.up.fill",
                            keywords: "collections smart entries favorites recent retro achievements hidden mame systems"
                        ) {
                            DependencySection(
                                title: loc.localized("tvMode.settings.shownEntries"),
                                isExpanded: Binding(
                                    get: { isSearching || expandedSections.contains("section-tvModeCollections") },
                                    set: { isOn in toggleSection("section-tvModeCollections", isOn: isOn) }
                                )
                            ) {
                                ForEach(TVModeSettings.SmartEntry.allCases) { entry in
                                    Toggle(loc.localized(entry.locKey), isOn: Binding(
                                        get: { _ = generation; return TVModeSettings.shownSmartEntries.contains(entry) },
                                        set: { isOn in
                                            var current = Set(TVModeSettings.shownSmartEntries)
                                            if isOn { current.insert(entry) } else { current.remove(entry) }
                                            TVModeSettings.setShownSmartEntries(Array(current).sorted { $0.rawValue < $1.rawValue })
                                            NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil)
                                        }
                                    ))
                                }
                                Toggle(loc.localized("tvMode.settings.systems"), isOn: Binding(
                                    get: { TVModeSettings.showSystems },
                                    set: { TVModeSettings.setShowSystems($0) }
                                ))
                                Text(loc.localized("settings.tvModeCollectionsDescription"))
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                            }
                            .padding(.vertical, AppSpacing.sm)
                        }

                        // ★ Gamepad buttons (collapsed by default, expands on search hit)
                        settingsCard(
                            id: "section-tvModeGamepad",
                            title: loc.localized("settings.tvModeGamepad"),
                            icon: "gamecontroller",
                            keywords: "gamepad controller button remap X Y SELECT enter TV mode"
                        ) {
                            DependencySection(
                                title: loc.localized("settings.tvModeGamepad"),
                                isExpanded: Binding(
                                    get: { isSearching || expandedSections.contains("section-tvModeGamepad") },
                                    set: { isOn in toggleSection("section-tvModeGamepad", isOn: isOn) }
                                )
                            ) {
                                ForEach(tvModeGamepadActions, id: \.self) { action in
                                    gamepadActionRow(action)
                                }
                                Text(loc.localized("settings.tvModeGamepadDescription"))
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                            }
                            .padding(.vertical, AppSpacing.sm)
                        }

                        if isSearching && !hasMatchingSections {
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
            .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
            .sheet(isPresented: $showScreenPicker) {
                screenPickerSheet
            }
            .navigationTitle(loc.localized("settings.tvMode"))
            .onAppear {
                tvModeSystemIconStyle = AppSettings.getString("tvMode_systemIconStyle", defaultValue: "default") ?? "default"
            }
        }
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

    // MARK: - Gamepad row

    /// TV-mode-relevant subset of `GamepadNavAction`. Matches the actions
    /// the in-TV-mode overlay currently responds to, so the user can rebind
    /// them without having to dig through the full Hotkeys page.
    private var tvModeGamepadActions: [GamepadNavAction] {
        [.toggleViewMode, .contextMenu, .openSettings, .enterTVMode]
    }

    @ViewBuilder
    private func gamepadActionRow(_ action: GamepadNavAction) -> some View {
        HStack {
            Text(loc.localized(action.localizationKey))
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: Binding(
                get: { gamepadNav.button(for: action) },
                set: { newValue in
                    gamepadNav.update(action, binding: GamepadNavBinding(button: newValue))
                }
            )) {
                Text(loc.localized("gamepadNav.unbound")).tag(GamepadNavButton?.none)
                ForEach(GamepadNavButton.availableForMapping, id: \.self) { button in
                    Text(button.displayName).tag(GamepadNavButton?.some(button))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: - Theme / icon-style preview rows

    /// Horizontal row of three theme preview cards (bold / muted / boxart).
    @ViewBuilder
    private var themePreviewRow: some View {
        HStack(spacing: AppSpacing.lg) {
            ForEach(TVModeSettings.Theme.allCases) { theme in
                TVModeThemePreviewCard(
                    theme: theme,
                    colorScheme: colorScheme,
                    isSelected: TVModeSettings.theme == theme,
                    label: loc.localized("tvMode.theme.\(theme.rawValue)")
                ) {
                    TVModeSettings.setTheme(theme)
                    NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil)
                    generation &+= 1
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    /// Inline system-tile icon-style picker.
    @ViewBuilder
    private var iconStyleRow: some View {
        Divider().padding(.vertical, AppSpacing.xs)

        Text(loc.localized("settings.tvModeSystemIcons"))
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(AppColors.textSecondary(colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: AppSpacing.lg) {
            TVModeIconStyleTile(
                style: "default",
                colorScheme: colorScheme,
                isSelected: tvModeSystemIconStyle == "default",
                label: loc.localized("settings.tvModeSystemIcons.default")
            ) {
                tvModeSystemIconStyle = "default"
                AppSettings.setString("tvMode_systemIconStyle", value: "default")
            }
            TVModeIconStyleTile(
                style: "controller",
                colorScheme: colorScheme,
                isSelected: tvModeSystemIconStyle == "controller",
                label: loc.localized("settings.tvModeSystemIcons.controller")
            ) {
                tvModeSystemIconStyle = "controller"
                AppSettings.setString("tvMode_systemIconStyle", value: "controller")
            }
        }
        .padding(.vertical, AppSpacing.xs)

        Text(loc.localized("settings.tvModeSystemIconsDescription"))
            .font(.caption)
            .foregroundStyle(AppColors.textSecondary(colorScheme))
    }

    // MARK: - Collapsible-section helpers

    private func toggleSection(_ id: String, isOn: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if isOn {
                expandedSections.insert(id)
            } else {
                expandedSections.remove(id)
            }
        }
    }

    // MARK: - Helpers

    private var rememberedScreenSummary: String {
        _ = generation
        guard let id = TVModeSettings.rememberedScreenID else {
            return loc.localized("tvMode.settings.rememberedScreen.none")
        }
        if let screen = ScreenCatalog.shared.screens.first(where: { $0.id == id }) {
            return screen.name
        }
        return loc.localized("tvMode.settings.rememberedScreen.unavailable")
    }

    private var noResultsView: some View {
        VStack {
            Text("\(loc.localized("general.noMatchingSettings")) \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppSpacing.xl2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Screen picker sheet

    @ViewBuilder
    private var screenPickerSheet: some View {
        let screens = ScreenCatalog.shared.screens
        let initialFocus: Int = {
            if let stored = TVModeSettings.rememberedScreenID,
               let idx = screens.firstIndex(where: { $0.id == stored }) {
                return idx
            }
            if let mainID = ScreenCatalog.shared.mainScreenID,
               let idx = screens.firstIndex(where: { $0.id == mainID }) {
                return idx
            }
            return 0
        }()
        TVModeScreenPickerView(
            screens: screens,
            initialFocusIndex: initialFocus,
            onSelect: { descriptor in
                TVModeSettings.setRememberedScreenID(descriptor.id)
                if TVModeSettings.screenSelectionMode != .lastUsed {
                    TVModeSettings.setScreenSelectionMode(.lastUsed)
                }
                generation &+= 1
                showScreenPicker = false
            },
            onCancel: {
                showScreenPicker = false
            }
        )
        .frame(minWidth: 640, minHeight: 460)
    }
}

// MARK: - Theme preview card

private struct TVModeThemePreviewCard: View {
    let theme: TVModeSettings.Theme
    let colorScheme: ColorScheme
    let isSelected: Bool
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    private let previewWidth: CGFloat = 140
    private let previewHeight: CGFloat = 84

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                previewBackground
                    .frame(width: previewWidth, height: previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .strokeBorder(
                                isSelected ? AppColors.accentForScheme(colorScheme) : Color.primary.opacity(0.1),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .padding(4)
                    }
                }
                .scaleEffect(isHovered ? 1.04 : 1.0)
                .animation(AppMotion.micro, value: isHovered)

                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected
                        ? AppColors.textPrimary(colorScheme)
                        : AppColors.textTertiary(colorScheme))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var previewBackground: some View {
        switch theme {
        case .bold:
            ZStack {
                AppColors.windowBackground(colorScheme, tinted: true)
                RadialGradient(
                    colors: [
                        AppColors.accentForScheme(colorScheme).opacity(0.28),
                        .clear
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: previewHeight * 1.4
                )
                RadialGradient(
                    colors: [
                        AppColors.accentForScheme(colorScheme).opacity(0.22),
                        .clear
                    ],
                    center: .bottom,
                    startRadius: 0,
                    endRadius: previewHeight * 1.2
                )
            }
        case .muted:
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.08)
                RadialGradient(
                    colors: [Color.white.opacity(0.06), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: previewHeight * 0.9
                )
            }
        case .boxart:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.20, blue: 0.26),
                        Color(red: 0.05, green: 0.05, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Color.black.opacity(0.45)
                VStack(spacing: 2) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(verbatim: "Boxart")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
}

// MARK: - System tile icon-style preview tile

private struct TVModeIconStyleTile: View {
    let style: String
    let colorScheme: ColorScheme
    let isSelected: Bool
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    private let tileWidth: CGFloat = 80
    private let tileHeight: CGFloat = 84

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(AppColors.cardBackground(colorScheme))
                    Image(systemName: style == "controller" ? "gamecontroller.fill" : "square.grid.2x2.fill")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(AppColors.accentForScheme(colorScheme).opacity(0.85))
                }
                .frame(width: tileWidth, height: tileHeight)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .strokeBorder(
                            isSelected ? AppColors.accentForScheme(colorScheme) : Color.primary.opacity(0.1),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .padding(3)
                    }
                }
                .scaleEffect(isHovered ? 1.04 : 1.0)
                .animation(AppMotion.micro, value: isHovered)

                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected
                        ? AppColors.textPrimary(colorScheme)
                        : AppColors.textTertiary(colorScheme))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
