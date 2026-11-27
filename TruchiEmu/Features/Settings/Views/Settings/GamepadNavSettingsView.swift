import SwiftUI
import AppKit

/// Reusable gamepad-navigation binding content. Embedded as the "App" tab
/// of the Hotkeys settings page. Renders inside an enclosing `Form` scope
/// provided by the host, so it uses `settingsCard` containers directly
/// (each with its own `id` for the parent `ScrollViewReader` to scroll to).
struct GamepadNavContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var configManager = GamepadNavConfigManager.shared

    @Binding var searchText: String
    let scopedSectionID: String?

    @State private var settingsGamepadContext: GamepadNavContext?

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesPage() -> Bool {
        SettingsSearchRuntime.pageMatches(.hotkeys, query: searchText)
    }

    private func matchesAnyLabel(_ actions: [GamepadNavAction]) -> Bool {
        actions.contains { SettingsIndex.matches(haystack: loc.localized($0.localizationKey), query: searchText) }
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if matchesPage() { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // MARK: - Enable
            settingsCard(
                id: "section-enable",
                title: loc.localized("gamepadNav.section"),
                icon: "gamecontroller.fill",
                keywords: "gamepad nav enable joystick navigation"
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(loc.localized("gamepadNav.section"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                    Toggle(loc.localized("gamepadNav.enableJoystickNavigation"), isOn: $configManager.isEnabled)
                        .font(.caption)
                }
                .padding(.vertical, AppSpacing.xxs)
            }

            // MARK: - Navigation
            if sectionVisible("enable") && (!isSearching || matchesPage() || matchesAnyLabel(navigationActions)) {
                settingsCard(
                    id: "section-navigation",
                    title: loc.localized("gamepadNav.section.navigation"),
                    icon: "dpad.up.filled",
                    keywords: "navigation navigate up down left right dpad"
                ) {
                    actionGrid(navigationActions)
                }
            }

            // MARK: - Zones
            if sectionVisible("zones") && (!isSearching || matchesPage() || matchesAnyLabel(zoneActions)) {
                settingsCard(
                    id: "section-zones",
                    title: loc.localized("gamepadNav.section.zones"),
                    icon: "square.stack.3d.up",
                    keywords: "zones focus prev next sidebar content toolbar"
                ) {
                    actionGrid(zoneActions)
                }
            }

            // MARK: - Scrolling
            if sectionVisible("scrolling") && (!isSearching || matchesPage() || matchesAnyLabel(scrollActions)) {
                settingsCard(
                    id: "section-scrolling",
                    title: loc.localized("gamepadNav.section.scrolling"),
                    icon: "arrow.up.arrow.down",
                    keywords: "scroll up down page up page down"
                ) {
                    actionGrid(scrollActions)
                }
            }

            // MARK: - Actions
            if sectionVisible("actions") && (!isSearching || matchesPage() || matchesAnyLabel(coreActions)) {
                settingsCard(
                    id: "section-actions",
                    title: loc.localized("gamepadNav.section.actions"),
                    icon: "hand.tap",
                    keywords: "select cancel context menu toggle view mode focus search cycle sort"
                ) {
                    actionGrid(coreActions)
                }
            }

            // MARK: - Library
            if sectionVisible("library") && (!isSearching || matchesPage() || matchesAnyLabel(libraryActions)) {
                settingsCard(
                    id: "section-library",
                    title: loc.localized("gamepadNav.section.library"),
                    icon: "book",
                    keywords: "library open settings launch game"
                ) {
                    actionGrid(libraryActions)
                }
            }

            // MARK: - Game Window
            if sectionVisible("gameWindow") && (!isSearching || matchesPage() || matchesAnyLabel(gameWindowActions)) {
                settingsCard(
                    id: "section-gameWindow",
                    title: loc.localized("gamepadNav.section.gameWindow"),
                    icon: "gamecontroller",
                    keywords: "game window show toolbar close window"
                ) {
                    actionGrid(gameWindowActions)
                }
            }

            // MARK: - TV Mode
            if sectionVisible("tvMode") && (!isSearching || matchesPage() || matchesAnyLabel(tvModeActions)) {
                settingsCard(
                    id: "section-tvMode",
                    title: loc.localized("gamepadNav.section.tvMode"),
                    icon: "tv",
                    keywords: "tv mode enter television"
                ) {
                    actionGrid(tvModeActions)
                    Text(loc.localized("gamepadNav.section.tvModeDescription"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // MARK: - Reset
            if sectionVisible("reset") && (!isSearching || matchesPage()) {
                settingsCard(
                    id: "section-reset",
                    title: loc.localized("gamepadNav.section.reset"),
                    icon: "arrow.uturn.backward",
                    keywords: "reset defaults restore"
                ) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(loc.localized("gamepadNav.resetDescription"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                        SettingsActionButton(loc.localized("gamepadNav.resetToDefaults")) {
                            configManager.resetToDefaults()
                        }
                    }
                }
            }

            // No results message
            if isSearching
                && !matchesPage()
                && !matchesAnyLabel(navigationActions)
                && !matchesAnyLabel(zoneActions)
                && !matchesAnyLabel(scrollActions)
                && !matchesAnyLabel(coreActions)
                && !matchesAnyLabel(libraryActions)
                && !matchesAnyLabel(gameWindowActions)
                && !matchesAnyLabel(tvModeActions) {
                noResultsView
            }

            Spacer(minLength: AppSpacing.xl5)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - No results

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

    // MARK: Action groupings

    private var navigationActions: [GamepadNavAction] {
        [.navigateUp, .navigateDown, .navigateLeft, .navigateRight]
    }

    private var zoneActions: [GamepadNavAction] {
        [.focusPrevZone, .focusNextZone, .focusSidebarZone, .focusContentZone, .focusToolbarZone]
    }

    private var scrollActions: [GamepadNavAction] {
        [.scrollUp, .scrollDown, .pageUp, .pageDown]
    }

    private var coreActions: [GamepadNavAction] {
        [.select, .cancel, .contextMenu, .toggleViewMode, .focusSearch, .cycleSortOrder]
    }

    private var libraryActions: [GamepadNavAction] {
        [.openSettings, .launchGame]
    }

    private var gameWindowActions: [GamepadNavAction] {
        [.showGameToolbar, .closeWindow]
    }

    private var tvModeActions: [GamepadNavAction] {
        [.enterTVMode]
    }

    // MARK: Grid rows

    @ViewBuilder
    private func actionGrid(_ actions: [GamepadNavAction]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                actionRow(action: action, isLast: index == actions.count - 1)
            }
        }
    }

    @ViewBuilder
    private func actionRow(action: GamepadNavAction, isLast: Bool) -> some View {
        GridRow {
            Text(loc.localized(action.localizationKey))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 220, alignment: .leading)
                .gridColumnAlignment(.leading)
            Picker(loc.localized("gamepadNav.bindButton"), selection: pickerSelection(for: action)) {
                Text(loc.localized("gamepadNav.unbound")).tag(GamepadNavButton?.none)
                ForEach(GamepadNavButton.availableForMapping, id: \.self) { button in
                    Text(button.displayName).tag(GamepadNavButton?.some(button))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .gridColumnAlignment(.trailing)
            .frame(maxWidth: 200)
        }
        .padding(.vertical, AppSpacing.xxs)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .overlay(AppColors.divider(colorScheme))
            }
        }
    }

    private func pickerSelection(for action: GamepadNavAction) -> Binding<GamepadNavButton?> {
        Binding(
            get: { GamepadNavConfigManager.shared.button(for: action) },
            set: { newValue in
                GamepadNavConfigManager.shared.update(action, binding: GamepadNavBinding(button: newValue))
            }
        )
    }
}
