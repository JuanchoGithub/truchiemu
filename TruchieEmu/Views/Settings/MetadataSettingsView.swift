import SwiftUI

struct MetadataSettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @StateObject private var launchboxService = LaunchBoxGamesDBService.shared
    @State private var isEnabled: Bool = true
    @State private var showSyncConfirmation = false
    @State private var lastSyncText: String = "Never"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // LaunchBox GamesDB Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("LaunchBox GamesDB", systemImage: "globe")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $isEnabled)
                            .labelsHidden()
                            .onChange(of: isEnabled) { newValue in
                                launchboxService.setEnabled(newValue)
                            }
                    }
                    
                    VStack(spacing: 0) {
                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Automatically fetch game metadata from the LaunchBox Games Database")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Text("Includes: descriptions, developer, publisher, genre, max players, cooperative play, and ESRB ratings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        
                        Divider()
                        
                        // Last sync info
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last Sync")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(lastSyncText)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Spacer()
                            
                            if launchboxService.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Syncing...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        
                        Divider()
                        
                        // Sync button
                        Button {
                            showSyncConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                Text("Sync All Games Now")
                                    .font(.body)
                                Spacer()
                                if launchboxService.isSyncing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(launchboxService.isSyncing || !isEnabled)
                        .confirmationDialog(
                            "Sync All Games",
                            isPresented: $showSyncConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Start Sync") {
                                Task {
                                    await launchboxService.batchSyncLibrary(library: library)
                                    updateLastSyncText()
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will search the LaunchBox Games Database for all games in your library that are missing metadata. This may take a while depending on your library size.")
                        }
                        
                        if launchboxService.isSyncing {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(value: launchboxService.syncProgress)
                                    .progressViewStyle(.linear)
                                Text(launchboxService.syncStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        }
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding(.top, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Metadata")
        .onAppear {
            isEnabled = launchboxService.isEnabled
            updateLastSyncText()
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
