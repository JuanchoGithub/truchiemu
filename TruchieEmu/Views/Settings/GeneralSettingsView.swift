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
    
    var body: some View {
        Form {
            Section("Save States") {
                Toggle("Auto-save on game exit", isOn: $autoSaveOnExit)
                Toggle("Auto-load on game start", isOn: $autoLoadOnStart)
                Toggle("Compress save states (LZ4)", isOn: $compressSaveStates)
                
                LabeledContent("Save states location") {
                    Text("~/Library/Application Support/TruchieEmu/saves/states/")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            
            Section("Hidden Games") {
                Toggle("Show \"Hidden Games\" category in sidebar", isOn: $showHiddenGamesCategory)
                Text("When disabled, hidden games will still exist but the category won't be visible in the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("LaunchBox GamesDB") {
                Toggle("Enable LaunchBox GamesDB", isOn: $launchboxEnabled)
                Text("Automatically fetch game metadata — descriptions, developer, publisher, genre, max players, cooperative play, and ESRB ratings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                LabeledContent("Last sync") {
                    if launchboxService.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Syncing...")
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
                
                Button("Sync All Games Now") {
                    showSyncConfirmation = true
                }
                .disabled(launchboxService.isSyncing || !launchboxEnabled)
                .confirmationDialog(
                    "Sync All Games",
                    isPresented: $showSyncConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Start Sync") {
                        Task {
                            await launchboxService.batchSyncLibrary(library: library) { _, _, _ in }
                            updateLastSyncText()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will search the LaunchBox Games Database for all games in your library that are missing metadata. This may take a while depending on your library size.")
                }
            }
            
            Section("Application") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                }
                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
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
