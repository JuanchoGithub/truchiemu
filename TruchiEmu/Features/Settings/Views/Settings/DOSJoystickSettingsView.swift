import SwiftUI
import GameController
import Combine

struct DOSJoystickSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var preset: DOSJoystickPreset = AppSettings.getDOSJoystickPreset()

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    static let searchKeywords: String = "dos joystick gamepad controller gravis dosbox thrustmaster flight stick plugged"

    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    var body: some View {
        Form {
            presetSection
            if isSearching && !hasMatchingSections {
                Section {
                    Text(loc.localized("general.noMatchingSettings") + " \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .navigationTitle(loc.localized("settings.dosJoystick"))
        .onAppear {
            preset = AppSettings.getDOSJoystickPreset()
        }
    }

    // MARK: - Preset Section

    @ViewBuilder
    private var presetSection: some View {
        Section {
            Picker(loc.localized("settings.dosJoystick.preset"), selection: $preset) {
                ForEach(DOSJoystickPreset.allCases) { p in
                    Text(loc.localized(p.localizationKey)).tag(p)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: preset) { _, newValue in
                AppSettings.setDOSJoystickPreset(newValue)
                LoggerService.info(category: "DOSJoystick", "System preset set to \(newValue.rawValue)")
            }
        } header: {
            Label { Text(loc.localized("settings.dosJoystick")) } icon: { Image(systemName: "gamecontroller.fill") }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.localized("settings.dosJoystick.description"))
                Text(loc.localized("settings.dosJoystick.hotkeyHint"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
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
}
