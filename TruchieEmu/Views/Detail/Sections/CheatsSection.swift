import SwiftUI

// MARK: - Cheats Section Component

struct CheatsSection: View {
    let rom: ROM
    @StateObject private var cheatManagerService = CheatManagerService.shared
    @StateObject private var cheatDownloadService = CheatDownloadService.shared
    @State private var cheatCount: Int = 0
    @State private var enabledCheatCount: Int = 0
    @State private var downloadMessage: String? = nil
    @State private var downloadMessageTone: ManualStatusTone = .info
    @State private var cheatsList: [Cheat] = []
    @State private var cheatSearchText: String = ""
    @State private var showCheatManager = false
    @State private var showImportCheatFile = false
    @Environment(\.colorScheme) private var colorScheme
    private var t: ThemeColors { ThemeColors.for(colorScheme) }
    
    private var filteredCheatsList: [Cheat] {
        guard !cheatSearchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return cheatsList
        }
        let searchWords = cheatSearchText.lowercased().split(separator: " ").map { String($0) }
        return cheatsList.filter { cheat in
            let cheatText = cheat.displayName.lowercased()
            return searchWords.allSatisfy { word in cheatText.contains(word) }
        }
    }

    var body: some View {
        ModernSectionCard(
            title: "Cheats",
            icon: "wand.and.stars",
            badge: cheatCount > 0 ? "\(enabledCheatCount)/\(cheatCount)" : nil
        ) {
            VStack(spacing: 10) {
                // Download status message
                if let message = downloadMessage {
                    HStack(spacing: 8) {
                        if cheatDownloadService.isDownloading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: downloadMessageTone.iconName)
                                .foregroundColor(downloadMessageTone.foregroundColor)
                        }
                        Text(message)
                            .font(.caption)
                            .foregroundColor(t.textSecondary)
                        Spacer()
                        Button {
                            downloadMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(t.iconMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(t.cardBackground)
                    .cornerRadius(6)
                }

                // Download and manage buttons
                HStack(spacing: 6) {
                    Button {
                        Task { await downloadCheats() }
                    } label: {
                        HStack(spacing: 4) {
                            if cheatDownloadService.isDownloading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text(cheatDownloadService.isDownloading ? "Downloading..." : "Download")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(cheatDownloadService.isDownloading ? Color.green.opacity(0.4) : Color.green.opacity(0.6))
                        .cornerRadius(5)
                    }
                    .disabled(cheatDownloadService.isDownloading)
                    
                    Button {
                        showImportCheatFile = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.6))
                        .cornerRadius(5)
                    }
                    
                    Spacer()
                    
                    Button {
                        showCheatManager = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("Manage")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(5)
                    }
                }

                Divider().overlay(t.divider)

                // Search field, cheat list, and footer
                if !cheatsList.isEmpty {
                    // Search
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(t.iconMuted)
                            .font(.caption)
                        TextField("Search cheats...", text: $cheatSearchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .foregroundColor(t.textPrimary)
                        if !cheatSearchText.isEmpty {
                            Button {
                                cheatSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(t.iconMuted)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(t.cardBackground)
                    .cornerRadius(5)
                }

                // Cheat list or empty state
                if cheatsList.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 20))
                            .foregroundColor(t.iconMuted)
                        Text("No cheats available")
                            .font(.caption)
                            .foregroundColor(t.textSecondary)
                        Text("Download or import a cheat file")
                            .font(.caption2)
                            .foregroundColor(t.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredCheatsList) { cheat in
                                CheatListRowView(
                                    cheat: cheat,
                                    isOn: cheat.enabled,
                                    onToggle: {
                                        var updated = cheat
                                        updated.enabled.toggle()
                                        cheatManagerService.updateCheat(updated, for: rom)
                                        loadCheatsList()
                                        updateCheatCounts()
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    
                    if !cheatSearchText.isEmpty && filteredCheatsList.isEmpty {
                        Text("No cheats match \"\(cheatSearchText)\"")
                            .font(.caption2)
                            .foregroundColor(t.textMuted)
                            .padding(.vertical, 4)
                    }
                    
                    Divider().overlay(t.divider)
                    
                    HStack {
                        Button {
                            if enabledCheatCount > 0 {
                                cheatManagerService.disableAllCheats(for: rom)
                            } else {
                                cheatManagerService.enableAllCheats(for: rom)
                            }
                            loadCheatsList()
                            updateCheatCounts()
                        } label: {
                            Label(enabledCheatCount > 0 ? "Disable All" : "Enable All", 
                                  systemImage: enabledCheatCount > 0 ? "stop.circle" : "play.circle")
                                .font(.caption)
                                .foregroundColor(t.textSecondary)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Text("\(enabledCheatCount) of \(cheatCount) enabled")
                            .font(.caption)
                            .foregroundColor(t.textSecondary)
                    }
                }

                Divider().overlay(t.divider)

                Button {
                    openCheatSettings()
                } label: {
                    HStack {
                        Image(systemName: "gearshape")
                            .foregroundColor(t.textSecondary)
                        Text("Cheat Settings")
                            .font(.caption)
                            .foregroundColor(t.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(t.iconMuted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            updateCheatCounts()
            loadCheatsList()
            if cheatsList.isEmpty {
                cheatManagerService.loadCheatsForROM(rom)
                cheatsList = cheatManagerService.cheats(for: rom)
                updateCheatCounts()
            }
        }
        .onChange(of: rom.id) { _, _ in
            updateCheatCounts()
            loadCheatsList()
            if cheatsList.isEmpty {
                cheatManagerService.loadCheatsForROM(rom)
                cheatsList = cheatManagerService.cheats(for: rom)
                updateCheatCounts()
            }
        }
        .fileImporter(
            isPresented: $showImportCheatFile,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        _ = await cheatManagerService.importChtFile(url, for: rom)
                        updateCheatCounts()
                        loadCheatsList()
                    }
                }
            case .failure(let error):
                LoggerService.debug(category: "Cheats", "File import error: \(error)")
            }
        }
        .sheet(isPresented: $showCheatManager) {
            CheatManagerView(rom: rom)
                .frame(minWidth: 500, minHeight: 600)
        }
    }

    private func downloadCheats() async {
        LoggerService.info(category: "Cheats", "Download button tapped")
        downloadMessage = "Starting download..."
        downloadMessageTone = .info
        
        do {
            let systemID = rom.systemID ?? ""
            guard !systemID.isEmpty else {
                downloadMessage = "No system assigned to this game"
                downloadMessageTone = .warning
                return
            }
            
            let cheatCountBefore = cheatManagerService.totalCount(for: rom)
            let success = try await withTimeout(seconds: 120) {
                try await cheatDownloadService.downloadCheatForROM(rom, systemID: systemID)
            }
            
            if success {
                cheatManagerService.loadCheatsForROM(rom)
                updateCheatCounts()
                loadCheatsList()
                let cheatsFound = cheatCount - cheatCountBefore
                if cheatsFound > 0 {
                    downloadMessage = "Downloaded \(cheatsFound) cheat\(cheatsFound == 1 ? "" : "s")"
                } else {
                    downloadMessage = "Downloaded cheat for \(rom.displayName)"
                }
                downloadMessageTone = .success
            } else {
                downloadMessage = "No cheat file found for \(rom.displayName)"
                downloadMessageTone = .warning
            }
        } catch is TimeoutError {
            downloadMessage = "Download timed out"
            downloadMessageTone = .error
        } catch {
            downloadMessage = "Download failed: \(error.localizedDescription)"
            downloadMessageTone = .error
        }
    }

    private func loadCheatsList() {
        cheatsList = cheatManagerService.cheats(for: rom)
    }

    private func updateCheatCounts() {
        cheatCount = cheatManagerService.totalCount(for: rom)
        enabledCheatCount = cheatManagerService.enabledCount(for: rom)
    }

    private func openCheatSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        if NSApp.mainWindow == nil {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}