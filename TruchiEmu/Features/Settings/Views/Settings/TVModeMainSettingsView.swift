import SwiftUI

/// Main-Settings page that hosts every TV-Mode preference currently split
/// between the in-TV-mode `TVModeSettingsView` sheet and the two leftover
/// `GeneralSettingsView` sections. Built so the user has one obvious place
/// to configure the launcher experience before (or instead of) entering it.
///
/// Sections:
///   1. Behavior — launch in TV Mode by default, show systems in the sidebar
///   2. Theme — bold / muted / boxart preview cards inline with the
///      system-tile icon style picker; both give visual feedback of what
///      the user is choosing.
///   3. Display — screen-selection mode, remembered screen, pick default
///   4. Visible collections — multi-toggle for `SmartEntry`s + systems
///      (collapsed by default, expands when search hits it)
///   5. Gamepad buttons — remap X / Y / SELECT / Enter-TV-Mode for TV Mode
///      (collapsed by default, expands when search hits it)
///
/// Design notes:
///   - The theme and screen sections are NEW here — neither exists in the
///     in-TV-mode sheet today.
///   - The visible-collections and screen-selection rows mirror
///     `TVModeSettingsView` so a user who tweaks one place and then enters
///     TV Mode sees the same value, and vice versa.
///   - Gamepad remapping writes through `GamepadNavConfigManager`, the same
///     store used by the Hotkeys page; TV-Mode-specific UI on top is just a
///     curated list of actions.
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
        ScrollViewReader { proxy in
            Form {
                // ★ Behavior
                if (!isSearching || matchesSearch("launch TV Mode default startup systems sidebar"))
                    && sectionVisible("section-tvModeBehavior") {
                    Section(header: Label(loc.localized("settings.tvModeBehavior"), systemImage: "play.rectangle")) {
                        Toggle(loc.localized("tvMode.settings.launchInTVMode"), isOn: Binding(
                            get: { TVModeSettings.launchInTVMode },
                            set: { TVModeSettings.setLaunchInTVMode($0) }
                        ))
                        Text(loc.localized("tvMode.settings.launchInTVModeDescription"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }
                    .id("section-tvModeBehavior")
                }

                // ★ Theme (with visual preview cards) + inline system-icon style picker
                if (!isSearching || matchesSearch("theme bold muted boxart style appearance")
                       || matchesSearch("system icon controller emulator tile"))
                    && sectionVisible("section-tvModeTheme") {
                    Section(header: Label(loc.localized("settings.tvModeTheme"), systemImage: "paintpalette.fill")) {
                        themePreviewRow

                        iconStyleRow

                        Text(loc.localized("settings.tvModeThemeDescription"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }
                    .id("section-tvModeTheme")
                }

                // ★ Display
                if (!isSearching || matchesSearch("display screen external monitor multi display remember reset"))
                    && sectionVisible("section-tvModeDisplay") {
                    Section(header: Label(loc.localized("settings.tvModeDisplay"), systemImage: "display")) {
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
                            Button(loc.localized("settings.tvModePickDefaultScreen")) {
                                showScreenPicker = true
                            }
                            .buttonStyle(.bordered)

                            Button(loc.localized("tvMode.settings.resetScreen")) {
                                TVModeSettings.resetRememberedScreen()
                                generation &+= 1
                            }
                            .buttonStyle(.bordered)
                            .disabled(TVModeSettings.rememberedScreenID == nil)
                        }

                        Text(loc.localized("settings.tvModeDisplayDescription"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }
                    .id("section-tvModeDisplay")
                }

                // ★ Visible collections (collapsed by default, expands on search hit)
                if (!isSearching || matchesSearch("collections smart entries favorites recent retro achievements hidden mame systems"))
                    && sectionVisible("section-tvModeCollections") {
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
                    .id("section-tvModeCollections")
                }

                // ★ Gamepad buttons (collapsed by default, expands on search hit)
                if (!isSearching || matchesSearch("gamepad controller button remap X Y SELECT enter TV mode"))
                    && sectionVisible("section-tvModeGamepad") {
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
                    .id("section-tvModeGamepad")
                }

                if isSearching && !hasMatchingSections {
                    Section {
                        Text("\(loc.localized("general.noMatchingSettings")) \"\(searchText)\"")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, AppSpacing.xl2)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .formStyle(.grouped)
            .onAppear {
                tvModeSystemIconStyle = AppSettings.getString("tvMode_systemIconStyle", defaultValue: "default") ?? "default"
            }
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
            .sheet(isPresented: $showScreenPicker) {
                screenPickerSheet
            }
            .navigationTitle(loc.localized("settings.tvMode"))
        }
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
    /// Each card renders a miniature of the runtime background the user sees
    /// inside TV Mode for that theme, so the choice has immediate visual
    /// feedback instead of being a bare segmented label.
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

    /// Inline system-tile icon-style picker, rendered as two preview tiles
    /// directly under the theme cards so it lives next to the theme it
    /// decorates. Replaces the standalone "System tile icons" section that
    /// previously used a `.menu` Picker of black-box string tags.
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

    /// Toggle the expansion state of a collapsible section, animating the
    /// reveal/hide. Driven by the `DependencySection` binding declared above.
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

    /// Live read of the remembered screen. Reads via `ScreenCatalog.shared`
    /// so the label tracks the current display setup — if the user unplugs
    /// the remembered display, we surface "Disconnected" instead of stale
    /// data. The `generation` bump on reset also forces a re-render.
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

    // MARK: - Screen picker sheet

    /// Reuses `TVModeScreenPickerView` (the same component shown when
    /// entering TV Mode). On pick, persists the chosen screen as the
    /// remembered default and — if the user's selection mode is `.alwaysMain`
    /// or `.ask` — promotes the mode to `.lastUsed` so the choice actually
    /// takes effect on the next TV-Mode entry. Picking never starts TV Mode.
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

/// Single theme preview tile. Renders a miniature of the TV-Mode runtime
/// background the user will actually see for the given `theme`, with an
/// accent ring + checkmark badge when selected — matching the visual
/// idiom of the AccentColorTheme icon buttons in `GeneralSettingsView`.
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

    /// Miniature render of the theme's actual TV-mode background. Static
    /// (non-animated) version of `TVModeView.background` so the preview is
    /// cheap to render and doesn't run a `Task` inside the Settings form.
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
                // Static placeholder for the blurred-boxart backdrop. A
                // dark gradient evokes the dimmed photo treatment used by
                // `TVModeBoxartBackdrop` without depending on a live ROM.
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

/// Single icon-style preview tile for the system-tile icon picker. Shows a
/// representative rendering of either "default" (emulator icon square grid)
/// or "controller" (gamepad glyph), matching the runtime system-tile icon
/// styles used in TV Mode. Same selected-ring + checkmark treatment as
/// the theme preview cards.
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
