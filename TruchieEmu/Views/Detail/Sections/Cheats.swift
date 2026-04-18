import SwiftUI

extension GameDetailView {
    var filteredCheatsList: [Cheat] {
        guard !cheatSearchText.trimmingCharacters(in: .whitespaces).isEmpty else { return cheatsList }
        let searchWords = cheatSearchText.lowercased().split(separator: " ").map { String($0) }
        return cheatsList.filter { cheat in
            let cheatText = cheat.displayName.lowercased()
            return searchWords.allSatisfy { word in cheatText.contains(word) }
        }
    }
    
    var cheatsSection: some View {
        ModernSectionCard(
            title: "Cheats",
            icon: "wand.and.stars",
            badge: cheatCount > 0 ? "\(enabledCheatCount)/\(cheatCount)" : nil
        ) {
            VStack(spacing: 10) {
                if let message = downloadMessage {
                    HStack(spacing: 8) {
                        if cheatDownloadService.isDownloading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: downloadMessageTone.iconName).foregroundColor(downloadMessageTone.foregroundColor)
                        }
                        Text(message).font(.caption).foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Button { downloadMessage = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8).background(cardBgColor).cornerRadius(6)
                }

                HStack(spacing: 6) {
                    Button {
                        Task {
                            downloadMessage = "Starting download..."
                            downloadMessageTone = .info
                            do {
                                let systemID = currentROM.systemID ?? ""
                                guard !systemID.isEmpty else {
                                    downloadMessage = "No system assigned to this game"
                                    downloadMessageTone = .warning; return
                                }
                                let cheatCountBefore = cheatManagerService.totalCount(for: currentROM)
                                let success = try await withTimeout(seconds: 120) { try await cheatDownloadService.downloadCheatForROM(currentROM, systemID: systemID) }
                                if success {
                                    cheatManagerService.loadCheatsForROM(currentROM)
                                    updateCheatCounts()
                                    loadCheatsList()
                                    let cheatsFound = cheatCount - cheatCountBefore
                                    if cheatsFound > 0 { downloadMessage = "Downloaded \(cheatsFound) cheat\(cheatsFound == 1 ? "" : "s")" }
                                    else { downloadMessage = "Downloaded cheat for \(currentROM.displayName)" }
                                    downloadMessageTone = .success
                                } else {
                                    downloadMessage = "No cheat file found for \(currentROM.displayName)"
                                    downloadMessageTone = .warning
                                }
                            } catch is TimeoutError {
                                downloadMessage = "Download timed out"; downloadMessageTone = .error
                            } catch {
                                downloadMessage = "Download failed: \(error.localizedDescription)"; downloadMessageTone = .error
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if cheatDownloadService.isDownloading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.circle") }
                            Text(cheatDownloadService.isDownloading ? "Downloading..." : "Download")
                        }
                        .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(cheatDownloadService.isDownloading ? Color.green.opacity(0.4) : Color.green.opacity(0.6)).cornerRadius(5)
                    }
                    .disabled(cheatDownloadService.isDownloading)
                    
                    Button { showImportCheatFile = true } label: {
                        HStack(spacing: 4) { Image(systemName: "square.and.arrow.down"); Text("Import") }
                        .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 5).background(Color.orange.opacity(0.6)).cornerRadius(5)
                    }
                    
                    Spacer()
                    
                    Button { showCheatManager = true } label: {
                        HStack(spacing: 4) { Image(systemName: "wand.and.stars"); Text("Manage") }
                        .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 5).background(Color.blue.opacity(0.6)).cornerRadius(5)
                    }
                }

                Divider().overlay(dividerColor)

                if !cheatsList.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundColor(.white.opacity(0.4)).font(.caption)
                        TextField("Search cheats...", text: $cheatSearchText)
                            .textFieldStyle(.plain).font(.caption).foregroundColor(.white.opacity(0.85))
                        if !cheatSearchText.isEmpty {
                            Button { cheatSearchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.3)).font(.caption)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(6).background(cardBgColor).cornerRadius(5)
                }

                if cheatsList.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "wand.and.stars").font(.system(size: 20)).foregroundColor(.white.opacity(0.3))
                        Text("No cheats available").font(.caption).foregroundColor(.white.opacity(0.5))
                        Text("Download or import a cheat file").font(.caption2).foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredCheatsList) { cheat in
                                CheatListRowView(cheat: cheat, isOn: cheat.enabled, onToggle: {
                                    var updated = cheat; updated.enabled.toggle()
                                    cheatManagerService.updateCheat(updated, for: currentROM)
                                    loadCheatsList(); updateCheatCounts()
                                })
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    
                    if !cheatSearchText.isEmpty && filteredCheatsList.isEmpty {
                        Text("No cheats match \"\(cheatSearchText)\"").font(.caption2).foregroundColor(.white.opacity(0.4)).padding(.vertical, 4)
                    }
                    
                    Divider().overlay(dividerColor)
                    
                    HStack {
                        Button {
                            if enabledCheatCount > 0 { cheatManagerService.disableAllCheats(for: currentROM) }
                            else { cheatManagerService.enableAllCheats(for: currentROM) }
                            loadCheatsList(); updateCheatCounts()
                        } label: {
                            Label(enabledCheatCount > 0 ? "Disable All" : "Enable All", systemImage: enabledCheatCount > 0 ? "stop.circle" : "play.circle")
                                .font(.caption).foregroundColor(.white.opacity(0.7))
                        }.buttonStyle(.plain)
                        Spacer()
                        Text("\(enabledCheatCount) of \(cheatCount) enabled").font(.caption).foregroundColor(.white.opacity(0.5))
                    }
                }

                Divider().overlay(dividerColor)

                Button { openCheatSettings() } label: {
                    HStack {
                        Image(systemName: "gearshape").foregroundColor(.white.opacity(0.5))
                        Text("Cheat Settings").font(.caption).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.white.opacity(0.3))
                    }
                }.buttonStyle(.plain)
            }
        }
        .onAppear {
            updateCheatCounts(); loadCheatsList()
            if cheatsList.isEmpty {
                cheatManagerService.loadCheatsForROM(currentROM)
                cheatsList = cheatManagerService.cheats(for: currentROM); updateCheatCounts()
            }
        }
        .onChange(of: currentROM.id) { _, _ in
            updateCheatCounts(); loadCheatsList()
            if cheatsList.isEmpty {
                cheatManagerService.loadCheatsForROM(currentROM)
                cheatsList = cheatManagerService.cheats(for: currentROM); updateCheatCounts()
            }
        }
        .fileImporter(isPresented: $showImportCheatFile, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { _ = await cheatManagerService.importChtFile(url, for: currentROM); updateCheatCounts(); loadCheatsList() }
                }
            case .failure(let error): LoggerService.debug(category: "Cheats", "File import error: \(error)")
            }
        }
    }
    
    func loadCheatsList() { cheatsList = cheatManagerService.cheats(for: currentROM) }
    func updateCheatCounts() {
        cheatCount = cheatManagerService.totalCount(for: currentROM)
        enabledCheatCount = cheatManagerService.enabledCount(for: currentROM)
    }
    func openCheatSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        if NSApp.mainWindow == nil { NSApp.activate(ignoringOtherApps: true) }
    }
}