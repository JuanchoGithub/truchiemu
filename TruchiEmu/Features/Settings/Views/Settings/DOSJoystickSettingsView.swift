import SwiftUI
import GameController
import Combine

struct DOSJoystickSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var preset: DOSJoystickPreset = AppSettings.getDOSJoystickPreset()

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @State private var contentLoaded = false

    static let searchKeywords: String = "dos joystick gamepad controller gravis dosbox thrustmaster flight stick plugged"

    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    var body: some View {
        Group {
            if contentLoaded {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            settingsCard(
                                id: "section-dosJoystick",
                                title: loc.localized("settings.dosJoystick"),
                                icon: "gamecontroller.fill",
                                keywords: "dos joystick gamepad controller gravis dosbox thrustmaster flight stick plugged"
                            ) {
                                Picker(loc.localized("settings.dosJoystick.preset"), selection: $preset) {
                                    ForEach(DOSJoystickPreset.allCases) { p in
                                        Text(loc.localized(p.localizationKey)).tag(p)
                                    }
                                }
                                .pickerStyle(.menu)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(loc.localized("settings.dosJoystick.description"))
                                    Text(loc.localized("settings.dosJoystick.hotkeyHint"))
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                                }
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
        .navigationTitle(loc.localized("settings.dosJoystick"))
        .onAppear {
            contentLoaded = true
            preset = AppSettings.getDOSJoystickPreset()
        }
        .onChange(of: preset) { _, newValue in
            AppSettings.setDOSJoystickPreset(newValue)
            LoggerService.info(category: "DOSJoystick", "System preset set to \(newValue.rawValue)")
        }
    }

    // MARK: - Search

    private var isSearching: Bool { !searchText.isEmpty }

    private var hasMatchingSections: Bool {
        matchesSearch("dos joystick gamepad controller gravis dosbox thrustmaster")
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.dosJoystick, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private var noResultsView: some View {
        VStack {
            Text(loc.localized("general.noMatchingSettings") + " \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity)
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

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }
}
