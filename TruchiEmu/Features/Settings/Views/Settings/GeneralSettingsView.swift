import SwiftUI

struct GeneralSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @State private var autoCheckUpdates: Bool = true
    @State private var notificationsEnabled: Bool = false

    @State private var pendingTheme: AccentColorTheme = .samus
    @State private var pendingAppearanceMode: AppearanceMode = .automatic
    @State private var pendingCustomColor: Color = Color(.sRGB, red: 0.031, green: 0.569, blue: 0.698)
    @State private var pendingToolbarAccent: Bool = true
    @State private var pendingTintedSurfaces: Bool = true
    @State private var showRestartConfirmation = false
    @Binding var hasPendingChanges: Bool
    @Binding var revertRequest: Int
    @Binding var applyRequest: Int
    @Binding var activePendingTheme: AccentColorTheme
    @Binding var activePendingCustomColor: Color
    @Binding var activePendingToolbarAccent: Bool
    @Binding var activePendingTintedSurfaces: Bool
    @Binding var activePendingAppearanceMode: AppearanceMode

    @State private var contentLoaded = false

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil),
         hasPendingChanges: Binding<Bool> = .constant(false),
         revertRequest: Binding<Int> = .constant(0),
         applyRequest: Binding<Int> = .constant(0),
         activePendingTheme: Binding<AccentColorTheme> = .constant(.samus),
         activePendingCustomColor: Binding<Color> = .constant(Color(.sRGB, red: 0.031, green: 0.569, blue: 0.698)),
        activePendingToolbarAccent: Binding<Bool> = .constant(true),
        activePendingTintedSurfaces: Binding<Bool> = .constant(true),
        activePendingAppearanceMode: Binding<AppearanceMode> = .constant(.automatic)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
        self._hasPendingChanges = hasPendingChanges
        self._revertRequest = revertRequest
        self._applyRequest = applyRequest
        self._activePendingTheme = activePendingTheme
        self._activePendingCustomColor = activePendingCustomColor
        self._activePendingToolbarAccent = activePendingToolbarAccent
        self._activePendingTintedSurfaces = activePendingTintedSurfaces
        self._activePendingAppearanceMode = activePendingAppearanceMode
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
                    // ★ Language picker
            if (!isSearching || matchesSearch("Application Language localization")) && sectionVisible("section-language") {
                Section(header: Label(loc.localized("settings.language"), systemImage: "globe")) {
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
                }
                .id("section-language")
            }

            // ★ Theme section
            if (!isSearching || matchesSearch("Theme accent color appearance mode light dark gaming")) && sectionVisible("section-theme") {
                Section(header: Label(loc.localized("settings.theme"), systemImage: "paintpalette")) {

                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text(loc.localized("settings.appearance"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))

                        Picker(loc.localized("settings.appearance"), selection: Binding<AppearanceMode>(
                            get: { pendingAppearanceMode },
                            set: { pendingAppearanceMode = $0 }
                        )) {
                            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                Label(mode.displayName, systemImage: mode.systemImageName).tag(mode)
                            }
                        }
        .pickerStyle(.segmented)
        }

LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 2) {
            CustomThemeButton(isSelected: pendingTheme == .custom) {
                pendingTheme = .custom
            }

            ForEach(AccentColorTheme.allCases.filter { !$0.isCustom }, id: \.self) { theme in
                themeGridButton(theme)
            }
        }

        if pendingTheme == .custom {
            ColorPicker(loc.localized("settings.customColor"), selection: $pendingCustomColor, supportsOpacity: false)
        }

        HStack {
            Toggle(loc.localized("settings.toolbarAccent"), isOn: $pendingToolbarAccent)
            Spacer()
            Toggle(loc.localized("settings.tintedSurfaces"), isOn: $pendingTintedSurfaces)
        }
        HStack(spacing: AppSpacing.xs) {
            Text(loc.localized("settings.toolbarAccentDescription"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            Spacer()
            Text(loc.localized("settings.tintedSurfacesDescription"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
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
                mode: pendingAppearanceMode,
                tinted: pendingTintedSurfaces
            )
        }
        }

        // Apply
        Section {
        Button(loc.localized("settings.theme.applyTheme")) {
                themeManager.applyTheme(pendingTheme, customColor: pendingTheme == .custom ? pendingCustomColor : nil)
                themeManager.setToolbarAccent(pendingToolbarAccent)
                themeManager.applyAppearanceMode(pendingAppearanceMode)
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

                    HStack {
                        Text(loc.localized("settings.systemNotifications"))
                        Spacer()
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
            pendingTheme = themeManager.currentTheme
            pendingAppearanceMode = themeManager.appearanceMode
            pendingCustomColor = themeManager.customAccentColor
        pendingToolbarAccent = themeManager.toolbarAccentEnabled
        pendingTintedSurfaces = themeManager.tintedSurfacesEnabled
        activePendingTheme = pendingTheme
        activePendingAppearanceMode = pendingAppearanceMode
        activePendingCustomColor = pendingCustomColor
        activePendingToolbarAccent = pendingToolbarAccent
        activePendingTintedSurfaces = pendingTintedSurfaces
        hasPendingChanges = false
        DispatchQueue.main.async {
            contentLoaded = true
        }
        }
        .onChange(of: autoCheckUpdates) { _, newValue in
            AppUpdateService.shared.autoCheckEnabled = newValue
        }
        .onChange(of: pendingTheme) { _, _ in
            activePendingTheme = pendingTheme
            hasPendingChanges = themeHasChanged
        }
        .onChange(of: pendingAppearanceMode) { _, _ in
            activePendingAppearanceMode = pendingAppearanceMode
            hasPendingChanges = themeHasChanged
        }
        .onChange(of: pendingCustomColor) { _, _ in
            activePendingCustomColor = pendingCustomColor
            hasPendingChanges = themeHasChanged
        }
        .onChange(of: pendingToolbarAccent) { _, _ in
            activePendingToolbarAccent = pendingToolbarAccent
            hasPendingChanges = themeHasChanged
        }
        .onChange(of: pendingTintedSurfaces) { _, _ in
            activePendingTintedSurfaces = pendingTintedSurfaces
            hasPendingChanges = themeHasChanged
        }
        .onChange(of: revertRequest) { _, _ in
            pendingTheme = themeManager.currentTheme
            pendingAppearanceMode = themeManager.appearanceMode
            pendingCustomColor = themeManager.customAccentColor
            pendingToolbarAccent = themeManager.toolbarAccentEnabled
            pendingTintedSurfaces = themeManager.tintedSurfacesEnabled
            hasPendingChanges = false
        }
        .onChange(of: applyRequest) { _, _ in
            guard themeHasChanged else { return }
            themeManager.applyTheme(pendingTheme, customColor: pendingTheme == .custom ? pendingCustomColor : nil)
            themeManager.setToolbarAccent(pendingToolbarAccent)
            themeManager.setTintedSurfaces(pendingTintedSurfaces)
            themeManager.applyAppearanceMode(pendingAppearanceMode)
            hasPendingChanges = false
            ThemeManager.relaunchApp()
        }
    }

    // MARK: - Theme Circle Button

    private func themeGridButton(_ theme: AccentColorTheme) -> some View {
        ThemeIconButton(
        iconName: theme.iconAssetName,
        label: theme.displayName,
        isSelected: pendingTheme == theme,
        colorScheme: colorScheme
        ) {
            pendingTheme = theme
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
        if pendingTheme == .custom { return pendingCustomColor }
        return pendingTheme.accent
    }

    private var previewAccentDimmed: Color {
        if pendingTheme == .custom { return AccentColorTheme.dimmedColor(from: pendingCustomColor) }
        return pendingTheme.accentDimmed
    }

    private var previewAccentDark: Color {
        if pendingTheme == .custom { return AccentColorTheme.darkColor(from: pendingCustomColor) }
        return pendingTheme.accentDark
    }

    private var previewAccentSecondary: Color {
        if pendingTheme == .custom { return pendingCustomColor }
        return pendingTheme.secondaryAccent
    }

    private var themeHasChanged: Bool {
        let themeChanged = pendingTheme != themeManager.currentTheme
        let customColorChanged = pendingTheme == .custom && pendingCustomColor != themeManager.customAccentColor
        let toolbarChanged = pendingToolbarAccent != themeManager.toolbarAccentEnabled
        let tintedSurfacesChanged = pendingTintedSurfaces != themeManager.tintedSurfacesEnabled
        let appearanceChanged = pendingAppearanceMode != themeManager.appearanceMode
        return themeChanged || customColorChanged || toolbarChanged || tintedSurfacesChanged || appearanceChanged
    }

    private var hasMatchingSections: Bool {
        matchesSearch("Application Language localization") ||
        matchesSearch("Theme accent color appearance mode light dark gaming tinted surfaces toolbar") ||
        matchesSearch("Application version build notifications updates")
    }

    private func languageDisplayName(for lang: String) -> String {
        switch lang.lowercased() {
        case "en": return "English"
        case "es": return "Español"
        case "pt": return "Português"
        default: return lang.uppercased()
        }
    }

    private func languageFlag(for lang: String) -> String {
        switch lang.lowercased() {
        case "en": return "🇺🇸"
        case "es": return "🇦🇷"
        case "pt": return "🇧🇷"
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
