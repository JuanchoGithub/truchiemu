import SwiftUI

struct SavesSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var directoryManager = SaveDirectoryManager.shared

    @State private var progressiveSaves = false
    @State private var autoSlotCount = 3
    @State private var autoSaveOnExit = false
    @State private var autoLoadOnStart = false
    @State private var compressSaveStates = true
    @State private var showSaveManager = false
    @State private var contentLoaded = false

    @Binding var searchText: String

    init(searchText: Binding<String> = .constant("")) {
        self._searchText = searchText
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        return keywords.localizedLowercase.fuzzyMatch(searchText) ||
               keywords.localizedLowercase.contains(searchText.lowercased())
    }

    var body: some View {
        Group {
            if contentLoaded {
                Form {
                    // Progressive Saves Section
                    if !isSearching || matchesSearch("Progressive saves auto slot rotation version count") {
                        Section(header: Label(loc.localized("settings.saves.progressiveSaves"), systemImage: "arrow.triangle.2.circlepath")) {
                            Toggle(loc.localized("settings.saves.progressiveSaves"), isOn: $progressiveSaves)
                            Text(loc.localized("settings.saves.progressiveSavesDescription"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))

                            if progressiveSaves {
                                HStack {
                                    Text(loc.localized("settings.saves.autoSlotCount"))
                                    Spacer()
                                    Picker("", selection: $autoSlotCount) {
                                        ForEach(1...5, id: \.self) { count in
                                            Text("\(count)").tag(count)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 200)
                                }
                                Text(loc.localized("settings.saves.slotCountDescription"))
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                            }
                        }
                    }

                    // Save Behavior Section
                    if !isSearching || matchesSearch("Auto save on exit auto-load compress states LZ4") {
                        Section(header: Label(loc.localized("settings.saveStates"), systemImage: "doc.badge.clock")) {
                            Toggle(loc.localized("settings.autoSaveOnExit"), isOn: $autoSaveOnExit)
                            Toggle(loc.localized("settings.autoLoadOnStart"), isOn: $autoLoadOnStart)
                            Toggle(loc.localized("settings.compressSaveStates"), isOn: $compressSaveStates)

                            LabeledContent(loc.localized("settings.saveStatesLocation")) {
                                Text(directoryManager.statesDirectory.path)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    // Save Files Location Section
                    if !isSearching || matchesSearch("Save Files SRAM location") {
                        Section(header: Label(loc.localized("settings.saveFiles"), systemImage: "doc.on.doc")) {
                            LabeledContent(loc.localized("settings.gameSavesLocation")) {
                                Text(directoryManager.savefilesDirectory.path)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    // Save Manager Section
                    if !isSearching || matchesSearch("Save manager browse delete manage review") {
                        Section {
                            Text(loc.localized("settings.saves.saveManagerDescription"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                            Button(action: { showSaveManager = true }) {
                                Label(loc.localized("settings.saves.saveManager"), systemImage: "externaldrive.badge.checkmark")
                            }
                            .sheet(isPresented: $showSaveManager) {
                                SaveManagerView()
                                    .gamepadDismissable { showSaveManager = false }
                            }
                        }
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
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .navigationTitle(loc.localized("settings.saves"))
        .onAppear {
            progressiveSaves = AppSettings.getBool("progressiveSaves_enabled", defaultValue: false)
            autoSlotCount = AppSettings.getInt("progressiveSaves_slotCount", defaultValue: 3)
            autoSaveOnExit = AppSettings.getBool("saveState_autoSaveOnExit", defaultValue: false)
            autoLoadOnStart = AppSettings.getBool("saveState_autoLoadOnStart", defaultValue: false)
            compressSaveStates = AppSettings.getBool("saveState_compress", defaultValue: true)
            DispatchQueue.main.async {
                contentLoaded = true
            }
        }
        .onChange(of: progressiveSaves) { _, newValue in
            AppSettings.setBool("progressiveSaves_enabled", value: newValue)
        }
        .onChange(of: autoSlotCount) { _, newValue in
            AppSettings.setInt("progressiveSaves_slotCount", value: newValue)
        }
        .onChange(of: autoSaveOnExit) { _, newValue in
            AppSettings.setBool("saveState_autoSaveOnExit", value: newValue)
        }
        .onChange(of: autoLoadOnStart) { _, newValue in
            AppSettings.setBool("saveState_autoLoadOnStart", value: newValue)
        }
        .onChange(of: compressSaveStates) { _, newValue in
            AppSettings.setBool("saveState_compress", value: newValue)
        }
    }

    private var hasMatchingSections: Bool {
        matchesSearch("Progressive saves auto slot rotation version count") ||
        matchesSearch("Auto save on exit auto-load compress states LZ4") ||
        matchesSearch("Save Files SRAM location") ||
        matchesSearch("Save manager browse delete manage review")
    }
}
