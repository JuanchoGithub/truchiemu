import SwiftUI
import AppKit

struct TimeMachineSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var masterEnabled: Bool = true
    @State private var rewindEnabled: Bool = true
    @State private var fastForwardEnabled: Bool = true
    @State private var slowMotionEnabled: Bool = true
    @State private var memoryMB: Double = 256
    @State private var contentLoaded = false

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?
    @Binding var selectedPage: SettingsView.Page

    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil),
         selectedPage: Binding<SettingsView.Page>) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
        self._selectedPage = selectedPage
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.timeMachine, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    var body: some View {
        Group {
            if contentLoaded {
                ScrollViewReader { proxy in
                    Form {
                        sectionFeatures
                        if masterEnabled {
                            sectionMemory
                            sectionHotkeys
                            sectionHardcore
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .formStyle(.grouped)
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
        .navigationTitle(loc.localized("settings.timeMachine"))
        .onAppear {
            loadSettings()
            DispatchQueue.main.async { contentLoaded = true }
        }
    }

    private func loadSettings() {
        masterEnabled = AppSettings.getBool("timeMachine_enabled", defaultValue: true)
        rewindEnabled = AppSettings.getBool("timeMachine_rewindEnabled", defaultValue: true)
        fastForwardEnabled = AppSettings.getBool("timeMachine_fastForwardEnabled", defaultValue: true)
        slowMotionEnabled = AppSettings.getBool("timeMachine_slowMotionEnabled", defaultValue: true)
        memoryMB = Double(AppSettings.getInt("timeMachine_memoryMB", defaultValue: 256))
    }

    // MARK: - Master Toggles

    @ViewBuilder
    private var sectionFeatures: some View {
        if (!isSearching || matchesSearch("features enable disable master rewind fast forward slow motion time machine speed")) && sectionVisible("features") {
            Section {
                Toggle(isOn: $masterEnabled) {
                    Text(loc.localized("settings.timeMachine.masterEnabled"))
                }
                .onChange(of: masterEnabled) { _, newValue in
                    AppSettings.set("timeMachine_enabled", value: newValue)
                    if newValue {
                        // Turning master ON auto-enables all three sub-features.
                        rewindEnabled = true
                        fastForwardEnabled = true
                        slowMotionEnabled = true
                        AppSettings.set("timeMachine_rewindEnabled", value: true)
                        AppSettings.set("timeMachine_fastForwardEnabled", value: true)
                        AppSettings.set("timeMachine_slowMotionEnabled", value: true)
                    }
                }

                if masterEnabled {
                    Toggle(isOn: $rewindEnabled) {
                        Text(loc.localized("settings.timeMachine.rewindEnabled"))
                    }
                    .onChange(of: rewindEnabled) { _, newValue in
                        AppSettings.set("timeMachine_rewindEnabled", value: newValue)
                    }

                    Toggle(isOn: $fastForwardEnabled) {
                        Text(loc.localized("settings.timeMachine.fastForwardEnabled"))
                    }
                    .onChange(of: fastForwardEnabled) { _, newValue in
                        AppSettings.set("timeMachine_fastForwardEnabled", value: newValue)
                    }

                    Toggle(isOn: $slowMotionEnabled) {
                        Text(loc.localized("settings.timeMachine.slowMotionEnabled"))
                    }
                    .onChange(of: slowMotionEnabled) { _, newValue in
                        AppSettings.set("timeMachine_slowMotionEnabled", value: newValue)
                    }

                    Text(loc.localized("settings.timeMachine.rewindEnabledDescription"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
            } header: {
                Label(loc.localized("settings.timeMachine.features"), systemImage: "clock.arrow.circlepath")
            }
            .id("section-features")
        }
    }

    @ViewBuilder
    private var sectionMemory: some View {
        if (!isSearching || matchesSearch("memory buffer budget size rewind archive capacity")) && sectionVisible("memory") {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(loc.localized("settings.timeMachine.memoryBudget"))
                        Spacer()
                        Text("\(Int(memoryMB)) MB")
                            .foregroundStyle(AppColors.brandAccent)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }

                    Slider(value: $memoryMB, in: 64...2048, step: 64) {
                        Text("")
                    } onEditingChanged: { editing in
                        if !editing {
                            AppSettings.set("timeMachine_memoryMB", value: Int(memoryMB))
                        }
                    }

                    Text(loc.localized("settings.timeMachine.memoryBudgetDescription"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
            } header: {
                Label(loc.localized("settings.timeMachine.rewindBuffer"), systemImage: "memorychip")
            }
            .id("section-memory")
        }
    }

    @ViewBuilder
    private var sectionHotkeys: some View {
        if (!isSearching || matchesSearch("hotkeys configure bind keyboard controller rewind fast forward slow motion")) && sectionVisible("hotkeys") {
            Section {
                Text(loc.localized("settings.timeMachine.hotkeysDescription"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))

                Button {
                    selectedPage = .hotkeys
                } label: {
                    Label(loc.localized("settings.timeMachine.configureHotkeys"), systemImage: "keyboard")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppColors.brandAccent)
            } header: {
                Label(loc.localized("settings.timeMachine.hotkeys"), systemImage: "keyboard")
            }
            .id("section-hotkeys")
        }
    }

    @ViewBuilder
    private var sectionHardcore: some View {
        if (!isSearching || matchesSearch("hardcore retro achievements restriction block disabled")) && sectionVisible("hardcore") {
            Section {
                Label {
                    Text(loc.localized("settings.timeMachine.hardcoreNote"))
                        .font(.caption)
                        .foregroundStyle(AppColors.warning(colorScheme))
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(AppColors.warning(colorScheme))
                }

                Button {
                    selectedPage = .retroAchievements
                } label: {
                    Label(loc.localized("settings.timeMachine.hardcoreConfigure"), systemImage: "chevron.right")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppColors.brandAccent)
            } header: {
                Label(loc.localized("settings.timeMachine.hardcore"), systemImage: "shield.lefthalf.filled")
            }
            .id("section-hardcore")
        }
    }
}
