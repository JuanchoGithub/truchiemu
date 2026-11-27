import SwiftUI

// MARK: - Main Settings Page (General)

// Redesigned settings page inspired by modern design inspiration platforms:
// card-based layout, stat pill chips at the top, large rounded corners,
// strong typography hierarchy, and interactive hover states.
struct GeneralSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @State private var autoCheckUpdates: Bool = true
    @State private var notificationsEnabled: Bool = false
    @State private var boxArtPivotingEnabled: Bool = true
    @State private var hltbEnabled: Bool = true
    @State private var categoryAskToAddAfterCreate: Bool = true
    @State private var openCriticAPIKey: String = ""

    @State private var pending = PendingThemeSettings()
    @Binding var hasPendingChanges: Bool
    @Binding var revertRequest: Int
    @Binding var applyRequest: Int
    @Binding var activePending: PendingThemeSettings

    @State private var contentLoaded = false
    @State private var showThemeStudio = false

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var prefs = SystemPreferences.shared
    @ObservedObject private var openCritic = OpenCriticService.shared

    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil),
         hasPendingChanges: Binding<Bool> = .constant(false),
         revertRequest: Binding<Int> = .constant(0),
         applyRequest: Binding<Int> = .constant(0),
         activePending: Binding<PendingThemeSettings> = .constant(PendingThemeSettings())) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
        self._hasPendingChanges = hasPendingChanges
        self._revertRequest = revertRequest
        self._applyRequest = applyRequest
        self._activePending = activePending
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.general, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    var body: some View {
        Group {
            if contentLoaded {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            // Stat pill chips (inspired by the number pills on the
                            // design inspiration page). Only shown when not searching.
                            if !isSearching {
                                statPillsRow
                            }

                            // MARK: - Language & Region
                            settingsCard(
                                id: "section-languageRegion",
                                title: loc.localized("settings.languageRegion"),
                                icon: "globe",
                                keywords: "Language Region systems language emulation core country localization"
                            ) {
                                languageRegionContent
                            }

                            // MARK: - Theme
                            settingsCard(
                                id: "section-theme",
                                title: loc.localized("settings.theme"),
                                icon: "paintpalette",
                                keywords: "Theme accent color appearance mode light dark gaming tinted surfaces toolbar"
                            ) {
                                themeContent
                            }

                            // MARK: - Library Hero
                            settingsCard(
                                id: "section-libraryHero",
                                title: loc.localized("settings.libraryHero.section"),
                                icon: "rectangle.grid.1x2",
                                keywords: "library hero header collection banner show hide"
                            ) {
                                libraryHeroContent
                            }

                            // MARK: - Quick Access
                            settingsCard(
                                id: "section-sidebarQuickAccess",
                                title: loc.localized("settings.sidebarQuickAccess.section"),
                                icon: "square.grid.2x2",
                                keywords: "sidebar quick access tiles all games favorites recent show hide collapse"
                            ) {
                                quickAccessContent
                            }

                            // MARK: - Box Art Pivoting
                            settingsCard(
                                id: "section-boxart-pivoting",
                                title: loc.localized("boxArt.pivoting"),
                                icon: "cube.transparent",
                                keywords: "boxArt pivoting 3D tilt cursor"
                            ) {
                                boxArtContent
                            }

                            // MARK: - Categories
                            settingsCard(
                                id: "section-categories",
                                title: loc.localized("app.categories"),
                                icon: "folder",
                                keywords: "categories category add game prompt ask create"
                            ) {
                                categoriesContent
                            }

                            // MARK: - Application
                            settingsCard(
                                id: "section-application",
                                title: loc.localized("settings.application"),
                                icon: "app.badge",
                                keywords: "Application version build notifications updates"
                            ) {
                                applicationContent
                            }

                            // MARK: - OpenCritic
                            settingsCard(
                                id: "section-openCritic",
                                title: loc.localized("settings.openCritic"),
                                icon: "star",
                                keywords: "OpenCritic API key truchiemu reviews scores"
                            ) {
                                openCriticContent
                            }

                            // No results message
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
                .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .navigationTitle("General")
        .sheet(isPresented: $showThemeStudio) {
            ThemeStudioView {
                pending.theme = themeManager.currentTheme
                pending.appearanceMode = themeManager.appearanceMode
                pending.customColor = themeManager.customAccentColor
                pending.toolbarAccent = themeManager.toolbarAccentEnabled
                pending.tintedSurfaces = themeManager.tintedSurfacesEnabled
                activePending = pending
                hasPendingChanges = false
            }
        }
        .onAppear {
            NotificationService.shared.refreshAuthorizationStatus()
            autoCheckUpdates = AppUpdateService.shared.autoCheckEnabled
            notificationsEnabled = NotificationService.shared.isAuthorized
            boxArtPivotingEnabled = prefs.boxArtPivotingEnabled()
            hltbEnabled = AppSettings.getBool("hltbEnabled", defaultValue: true)
            categoryAskToAddAfterCreate = AppSettings.getBool(GameCategory.askToAddAfterCreateSettingsKey, defaultValue: true)
            openCriticAPIKey = OpenCriticService.shared.apiKey ?? ""
            pending.theme = themeManager.currentTheme
            pending.appearanceMode = themeManager.appearanceMode
            pending.customColor = themeManager.customAccentColor
            pending.toolbarAccent = themeManager.toolbarAccentEnabled
            pending.tintedSurfaces = themeManager.tintedSurfacesEnabled
            activePending = pending
            hasPendingChanges = false
            DispatchQueue.main.async {
                contentLoaded = true
            }
        }
        .onChange(of: autoCheckUpdates) { _, newValue in
            AppUpdateService.shared.autoCheckEnabled = newValue
        }
        .onChange(of: boxArtPivotingEnabled) { _, newValue in
            prefs.setBoxArtPivotingEnabled(newValue)
        }
        .onChange(of: hltbEnabled) { _, newValue in
            AppSettings.setBool("hltbEnabled", value: newValue)
        }
        .onChange(of: categoryAskToAddAfterCreate) { _, newValue in
            AppSettings.setBool(GameCategory.askToAddAfterCreateSettingsKey, value: newValue)
        }
        .onChange(of: openCriticAPIKey) { _, newValue in
            OpenCriticService.shared.apiKey = newValue.isEmpty ? nil : newValue
        }
        .onChange(of: pending.theme) { _, _ in
            activePending.theme = pending.theme
            hasPendingChanges = themeHasChanged
        }
        .onChange(of: pending.appearanceMode) { _, _ in
            activePending.appearanceMode = pending.appearanceMode
            hasPendingChanges = themeHasChanged
        }
        .onChange(of: pending.customColor) { _, _ in
            activePending.customColor = pending.customColor
            hasPendingChanges = themeHasChanged
        }
        .onChange(of: pending.toolbarAccent) { _, _ in
            activePending.toolbarAccent = pending.toolbarAccent
            hasPendingChanges = themeHasChanged
        }
        .onChange(of: pending.tintedSurfaces) { _, _ in
            activePending.tintedSurfaces = pending.tintedSurfaces
            hasPendingChanges = themeHasChanged
        }
        .onChange(of: revertRequest) { _, _ in
            pending.theme = themeManager.currentTheme
            pending.appearanceMode = themeManager.appearanceMode
            pending.customColor = themeManager.customAccentColor
            pending.toolbarAccent = themeManager.toolbarAccentEnabled
            pending.tintedSurfaces = themeManager.tintedSurfacesEnabled
            hasPendingChanges = false
        }
        .onChange(of: applyRequest) { _, _ in
            guard themeHasChanged else { return }
            themeManager.applyTheme(pending.theme, customColor: pending.theme == .custom ? pending.customColor : nil)
            themeManager.setToolbarAccent(pending.toolbarAccent)
            themeManager.setTintedSurfaces(pending.tintedSurfaces)
            themeManager.applyAppearanceMode(pending.appearanceMode)
            themeManager.themeRevision += 1
            hasPendingChanges = false
        }
    }

    // MARK: - Stat Pills Row

    /// A horizontal row of stat pill chips echoing the number pills on the
    /// design inspiration page (e.g. "168 blocks", "261 finds").
    private var statPillsRow: some View {
        HStack(spacing: AppSpacing.md) {
            ForEach(statPills) { pill in
                SettingsStatPill(item: pill)
            }
        }
        .padding(.bottom, AppSpacing.xs)
    }

    private var statPills: [SettingsStatPill.Item] {
        var items: [SettingsStatPill.Item] = []
        items.append(SettingsStatPill.Item(
            id: "theme",
            number: themeManager.currentTheme.displayName,
            label: loc.localized("settings.unit.theme"),
            icon: "paintpalette.fill"
        ))
        items.append(SettingsStatPill.Item(
            id: "language",
            number: loc.currentLanguage.uppercased(),
            label: loc.localized("settings.unit.language"),
            icon: "globe"
        ))
        items.append(SettingsStatPill.Item(
            id: "version",
            number: "v\(AppVersion.current)",
            label: loc.localized("settings.unit.version"),
            icon: "tag.fill"
        ))
        return items
    }

    // MARK: - Card Helper

    /// Wraps a settings section in a rounded card with an icon + title header,
    /// matching the inspiration page's card aesthetic.
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

    private var languageRegionContent: some View {
        Group {
            Picker(loc.localized("settings.selectLanguage"), selection: Binding<String>(
                get: { loc.currentLanguage },
                set: { loc.setLanguage($0) })
            ) {
                ForEach(loc.availableLanguages, id: \.self) { lang in
                    Text("\(languageFlag(for: lang)) \(languageDisplayName(for: lang))")
                        .tag(lang)
                }
            }
            .pickerStyle(.menu)

            Picker(loc.localized("library.gameRegion"), selection: $prefs.systemLanguage) {
                ForEach(EmulatorLanguage.allCases) { lang in
                    Text("\(lang.flagEmoji) \(lang.name)").tag(lang)
                }
            }
            Text(loc.localized("library.regionDescription"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
    }

    private var themeContent: some View {
        Group {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(loc.localized("settings.appearance"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))

                Picker(loc.localized("settings.appearance"), selection: Binding<AppearanceMode>(
                    get: { pending.appearanceMode },
                    set: { pending.appearanceMode = $0 }
                )) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: mode.systemImageName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: AppSpacing.md) {
                CustomThemeButton(isSelected: pending.theme == .custom) {
                    pending.theme = .custom
                }

                ForEach(AccentColorTheme.allCases.filter { !$0.isCustom }, id: \.self) { theme in
                    themeGridButton(theme)
                }
            }

            if pending.theme == .custom {
                ColorPicker(loc.localized("settings.customColor"), selection: $pending.customColor, supportsOpacity: false)
            }

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xl) {
                Toggle(loc.localized("settings.toolbarAccent"), isOn: $pending.toolbarAccent)
                Spacer(minLength: AppSpacing.md)
                Toggle(loc.localized("settings.tintedSurfaces"), isOn: $pending.tintedSurfaces)
            }
            HStack(alignment: .top, spacing: AppSpacing.xl) {
                Text(loc.localized("settings.toolbarAccentDescription"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(loc.localized("settings.tintedSurfacesDescription"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(loc.localized("settings.theme.previewTitle"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))

                ThemePreviewCard(
                    accent: previewAccent,
                    accentDimmed: previewAccentDimmed,
                    accentDark: previewAccentDark,
                    accentSecondary: previewAccentSecondary,
                    mode: pending.appearanceMode,
                    tinted: pending.tintedSurfaces
                )
            }

            Button(loc.localized("settings.theme.applyTheme")) {
                themeManager.applyTheme(pending.theme, customColor: pending.theme == .custom ? pending.customColor : nil)
                themeManager.setToolbarAccent(pending.toolbarAccent)
                themeManager.applyAppearanceMode(pending.appearanceMode)
                themeManager.themeRevision += 1
                hasPendingChanges = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(!themeHasChanged)
            .frame(maxWidth: .infinity)

            Button {
                showThemeStudio = true
            } label: {
                Label(loc.localized("themeStudio.open"), systemImage: "swatchpalette")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var libraryHeroContent: some View {
        Group {
            Toggle(loc.localized("settings.libraryHero.show"), isOn: $prefs.showLibraryHero)
            Text(loc.localized("settings.libraryHero.showDescription"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
    }

    private var quickAccessContent: some View {
        Group {
            Toggle(loc.localized("settings.sidebarQuickAccess.show"), isOn: $prefs.showSidebarQuickAccess)
            Text(verbatim: loc.localized("settings.sidebarQuickAccess.showDescription"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
    }

    private var boxArtContent: some View {
        Group {
            Toggle(loc.localized("boxArt.pivotingEnabled"), isOn: $boxArtPivotingEnabled)
            Toggle(loc.localized("settings.hltb.enabled"), isOn: $hltbEnabled)
            Text(loc.localized("settings.hltb.enabledDescription"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            Text(loc.localized("boxArt.pivotingDescription"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
    }

    private var categoriesContent: some View {
        Group {
            Toggle(loc.localized("settings.categories.askToAddAfterCreate"), isOn: $categoryAskToAddAfterCreate)
            Text(loc.localized("settings.categories.askToAddAfterCreateDescription"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
    }

    private var applicationContent: some View {
        Group {
            LabeledContent(loc.localized("settings.version")) {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            }
            LabeledContent(loc.localized("settings.build")) {
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            }

            Divider()

            Toggle(loc.localized("settings.autoCheckUpdates"), isOn: $autoCheckUpdates)
            Text(loc.localized("settings.autoCheckUpdatesDescription"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            SettingsRow(loc.localized("settings.systemNotifications")) {
                HStack(spacing: AppSpacing.sm) {
                    if NotificationService.shared.isAuthorized {
                        SettingsActionButton(loc.localized("settings.notificationsTest")) {
                            NotificationService.shared.sendNotification(
                                title: loc.localized("settings.notificationsTestTitle"),
                                body: loc.localized("settings.notificationsTestBody")
                            )
                        }
                    }
                    SettingsActionButton(NotificationService.shared.isAuthorized ? loc.localized("settings.enabled") : loc.localized("settings.enable")) {
                        Task {
                            let granted = await NotificationService.shared.requestAuthorization()
                            if granted {
                                NotificationService.shared.sendNotification(
                                    title: loc.localized("settings.notificationsTestTitle"),
                                    body: loc.localized("settings.notificationsTestBody")
                                )
                            }
                        }
                    }
                    .disabled(NotificationService.shared.isAuthorized)
                }
            }
        }
    }

    private var openCriticContent: some View {
        Group {
            SecureField(loc.localized("settings.openCritic.apiKey"), text: $openCriticAPIKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xl) {
                Text(loc.localized("settings.openCritic.apiKeyDescription"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if openCritic.isTestingConnection {
                    ProgressView()
                        .controlSize(.small)
                }
                SettingsActionButton(openCritic.isTestingConnection
                                   ? loc.localized("settings.openCritic.testing")
                                   : loc.localized("settings.openCritic.testConnection")) {
                    Task {
                        await OpenCriticService.shared.testAPIConnection()
                    }
                }
                .disabled(openCritic.isTestingConnection)
            }
            if let msg = openCritic.connectionTestMessage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: openCritic.connectionTestSuccess == true
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(openCritic.connectionTestSuccess == true ? .green : .red)
                    Text(msg)
                        .font(.caption2)
                }
                .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
            if let attributed = try? AttributedString(
                markdown: loc.localized("settings.openCritic.apiKeyWarning"),
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            } else {
                Text(loc.localized("settings.openCritic.apiKeyWarning"))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
        }
    }

    // MARK: - Empty State

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

    // MARK: - Computed

    private var previewAccent: Color {
        if pending.theme == .custom { return pending.customColor }
        return pending.theme.accent
    }

    private var previewAccentDimmed: Color {
        if pending.theme == .custom { return AccentColorTheme.dimmedColor(from: pending.customColor) }
        return pending.theme.accentDimmed
    }

    private var previewAccentDark: Color {
        if pending.theme == .custom { return AccentColorTheme.darkColor(from: pending.customColor) }
        return pending.theme.accentDark
    }

    private var previewAccentSecondary: Color {
        if pending.theme == .custom { return pending.customColor }
        return pending.theme.secondaryAccent
    }

    private var themeHasChanged: Bool {
        let themeChanged = pending.theme != themeManager.currentTheme
        let customColorChanged = pending.theme == .custom && pending.customColor != themeManager.customAccentColor
        let toolbarChanged = pending.toolbarAccent != themeManager.toolbarAccentEnabled
        let tintedSurfacesChanged = pending.tintedSurfaces != themeManager.tintedSurfacesEnabled
        let appearanceChanged = pending.appearanceMode != themeManager.appearanceMode
        return themeChanged || customColorChanged || toolbarChanged || tintedSurfacesChanged || appearanceChanged
    }

    private var hasMatchingSections: Bool {
        matchesSearch("Language Region systems language emulation core country localization") ||
        matchesSearch("Theme accent color appearance mode light dark gaming tinted surfaces toolbar") ||
        matchesSearch("library hero header collection banner show hide") ||
        matchesSearch("sidebar quick access tiles all games favorites recent show hide collapse") ||
        matchesSearch("boxArt pivoting 3D tilt cursor") ||
        matchesSearch("categories category add game prompt ask create") ||
        matchesSearch("Application version build notifications updates")
    }

    private func languageDisplayName(for lang: String) -> String {
        switch lang.lowercased() {
        case "en": return "English"
        case "es": return "Español"
        case "pt": return "Português"
        case "ja": return "日本語"
        default: return lang.uppercased()
        }
    }

    private func languageFlag(for lang: String) -> String {
        switch lang.lowercased() {
        case "en": return "🇺🇸"
        case "es": return "🇦🇷"
        case "pt": return "🇧🇷"
        case "ja": return "🇯🇵"
        default: return "🌐"
        }
    }

    // MARK: - Theme Circle Button

    private func themeGridButton(_ theme: AccentColorTheme) -> some View {
        ThemeIconButton(
            iconName: theme.iconAssetName,
            label: theme.displayName,
            isSelected: pending.theme == theme,
            colorScheme: colorScheme
        ) {
            pending.theme = theme
        }
    }
}

// MARK: - Theme Icon Button

private struct ThemeIconButton: View {
    let iconName: String
    let label: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 45, height: 45)
                    .scaleEffect(isHovered ? 1.5 : 1.0)
                    .animation(AppMotion.micro, value: isHovered)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .offset(x: 16, y: -16)
                            .opacity(isSelected ? 1 : 0)
                    )

                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected || isHovered ? AppColors.textPrimary(colorScheme) : AppColors.textSecondary(colorScheme))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Custom Theme Button

private struct CustomThemeButton: View {
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image("ThemeCustom")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 45, height: 45)
                    .scaleEffect(isHovered ? 1.5 : 1.0)
                    .animation(AppMotion.micro, value: isHovered)

                Text(LocalizationManager.shared.localized("settings.theme.custom"))
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected || isHovered ? AppColors.textPrimary(colorScheme) : AppColors.textSecondary(colorScheme))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Theme Preview Card

private struct ThemePreviewCard: View {
    let accent: Color
    let accentDimmed: Color
    let accentDark: Color
    let accentSecondary: Color
    let mode: AppearanceMode
    let tinted: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkPreview: Bool {
        switch mode {
        case .dark: return true
        case .light: return false
        case .automatic: return NSApp.effectiveAppearance.name == .darkAqua
        }
    }

    private var previewBackgroundColor: Color {
        let base: Color = isDarkPreview
            ? Color(red: 0.11, green: 0.11, blue: 0.12)
            : Color(red: 0.96, green: 0.96, blue: 0.96)
        guard tinted else { return base }
        let strength: CGFloat = isDarkPreview ? 0.04 : 0.08
        guard let baseNS = NSColor(base).usingColorSpace(.sRGB),
              let accentNS = NSColor(accent).usingColorSpace(.sRGB),
              let blended = baseNS.blended(withFraction: strength, of: accentNS) else {
            return base
        }
        return Color(nsColor: blended)
    }

    private var previewCardColor: Color {
        isDarkPreview
            ? Color(red: 0.16, green: 0.16, blue: 0.17)
            : Color.white
    }

    private var previewTextColor: Color {
        isDarkPreview ? .white : .black
    }

    private var previewSecondaryTextColor: Color {
        isDarkPreview ? .white.opacity(0.6) : .black.opacity(0.5)
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: mode.systemImageName)
                    .font(.caption)
                    .foregroundStyle(accent)
                    .frame(width: 16)

                RoundedRectangle(cornerRadius: AppRadius.sm)
                    .fill(accent)
                    .frame(width: 40, height: 24)

                RoundedRectangle(cornerRadius: AppRadius.sm)
                    .fill(accentSecondary)
                    .frame(width: 40, height: 24)
            }

            HStack(spacing: AppSpacing.lg) {
                VStack(spacing: AppSpacing.sm) {
                    RoundedRectangle(cornerRadius: AppRadius.sm)
                        .fill(accentSecondary)
                        .overlay(Text("Primary").foregroundStyle(AppColors.textOnAccent(for: accentSecondary, colorScheme: colorScheme)).font(.caption.weight(.medium)))
                        .frame(height: 28)

                    RoundedRectangle(cornerRadius: AppRadius.sm)
                        .fill(accent.opacity(0.15))
                        .overlay(Text("Outline").foregroundStyle(accent).font(.caption.weight(.medium)))
                        .frame(height: 28)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Primary Text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(previewTextColor)
                    Text("Secondary Text")
                        .font(.caption)
                        .foregroundStyle(previewSecondaryTextColor)
                    Toggle("", isOn: .constant(true))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(accentSecondary)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(previewCardColor)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .padding(4)
        .background(previewBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

// MARK: - Stat Pill

/// A pill-shaped stat chip echoing the number pills on the design inspiration
/// page: an icon, a bold value, and a small uppercase label.
struct SettingsStatPill: View {
    let item: Item
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    struct Item: Identifiable {
        let id: String
        let number: String
        let label: String
        let icon: String
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: item.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppColors.brandAccent)

            Text(verbatim: item.number)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary(colorScheme))
                .lineLimit(1)

            Text(verbatim: item.label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(AppColors.textTertiary(colorScheme))
                .lineLimit(1)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(
            Capsule(style: .continuous)
                .fill(AppColors.brandAccent.opacity(colorScheme == .dark ? 0.14 : 0.10))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppColors.brandAccent.opacity(isHovered ? 0.30 : 0.18), lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .fixedSize()
    }
}

// MARK: - Card Hover Effect

/// Subtle lift + border brighten on hover, echoing the interactive cards on
/// the design inspiration page.
struct CardHoverEffect: ViewModifier {
    let colorScheme: ColorScheme
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.005 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xl)
                    .stroke(AppColors.brandAccent.opacity(isHovered ? 0.25 : 0.0), lineWidth: 1)
                    .animation(.easeOut(duration: 0.12), value: isHovered)
            )
            .onHover { isHovered = $0 }
    }
}

extension View {
    func cardHoverEffect(colorScheme: ColorScheme) -> some View {
        modifier(CardHoverEffect(colorScheme: colorScheme))
    }
}
