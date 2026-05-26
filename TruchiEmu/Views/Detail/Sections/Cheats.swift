import SwiftUI

extension GameDetailView {
    var filteredCheatsList: [Cheat] {
        var result = cheatsList
        if showEnabledOnlyCheats {
            result = result.filter { $0.enabled }
        }
        guard !cheatSearchText.trimmingCharacters(in: .whitespaces).isEmpty else { return result }
        let searchWords = cheatSearchText.lowercased().split(separator: " ").map { String($0) }
        return result.filter { cheat in
            let cheatText = cheat.displayName.lowercased()
            return searchWords.allSatisfy { word in cheatText.contains(word) }
        }
    }

    var cheatsSection: some View {
        ModernSectionCard(
            title: loc.localized("cheats.title"),
            icon: "wand.and.stars",
            badge: cheatCount > 0 ? "\(enabledCheatCount)/\(cheatCount)" : nil
        ) {
      VStack(spacing: 0) {
        HStack {
          Image(systemName: "gamecontroller.fill").foregroundColor(AppColors.brandAccent).frame(width: 20)
          VStack(alignment: .leading, spacing: 2) {
            Text(loc.localized("cheats.enableCheats"))
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundColor(AppColors.textPrimary(colorScheme))
          }
          Spacer()
          Toggle("", isOn: Binding(
            get: { currentROM.settings.cheatsEnabled ?? false },
            set: { newValue in
              updateSettings { $0.cheatsEnabled = newValue }
            }
          ))
          .toggleStyle(SwitchToggleStyle())
          .labelsHidden()
        }
        .padding(.vertical, AppSpacing.xs)

        Divider().overlay(AppColors.divider(colorScheme))

        if let message = downloadMessage {
          HStack(spacing: AppSpacing.md) {
            if cheatDownloadService.isDownloading {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: downloadMessageTone.iconName).foregroundColor(downloadMessageTone.foregroundColor)
            }
            Text(message).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
            Spacer()
            Button { downloadMessage = nil } label: {
              Image(systemName: "xmark.circle.fill").foregroundColor(AppColors.textMuted(colorScheme))
            }
            .buttonStyle(.plain)
          }
          .padding(AppSpacing.sm).background(AppColors.brandAccent.opacity(0.12)).cornerRadius(AppRadius.sm)
        }

        HStack(spacing: AppSpacing.xs) {
        Button {
            Task {
                downloadMessage = loc.localized("cheats.startingDownload")
                downloadMessageTone = .info
                do {
                    let systemID = currentROM.systemID ?? ""
                    guard !systemID.isEmpty else {
                        downloadMessage = loc.localized("cheats.noSystemAssigned")
                        downloadMessageTone = .warning; return
                    }
                    let cheatCountBefore = cheatManagerService.totalCount(for: currentROM)
                    let success = try await withTimeout(seconds: 120) { try await cheatDownloadService.downloadCheatForROM(currentROM, systemID: systemID) }
                    if success {
                        cheatManagerService.loadCheatsForROM(currentROM)
                        updateCheatCounts()
                        loadCheatsList()
                        let cheatsFound = cheatCount - cheatCountBefore
                        if cheatsFound > 0 { downloadMessage = String(format: loc.localized("cheats.downloadedCheatsFound").replacingOccurrences(of: "{0}", with: "\(cheatsFound)").replacingOccurrences(of: "{1}", with: cheatsFound == 1 ? "" : "s")) }
                        else { downloadMessage = loc.localized("cheats.downloadedCheatFor").replacingOccurrences(of: "{0}", with: currentROM.displayName) }
                        downloadMessageTone = .success
                    } else {
                        downloadMessage = loc.localized("cheats.noCheatFileFound").replacingOccurrences(of: "{0}", with: currentROM.displayName)
                        downloadMessageTone = .warning
                    }
                } catch is TimeoutError {
                    downloadMessage = loc.localized("cheats.downloadTimedOut"); downloadMessageTone = .error
                } catch {
                    downloadMessage = loc.localized("cheats.downloadFailed").replacingOccurrences(of: "{0}", with: error.localizedDescription); downloadMessageTone = .error
                }
            }
        } label: {
            HStack(spacing: AppSpacing.xxs) {
                if cheatDownloadService.isDownloading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.circle") }
                Text(cheatDownloadService.isDownloading ? loc.localized("cheats.downloading") : loc.localized("cheats.download"))
}
        .font(.subheadline)
        .foregroundColor(AppColors.textOnAccent(colorScheme))
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.brandAccent)
        .cornerRadius(AppRadius.sm)
        }
        .buttonStyle(.plain)
        .disabled(cheatDownloadService.isDownloading)

        Button { showImportCheatFile = true } label: {
            HStack(spacing: AppSpacing.xxs) { Image(systemName: "square.and.arrow.down"); Text(loc.localized("cheats.import")) }
                .font(.subheadline)
                .foregroundColor(AppColors.brandAccent)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.brandAccent.opacity(0.15))
                .cornerRadius(AppRadius.sm)
        }
        .buttonStyle(.plain)

      Spacer()
      }
      .padding(.vertical, AppSpacing.xs)

      Divider().overlay(AppColors.divider(colorScheme))

                if !cheatsList.isEmpty {
        HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "magnifyingglass").foregroundColor(AppColors.textMuted(colorScheme)).font(.caption)
                        TextField(loc.localized("cheats.searchCheats"), text: $cheatSearchText)
                            .textFieldStyle(.plain).font(.caption).foregroundColor(AppColors.textPrimary(colorScheme))
                        if !cheatSearchText.isEmpty {
                            Button { cheatSearchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(AppColors.textMuted(colorScheme)).font(.caption)
                            }.buttonStyle(.plain)
                        }
                        Button {
                            showEnabledOnlyCheats.toggle()
                        } label: {
                            Image(systemName: showEnabledOnlyCheats ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(showEnabledOnlyCheats ? .green : AppColors.textMuted(colorScheme))
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
          .padding(AppSpacing.sm).background(AppColors.brandAccent.opacity(0.08)).cornerRadius(AppRadius.sm)
        }

        if cheatsList.isEmpty {
          VStack(spacing: AppSpacing.xs) {
            Image(systemName: "wand.and.stars").font(.system(size: 20)).foregroundColor(AppColors.textMuted(colorScheme))
                        Text(loc.localized("cheats.noCheatsAvailable")).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("cheats.downloadOrImportCheatFile")).font(.caption2).foregroundColor(AppColors.textMuted(colorScheme))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.lg)
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.xs) {
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
                        Text(loc.localized("cheats.noCheatsMatch").replacingOccurrences(of: "{0}", with: cheatSearchText)).font(.caption2).foregroundColor(AppColors.textMuted(colorScheme)).padding(.vertical, AppSpacing.xxs)
                    }
                }

                Divider().overlay(AppColors.divider(colorScheme))

                HStack {
                    Button {
                        if enabledCheatCount > 0 { cheatManagerService.disableAllCheats(for: currentROM) }
                        else { cheatManagerService.enableAllCheats(for: currentROM) }
                        loadCheatsList(); updateCheatCounts()
                    } label: {
                        Label(enabledCheatCount > 0 ? loc.localized("cheats.disableAll") : loc.localized("cheats.enableAll"), systemImage: enabledCheatCount > 0 ? "stop.circle" : "play.circle")
                            .font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                    }.buttonStyle(.plain)
                    Spacer()
      Text(loc.localized("cheats.enabledOfTotal").replacingOccurrences(of: "{0}", with: "\(enabledCheatCount)").replacingOccurrences(of: "{1}", with: "\(cheatCount)")).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
      }
      .padding(.vertical, AppSpacing.xs)

      Divider().overlay(AppColors.divider(colorScheme))

      Button { openCheatSettings() } label: {
        HStack {
          Image(systemName: "gearshape").foregroundColor(AppColors.textSecondary(colorScheme))
          Text(loc.localized("cheats.cheatSettings")).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
          Spacer()
          Image(systemName: "chevron.right").font(.caption).foregroundColor(AppColors.textMuted(colorScheme))
        }
      }.buttonStyle(.plain)
      .padding(.vertical, AppSpacing.xs)
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