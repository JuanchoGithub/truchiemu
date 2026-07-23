import SwiftUI
import AppKit

/// Settings page that lets the user rebind which controller button triggers each
/// gamepad navigation action (d-pad nav, A=select, B=cancel, Start+Select=show
/// toolbar, …).
///
/// Bindings are presented via native SwiftUI `Picker` rather than a capture
/// coordinator: simpler and more discoverable, and it sidesteps the gameplay
/// hijack-vs-capture conflict that `ControllerHotkeyCaptureCoordinator` must
/// guard against.
struct GamepadNavSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var configManager = GamepadNavConfigManager.shared
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @State private var settingsGamepadContext: GamepadNavContext?

    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesPage() -> Bool {
        SettingsSearchRuntime.pageMatches(.gamepadNav, query: searchText)
    }

    private func matchesAnyLabel(_ actions: [GamepadNavAction]) -> Bool {
        actions.contains { SettingsIndex.matches(haystack: loc.localized($0.localizationKey), query: searchText) }
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(loc.localized("gamepadNav.section"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary(colorScheme))
                        Toggle(loc.localized("gamepadNav.enableJoystickNavigation"), isOn: $configManager.isEnabled)
                            .font(.caption)
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
                .id("section-enable")

                if !isSearching || matchesPage() || matchesAnyLabel(navigationActions) {
                    Section(header: Label(loc.localized("gamepadNav.section.navigation"), systemImage: "dpad.up.filled")) {
                        actionGrid(navigationActions)
                    }
                    .id("section-navigation")
                }

                if !isSearching || matchesPage() || matchesAnyLabel(zoneActions) {
                    Section(header: Label(loc.localized("gamepadNav.section.zones"), systemImage: "square.stack.3d.up")) {
                        actionGrid(zoneActions)
                    }
                    .id("section-zones")
                }

                if !isSearching || matchesPage() || matchesAnyLabel(scrollActions) {
                    Section(header: Label(loc.localized("gamepadNav.section.scrolling"), systemImage: "arrow.up.arrow.down")) {
                        actionGrid(scrollActions)
                    }
                    .id("section-scrolling")
                }

                if !isSearching || matchesPage() || matchesAnyLabel(coreActions) {
                    Section(header: Label(loc.localized("gamepadNav.section.actions"), systemImage: "hand.tap")) {
                        actionGrid(coreActions)
                    }
                    .id("section-actions")
                }

                if !isSearching || matchesPage() || matchesAnyLabel(libraryActions) {
                    Section(header: Label(loc.localized("gamepadNav.section.library"), systemImage: "book")) {
                        actionGrid(libraryActions)
                    }
                    .id("section-library")
                }

                if !isSearching || matchesPage() || matchesAnyLabel(gameWindowActions) {
                    Section(header: Label(loc.localized("gamepadNav.section.gameWindow"), systemImage: "gamecontroller")) {
                        actionGrid(gameWindowActions)
                    }
                    .id("section-gameWindow")
                }

                if !isSearching || matchesPage() || matchesAnyLabel(tvModeActions) {
                    Section {
                        actionGrid(tvModeActions)
                        Text(loc.localized("gamepadNav.section.tvModeDescription"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        Label(loc.localized("gamepadNav.section.tvMode"), systemImage: "tv")
                    }
                    .id("section-tvMode")
                }

                if !isSearching || matchesPage() {
                    Section(header: Label(loc.localized("gamepadNav.section.reset"), systemImage: "arrow.uturn.backward")) {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(loc.localized("gamepadNav.resetDescription"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                            Button(loc.localized("gamepadNav.resetToDefaults")) {
                                configManager.resetToDefaults()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .id("section-reset")
                }

                if isSearching
                    && !matchesPage()
                    && !matchesAnyLabel(navigationActions)
                    && !matchesAnyLabel(zoneActions)
                    && !matchesAnyLabel(scrollActions)
                    && !matchesAnyLabel(coreActions)
                    && !matchesAnyLabel(libraryActions)
                    && !matchesAnyLabel(gameWindowActions)
                    && !matchesAnyLabel(tvModeActions) {
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
            .onChange(of: focusedSectionID) { _, newID in
                guard let id = newID else { return }
                withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
            }
            .onAppear {
                if settingsGamepadContext == nil {
                    let ctx = GamepadSheetContext(itemCount: 0)
                    settingsGamepadContext = ctx
                    GamepadNavContextStack.shared.push(ctx)
                }
            }
            .onDisappear {
                if let ctx = settingsGamepadContext {
                    GamepadNavContextStack.shared.remove(ctx)
                    settingsGamepadContext = nil
                }
            }
        }
        .navigationTitle(loc.localized("gamepadNav.section"))
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
