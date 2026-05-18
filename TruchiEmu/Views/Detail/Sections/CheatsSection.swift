import SwiftUI

struct CheatsSection: View {
    let rom: ROM
    @ObservedObject var library: ROMLibrary
    @StateObject private var cheatManagerService = CheatManagerService.shared
    @StateObject private var cheatDownloadService = CheatDownloadService.shared
    @StateObject private var loc = LocalizationManager.shared
    @State private var cheatCount: Int = 0
    @State private var enabledCheatCount: Int = 0
    @State private var downloadMessage: String? = nil
    @State private var downloadMessageTone: ManualStatusTone = .info
    @State private var cheatsList: [Cheat] = []
    @State private var cheatSearchText: String = ""
    @State private var showCheatManager = false
    @State private var showImportCheatFile = false
    @State private var showEnabledOnly: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var filteredCheatsList: [Cheat] {
        var result = cheatsList
        if showEnabledOnly {
            result = result.filter { $0.enabled }
        }
        guard !cheatSearchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return result
        }
        let searchWords = cheatSearchText.lowercased().split(separator: " ").map { String($0) }
        return result.filter { cheat in
            let cheatText = cheat.displayName.lowercased()
            return searchWords.allSatisfy { word in cheatText.contains(word) }
        }
    }

    var body: some View {
        ModernSectionCard(
            title: loc.localized("cheats.title"),
            icon: "wand.and.stars",
            badge: cheatCount > 0 ? "\(enabledCheatCount)/\(cheatCount)" : nil
        ) {
            VStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { rom.settings.cheatsEnabled ?? false },
                    set: { newValue in
                        var updatedROM = rom
                        updatedROM.settings.cheatsEnabled = newValue
                        library.updateROM(updatedROM)
                    }
                )) {
                    HStack {
                        Image(systemName: "gamecontroller.fill").foregroundColor(AppColors.brandAccent)
                        Text(loc.localized("cheats.enableCheats")).foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                Divider().overlay(AppColors.divider(colorScheme))

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
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Spacer()
                        Button {
                            downloadMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppColors.textMuted(colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(AppColors.cardBackground(colorScheme))
                    .cornerRadius(6)
                }

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
                            Text(cheatDownloadService.isDownloading ? loc.localized("cheats.downloading") : loc.localized("cheats.download"))
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
                            Text(loc.localized("cheats.import"))
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
                            Text(loc.localized("cheats.manage"))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.brandAccent.opacity(0.6))
                        .cornerRadius(5)
                    }
                }

                Divider().overlay(AppColors.divider(colorScheme))

                if !cheatsList.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppColors.textMuted(colorScheme))
                            .font(.caption)
                        TextField(loc.localized("cheats.searchCheats"), text: $cheatSearchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                        if !cheatSearchText.isEmpty {
                            Button {
                                cheatSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(AppColors.textMuted(colorScheme))
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            showEnabledOnly.toggle()
                        } label: {
                            Image(systemName: showEnabledOnly ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(showEnabledOnly ? .green : AppColors.textMuted(colorScheme))
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                    .background(AppColors.cardBackground(colorScheme))
                    .cornerRadius(5)
                }

                if cheatsList.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.textMuted(colorScheme))
                        Text(loc.localized("cheats.noCheatsAvailable"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("cheats.downloadOrImportCheatFile"))
                            .font(.caption2)
                            .foregroundColor(AppColors.textMuted(colorScheme))
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
                }

                if !cheatSearchText.isEmpty && filteredCheatsList.isEmpty {
                    Text(loc.localized("cheats.noCheatsMatch").replacingOccurrences(of: "{0}", with: cheatSearchText))
                        .font(.caption2)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                        .padding(.vertical, 4)
                }

                Divider().overlay(AppColors.divider(colorScheme))

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
                        Label(enabledCheatCount > 0 ? loc.localized("cheats.disableAll") : loc.localized("cheats.enableAll"),
                              systemImage: enabledCheatCount > 0 ? "stop.circle" : "play.circle")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(loc.localized("cheats.enabledOfTotal").replacingOccurrences(of: "{0}", with: "\(enabledCheatCount)").replacingOccurrences(of: "{1}", with: "\(cheatCount)"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }

                Divider().overlay(AppColors.divider(colorScheme))

                Button {
                    openCheatSettings()
                } label: {
                    HStack {
                        Image(systemName: "gearshape")
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("cheats.cheatSettings"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(AppColors.textMuted(colorScheme))
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
        downloadMessage = loc.localized("cheats.startingDownload")
        downloadMessageTone = .info

        do {
            let systemID = rom.systemID ?? ""
            guard !systemID.isEmpty else {
                downloadMessage = loc.localized("cheats.noSystemAssigned")
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
                    downloadMessage = String(format: loc.localized("cheats.downloadedCheatsFound").replacingOccurrences(of: "{0}", with: "\(cheatsFound)").replacingOccurrences(of: "{1}", with: cheatsFound == 1 ? "" : "s"))
                } else {
                    downloadMessage = loc.localized("cheats.downloadedCheatFor").replacingOccurrences(of: "{0}", with: rom.displayName)
                }
                downloadMessageTone = .success
            } else {
                downloadMessage = loc.localized("cheats.noCheatFileFound").replacingOccurrences(of: "{0}", with: rom.displayName)
                downloadMessageTone = .warning
            }
        } catch is TimeoutError {
            downloadMessage = loc.localized("cheats.downloadTimedOut")
            downloadMessageTone = .error
        } catch {
            downloadMessage = loc.localized("cheats.downloadFailed").replacingOccurrences(of: "{0}", with: error.localizedDescription)
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