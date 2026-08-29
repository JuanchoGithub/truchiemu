import SwiftUI

struct GeneralSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @State private var autoCheckUpdates: Bool = true
    @State private var notificationsEnabled: Bool = false
    @State private var boxArtPivotingEnabled: Bool = true
    @State private var hltbEnabled: Bool = true

    @State private var pending = PendingThemeSettings()
    @State private var showRestartConfirmation = false
    @Binding var hasPendingChanges: Bool
    @Binding var revertRequest: Int
    @Binding var applyRequest: Int
    @Binding var activePending: PendingThemeSettings

    @State private var contentLoaded = false

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var prefs = SystemPreferences.shared

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
                ScrollViewReader { proxy in
                    Form {
                    // ★ Language & Region
            if (!isSearching || matchesSearch("Language Region systems language emulation core country localization")) && sectionVisible("section-languageRegion") {
                Section(header: Label(loc.localized("settings.languageRegion"), systemImage: "globe")) {
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
                .id("section-languageRegion")
            }

            // ★ Theme section
            if (!isSearching || matchesSearch("Theme accent color appearance mode light dark gaming")) && sectionVisible("section-theme") {
                Section(header: Label(loc.localized("settings.theme"), systemImage: "paintpalette")) {

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

LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 2) {
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
        }

        // Apply
        Section {
        Button(loc.localized("settings.theme.applyTheme")) {
                themeManager.applyTheme(pending.theme, customColor: pending.theme == .custom ? pending.customColor : nil)
                themeManager.setToolbarAccent(pending.toolbarAccent)
                themeManager.applyAppearanceMode(pending.appearanceMode)
                hasPendingChanges = false
                showRestartConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!themeHasChanged)
            .frame(maxWidth: .infinity)
                    .confirmationDialog(
                        loc.localized("settings.theme.restartRequired"),
                        isPresented: $showRestartConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(loc.localized("settings.theme.restartNow")) {
                            ThemeManager.relaunchApp()
                        }
                        Button(loc.localized("settings.theme.later"), role: .cancel) {}
                    } message: {
                        Text(loc.localized("settings.theme.restartMessage"))
                    }
                }
                .id("section-theme")
            }

            // ★ Box Art Pivoting Section
            if (!isSearching || matchesSearch("boxArt pivoting 3D tilt cursor")) && sectionVisible("section-boxart-pivoting") {
                Section(header: Label(loc.localized("boxArt.pivoting"), systemImage: "cube.transparent")) {
                    Toggle(loc.localized("boxArt.pivotingEnabled"), isOn: $boxArtPivotingEnabled)
                    Toggle(loc.localized("settings.hltb.enabled"), isOn: $hltbEnabled)
                    Text(loc.localized("settings.hltb.enabledDescription"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))

                    Text(loc.localized("boxArt.pivotingDescription"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                .id("section-boxart-pivoting")
            }

            // ★ Application Section
            if (!isSearching || matchesSearch("Application version build notifications updates")) && sectionVisible("section-application") {
                Section(header: Label(loc.localized("settings.application"), systemImage: "app.badge")) {
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
                                Button(loc.localized("settings.notificationsTest")) {
                                    NotificationService.shared.sendNotification(
                                        title: loc.localized("settings.notificationsTestTitle"),
                                        body: loc.localized("settings.notificationsTestBody")
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            Button(NotificationService.shared.isAuthorized ? loc.localized("settings.enabled") : loc.localized("settings.enable")) {
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
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .id("section-application")
            }

            // No results message
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
        } else {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 400)
        }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear {
        NotificationService.shared.refreshAuthorizationStatus()
        autoCheckUpdates = AppUpdateService.shared.autoCheckEnabled
        notificationsEnabled = NotificationService.shared.isAuthorized
        boxArtPivotingEnabled = prefs.boxArtPivotingEnabled()
        hltbEnabled = AppSettings.getBool("hltbEnabled", defaultValue: true)
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
            hasPendingChanges = false
            ThemeManager.relaunchApp()
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
                    .foregroundStyle(isSelected ? AppColors.textPrimary(colorScheme) : AppColors.textTertiary(colorScheme))
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
                    .foregroundStyle(isSelected ? AppColors.textPrimary(colorScheme) : AppColors.textTertiary(colorScheme))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

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
        matchesSearch("boxArt pivoting 3D tilt cursor") ||
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
