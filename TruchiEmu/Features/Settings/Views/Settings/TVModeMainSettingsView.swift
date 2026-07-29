import SwiftUI

/// Main-Settings page that hosts every TV-Mode preference currently split
/// between the in-TV-mode `TVModeSettingsView` sheet and the two leftover
/// `GeneralSettingsView` sections. Built so the user has one obvious place
/// to configure the launcher experience before (or instead of) entering it.
///
/// Sections:
///   1. Behavior — launch in TV Mode by default, show systems in the sidebar
///   2. Theme — bold / muted / boxart (segmented picker)
///   3. Display — screen-selection mode, remembered screen, pick default
///   4. Visible collections — multi-toggle for `SmartEntry`s + systems
///   5. Gamepad buttons — remap X / Y / SELECT / Enter-TV-Mode for TV Mode
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

                // ★ Theme
                if (!isSearching || matchesSearch("theme bold muted boxart style appearance"))
                    && sectionVisible("section-tvModeTheme") {
                    Section(header: Label(loc.localized("settings.tvModeTheme"), systemImage: "paintpalette.fill")) {
                        Picker(loc.localized("settings.tvModeTheme"), selection: Binding(
                            get: { TVModeSettings.theme },
                            set: { newValue in
                                TVModeSettings.setTheme(newValue)
                                NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil)
                            }
                        )) {
                            ForEach(TVModeSettings.Theme.allCases) { theme in
                                Text(loc.localized("tvMode.theme.\(theme.rawValue)")).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

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

                // ★ Visible collections
                if (!isSearching || matchesSearch("collections smart entries favorites recent retro achievements hidden mame systems"))
                    && sectionVisible("section-tvModeCollections") {
                    Section(header: Label(loc.localized("tvMode.settings.shownEntries"), systemImage: "list.bullet")) {
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
                    .id("section-tvModeCollections")
                }

                // ★ System tile icons
                if (!isSearching || matchesSearch("system icon controller emulator tile"))
                    && sectionVisible("section-tvModeSystemIcons") {
                    Section(header: Label(loc.localized("settings.tvModeSystemIcons"), systemImage: "rectangle.on.rectangle.angled")) {
                        Picker(loc.localized("settings.tvModeSystemIcons"), selection: $tvModeSystemIconStyle) {
                            Text(loc.localized("settings.tvModeSystemIcons.default")).tag("default")
                            Text(loc.localized("settings.tvModeSystemIcons.controller")).tag("controller")
                        }
                        .pickerStyle(.menu)
                        .onChange(of: tvModeSystemIconStyle) { _, newValue in
                            AppSettings.setString("tvMode_systemIconStyle", value: newValue)
                        }
                        Text(loc.localized("settings.tvModeSystemIconsDescription"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }
                    .id("section-tvModeSystemIcons")
                }

                // ★ Gamepad buttons
                if (!isSearching || matchesSearch("gamepad controller button remap X Y SELECT enter TV mode"))
                    && sectionVisible("section-tvModeGamepad") {
                    Section(header: Label(loc.localized("settings.tvModeGamepad"), systemImage: "gamecontroller")) {
                        ForEach(tvModeGamepadActions, id: \.self) { action in
                            gamepadActionRow(action)
                        }
                        Text(loc.localized("settings.tvModeGamepadDescription"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }
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
