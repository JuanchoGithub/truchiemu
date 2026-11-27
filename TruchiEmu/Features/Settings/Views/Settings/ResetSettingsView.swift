import SwiftUI

struct ResetSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @State private var contentLoaded = false
    @State private var showResetConfirmation = false
    @State private var resetTarget: ResetTarget?
    @State private var resetMessage: String?

    init(searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    private enum ResetTarget: Identifiable {
        case section(String)
        case all

        var id: String {
            switch self {
            case .section(let name): return name
            case .all: return "all"
            }
        }
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.reset, query: searchText) { return true }
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
                            settingsCard(
                                id: "section-intro",
                                title: loc.localized("settings.reset.intro"),
                                icon: "text.alignleft",
                                keywords: "reset restore settings intro"
                            ) {
                                Text(loc.localized("settings.reset.intro"))
                                    .font(.callout)
                                    .foregroundColor(AppColors.textSecondary(colorScheme))
                            }

                            settingsCard(
                                id: "section-sections",
                                title: loc.localized("settings.reset.sections"),
                                icon: "list.bullet",
                                keywords: "reset sections hotkeys save directories startup tab"
                            ) {
                                row(.section("hotkeys"), title: loc.localized("settings.hotkeysGameplay"), description: loc.localized("settings.reset.hotkeys")) {
                                    SettingsResetter.resetHotkeys()
                                    resetMessage = loc.localized("settings.reset.hotkeysDone")
                                }
                                row(.section("saveDirectories"), title: loc.localized("settings.saves"), description: loc.localized("settings.reset.saveDirectories")) {
                                    SettingsResetter.resetSaveDirectories()
                                    resetMessage = loc.localized("settings.reset.saveDirectoriesDone")
                                }
                                row(.section("startupTab"), title: loc.localized("settings.reset.startupTab"), description: loc.localized("settings.reset.startupTabDescription")) {
                                    SettingsResetter.resetSelectedTab()
                                    resetMessage = loc.localized("settings.reset.startupTabDone")
                                }
                            }

                            settingsCard(
                                id: "section-restoreAll",
                                title: loc.localized("settings.reset.restoreAll"),
                                icon: "exclamationmark.triangle.fill",
                                keywords: "reset restore all settings defaults"
                            ) {
                                SettingsActionButton(
                                    loc.localized("settings.reset.restoreAll"),
                                    systemImage: "exclamationmark.triangle.fill",
                                    role: .destructive
                                ) {
                                    resetTarget = .all
                                    showResetConfirmation = true
                                }
                                Text(loc.localized("settings.reset.restoreAllDescription"))
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary(colorScheme))
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
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .navigationTitle(loc.localized("settings.reset.title"))
        .onAppear {
            contentLoaded = true
        }
        .alert(loc.localized("settings.reset.confirmTitle"), isPresented: $showResetConfirmation) {
            Button(loc.localized("settings.reset.confirmRestore"), role: .destructive) {
                if case .all = resetTarget {
                    SettingsResetter.resetAll()
                    resetMessage = loc.localized("settings.reset.restoreAllDone")
                }
            }
            Button(loc.localized("general.cancel"), role: .cancel) {}
        } message: {
            Text(loc.localized("settings.reset.confirmMessage"))
        }
        .onChange(of: searchText) { _, _ in }
        .overlay(alignment: .bottom) {
            if let message = resetMessage {
                AppToast(message: message, style: .success, duration: 3, onDismiss: { resetMessage = nil })
            }
        }
    }

    private var hasMatchingSections: Bool {
        matchesSearch("reset restore settings intro") ||
        matchesSearch("reset sections hotkeys save directories startup tab") ||
        matchesSearch("reset restore all settings defaults")
    }

    private var noResultsView: some View {
        VStack {
            Text(loc.localized("settings.reset.noMatchingSettings") + " \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppSpacing.xl2)
        }
        .frame(maxWidth: .infinity)
    }

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

    @ViewBuilder
    private func row(_ target: ResetTarget, title: String, description: String, onConfirm: @escaping () -> Void) -> some View {
        ResetRow(title: title, description: description, onConfirm: onConfirm)
    }
}

private struct ResetRow: View {
    let title: String
    let description: String
    let onConfirm: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: onConfirm) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(isHovered ? AppColors.brandAccent : AppColors.textPrimary(colorScheme))
                    Text(description)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                Spacer()
                Image(systemName: "arrow.uturn.backward")
                    .foregroundColor(AppColors.brandAccent)
            }
            .padding(AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(isHovered ? AppColors.accentBackground(colorScheme) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
