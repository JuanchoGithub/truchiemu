import SwiftUI
// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @StateObject private var launchboxService = LaunchBoxGamesDBService.shared
    @State private var autoSaveOnExit = false
    @State private var autoLoadOnStart = false
    @State private var compressSaveStates = true
    @State private var showHiddenGamesCategory: Bool = true
    @State private var launchboxEnabled: Bool = true
    @State private var showSyncConfirmation = false
    @State private var lastSyncText: String = "Never"
    
    @Binding var searchText: String
    
    // Observe LocalizationManager so the view updates when language changes
    @ObservedObject private var loc = LocalizationManager.shared
    
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
        Form {
            // ★ Language picker – appears at the top of General settings
            if !isSearching || matchesSearch("Application Language localization") {
                Section(loc.localized("settings.language")) {
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
            }
            
            // Save States Section
            if !isSearching || matchesSearch("Save States auto save auto-load compress") {
                Section(loc.localized("settings.saveStates")) {
                    Toggle(loc.localized("settings.autoSaveOnExit"), isOn: $autoSaveOnExit)
                    Toggle(loc.localized("settings.autoLoadOnStart"), isOn: $autoLoadOnStart)
                    Toggle(loc.localized("settings.compressSaveStates"), isOn: $compressSaveStates)

                    LabeledContent(loc.localized("settings.saveStatesLocation")) {
                        Text(SaveDirectoryManager.shared.statesDirectory.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            // Save Files Section
            if !isSearching || matchesSearch("Save Files SRAM") {
                Section(loc.localized("settings.saveFiles")) {
                    LabeledContent(loc.localized("settings.gameSavesLocation")) {
                        Text(SaveDirectoryManager.shared.savefilesDirectory.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            
            // Hidden Games Section
            if !isSearching || matchesSearch("Hidden Games category sidebar") {
                Section(loc.localized("settings.hiddenGames")) {
                    Toggle(loc.localized("settings.showHiddenGamesCategory"), isOn: $showHiddenGamesCategory)
                    Text("When disabled, hidden games will still exist but the category won't be visible in the sidebar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // LaunchBox GamesDB Section
            if !isSearching || matchesSearch("LaunchBox GamesDB sync metadata description developer publisher genre players ESRB") {
                Section(loc.localized("settings.launchBoxGamesDB")) {
                    Toggle(loc.localized("settings.enableLaunchBox"), isOn: $launchboxEnabled)
                    Text(loc.localized("settings.launchBoxDescription"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    LabeledContent(loc.localized("settings.lastSync")) {
                        if launchboxService.isSyncing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(loc.localized("settings.syncing"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(lastSyncText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if launchboxService.isSyncing {
                        VStack(spacing: 8) {
                            ProgressView(value: launchboxService.syncProgress)
                            Text(launchboxService.syncStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Button(loc.localized("settings.syncAllGamesNow")) {
                        showSyncConfirmation = true
                    }
                    .disabled(launchboxService.isSyncing || !launchboxEnabled)
                    .confirmationDialog(
                        loc.localized("settings.syncAllGamesTitle"),
                        isPresented: $showSyncConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(loc.localized("settings.startSync")) {
                            Task {
                                await launchboxService.batchSyncLibrary(library: library) { _, _, _ in }
                                updateLastSyncText()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(loc.localized("settings.syncAllGamesMessage"))
                    }
                }
            }
            
            // Application Section
            if !isSearching || matchesSearch("Application version build notifications") {
                Section(loc.localized("settings.application")) {
                    LabeledContent(loc.localized("settings.version")) {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    }
                    LabeledContent(loc.localized("settings.build")) {
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    }

                    // Notifications Subsection
                    if !isSearching || matchesSearch("Notifications system") {
                        Section(loc.localized("settings.notifications")) {
                            HStack {
                                Text(loc.localized("settings.systemNotifications"))
                                Spacer()
                                Button(NotificationService.shared.isAuthorized ? loc.localized("settings.enabled") : loc.localized("settings.enable")) {
                                    Task {
                                        await NotificationService.shared.requestAuthorization()
                                    }
                                }
                                .disabled(NotificationService.shared.isAuthorized)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            
            // No results message
            if isSearching && !hasMatchingSections {
                Section {
                    Text("No matching settings found for \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear {
            showHiddenGamesCategory = AppSettings.getBool("showHiddenGamesCategory", defaultValue: true)
            launchboxEnabled = launchboxService.isEnabled
            autoSaveOnExit = AppSettings.getBool("saveState_autoSaveOnExit", defaultValue: false)
            autoLoadOnStart = AppSettings.getBool("saveState_autoLoadOnStart", defaultValue: false)
            compressSaveStates = AppSettings.getBool("saveState_compress", defaultValue: true)
            updateLastSyncText()
        }
        .onChange(of: showHiddenGamesCategory) { _, newValue in
            AppSettings.setBool("showHiddenGamesCategory", value: newValue)
        }
        .onChange(of: launchboxEnabled) { _, newValue in
            launchboxService.setEnabled(newValue)
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
        matchesSearch("Save States auto save auto-load compress") ||
        matchesSearch("Hidden Games category sidebar") ||
        matchesSearch("LaunchBox GamesDB sync metadata description developer publisher genre players ESRB") ||
        matchesSearch("Application version build notifications")
    }

    private func languageDisplayName(for lang: String) -> String {
        switch lang.lowercased() {
        case "en": return "English"
        case "es": return "Español"
        default: return lang.uppercased()
        }
    }

    private func languageFlag(for lang: String) -> String {
        switch lang.lowercased() {
        case "en": return "🇺🇸"
        case "es": return "🇦🇷"
        default: return "🌐"
        }
    }
    
    private func updateLastSyncText() {
        if let date = launchboxService.lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            lastSyncText = formatter.localizedString(for: date, relativeTo: Date())
        } else {
            lastSyncText = "Never"
        }
    }
}
