import SwiftUI

struct CheatBrowserList: View {
    let rom: ROM

    var showCategoryFilter = false
    var showAddButton = false
    var showDownloadButton = false
    var showImportButton = false
    var showEnableDisableAll = false
    var showApplyButton = false
    var showSettingsLink = false
    var maxListHeight: CGFloat? = nil
    var onCountsChanged: ((Int, Int) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var cheatManager = CheatManagerService.shared
    @ObservedObject private var cheatDownloadService = CheatDownloadService.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var cheats: [Cheat] = []
    @State private var searchText = ""
    @State private var selectedCategory: CheatCategory? = nil
    @State private var showAddCheat = false
    @State private var showImportFile = false
    @State private var downloadMessage: String? = nil
    @State private var downloadMessageTone: ManualStatusTone = .info
    @State private var isDownloading = false
    @State private var newCheatName = ""
    @State private var newCheatCode = ""

    init(
        rom: ROM,
        showCategoryFilter: Bool = false,
        showAddButton: Bool = false,
        showDownloadButton: Bool = false,
        showImportButton: Bool = false,
        showEnableDisableAll: Bool = false,
        showApplyButton: Bool = false,
        showSettingsLink: Bool = false,
        maxListHeight: CGFloat? = nil,
        onCountsChanged: ((Int, Int) -> Void)? = nil
    ) {
        self.rom = rom
        self.showCategoryFilter = showCategoryFilter
        self.showAddButton = showAddButton
        self.showDownloadButton = showDownloadButton
        self.showImportButton = showImportButton
        self.showEnableDisableAll = showEnableDisableAll
        self.showApplyButton = showApplyButton
        self.showSettingsLink = showSettingsLink
        self.maxListHeight = maxListHeight
        self.onCountsChanged = onCountsChanged
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message = downloadMessage {
                downloadStatusView(message: message)
            }

            if showCategoryFilter {
                categoryFilterChips
                Divider().overlay(AppColors.divider(colorScheme))
            }

            searchBar

            if showAddButton || showDownloadButton || showImportButton {
                actionButtons
                Divider().overlay(AppColors.divider(colorScheme))
            }

            if cheats.isEmpty {
                emptyState
            } else {
                cheatListSection
            }

            if showEnableDisableAll && !cheats.isEmpty {
                Divider().overlay(AppColors.divider(colorScheme))
                enableDisableAllRow
            }

            if showApplyButton && enabledCount > 0 {
                Divider().overlay(AppColors.divider(colorScheme))
                applyButton
            }

            if showSettingsLink {
                Divider().overlay(AppColors.divider(colorScheme))
                cheatSettingsRow
            }
        }
        .onAppear { loadCheats() }
        .onChange(of: rom.id) { _, _ in loadCheats() }
        .sheet(isPresented: $showAddCheat) { addCheatSheet }
        .fileImporter(isPresented: $showImportFile, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { _ = await cheatManager.importChtFile(url, for: rom); loadCheats() }
                }
            case .failure:
                break
            }
        }
    }

    // MARK: - Subviews

    private func downloadStatusView(message: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            if isDownloading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: downloadMessageTone.iconName).foregroundColor(downloadMessageTone.foregroundColor)
            }
            Text(message).font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
            Spacer()
            Button { downloadMessage = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(AppColors.textMuted(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(AppSpacing.sm)
        .background(AppColors.brandAccent.opacity(0.12))
        .cornerRadius(AppRadius.sm)
    }

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button { selectedCategory = nil } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2").font(.caption2)
                        Text(loc.localized("cheat.all")).font(.subheadline)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(selectedCategory == nil ? AppColors.brandAccent : AppColors.cardBackgroundSubtle(colorScheme))
                    .foregroundColor(selectedCategory == nil ? AppColors.textOnAccent(colorScheme) : .primary)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                ForEach(CheatCategory.allCases, id: \.self) { category in
                    Button { selectedCategory = category } label: {
                        Label(category.displayName, systemImage: category.icon)
                            .font(.subheadline)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(selectedCategory == category ? AppColors.brandAccent : AppColors.cardBackgroundSubtle(colorScheme))
                            .foregroundColor(selectedCategory == category ? AppColors.textOnAccent(colorScheme) : .primary)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            TextField(loc.localized("cheat.searchPlaceholder"), text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(8)
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if showAddButton {
                Button { showAddCheat = true } label: {
                    Label(loc.localized("cheat.addCustomCheat"), systemImage: "plus")
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .help(loc.localized("cheat.addCustomCheatHelp"))
            }

            if showImportButton {
                Button { showImportFile = true } label: {
                    Label(loc.localized("cheat.importFile"), systemImage: "square.and.arrow.down")
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .help(loc.localized("cheat.importFileHelp"))
            }

            if showDownloadButton {
                Button {
                    Task { await downloadCheats() }
                } label: {
                    HStack(spacing: 4) {
                        if isDownloading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text(isDownloading ? loc.localized("cheat.searching") : loc.localized("cheat.download"))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .help(loc.localized("cheat.downloadHelp"))
                .disabled(isDownloading)
            }

            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var addCheatSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.localized("cheat.addCustomCheat")).font(.headline)
                Spacer()
                Button { showAddCheat = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                Section(loc.localized("cheat.details")) {
                    TextField(loc.localized("cheat.descriptionPlaceholder"), text: $newCheatName)
                    TextField(loc.localized("cheat.codePlaceholder"), text: $newCheatCode)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(loc.localized("cheat.cancel")) { showAddCheat = false }
                    .keyboardShortcut(.escape, modifiers: .command)
                Button(loc.localized("cheat.addCheat")) { addCheat() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(newCheatCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars").font(.system(size: 40)).foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            Text(searchText.isEmpty ? loc.localized("cheat.noCheatsAvailable") : loc.localized("cheat.noMatchingCheats"))
                .foregroundColor(AppColors.textSecondary(colorScheme))
            if searchText.isEmpty {
                Text(loc.localized("cheat.importInstructions")).font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var cheatListSection: some View {
        let filtered = filteredCheats
        let sorted = filtered.sorted { $0.enabled && !$1.enabled }

        return Group {
            if filtered.isEmpty {
                Text(loc.localized("cheats.noCheatsMatch").replacingOccurrences(of: "{0}", with: searchText))
                    .font(.subheadline).foregroundColor(AppColors.textMuted(colorScheme)).padding(.vertical, AppSpacing.xxs)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(sorted) { cheat in
                            CheatListRowView(cheat: cheat, isOn: cheat.enabled) {
                                var updated = cheat
                                updated.enabled.toggle()
                                cheatManager.updateCheat(updated, for: rom)
                                loadCheats()
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: maxListHeight)
            }
        }
    }

    private var enableDisableAllRow: some View {
        HStack {
            Button {
                if enabledCount > 0 {
                    cheatManager.disableAllCheats(for: rom)
                } else {
                    cheatManager.enableAllCheats(for: rom)
                }
                loadCheats()
            } label: {
                Label(enabledCount > 0 ? loc.localized("cheats.disableAll") : loc.localized("cheats.enableAll"), systemImage: enabledCount > 0 ? "stop.circle" : "play.circle")
                    .font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            Spacer()
            Text(loc.localized("cheats.enabledOfTotal")
                .replacingOccurrences(of: "{0}", with: "\(enabledCount)")
                .replacingOccurrences(of: "{1}", with: "\(totalCount)"))
                .font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var applyButton: some View {
        Button {
            let cheats = cheatManager.cheats(for: rom).filter { $0.enabled }
            let cheatData = cheats.map { cheat in
                ["index": cheat.index, "code": cheat.code, "enabled": cheat.enabled] as [String: Any]
            }
            XPCBridgeAdapter.shared.applyCheats(cheatData)
        } label: {
            Label(loc.localized("cheat.applyCheats"), systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }

    private var cheatSettingsRow: some View {
        Button { openCheatSettings() } label: {
            HStack {
                Image(systemName: "gearshape").foregroundColor(AppColors.textSecondary(colorScheme))
                Text(loc.localized("cheats.cheatSettings")).font(.subheadline).foregroundColor(AppColors.textSecondary(colorScheme))
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline).foregroundColor(AppColors.textMuted(colorScheme))
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, AppSpacing.xs)
    }

    private var totalCount: Int { cheatManager.totalCount(for: rom) }
    private var enabledCount: Int { cheatManager.enabledCount(for: rom) }

    private var filteredCheats: [Cheat] {
        var result = cheats
        if !searchText.isEmpty {
            let words = searchText.lowercased().split(separator: " ").map(String.init)
            result = result.filter { cheat in
                let text = cheat.displayName.lowercased()
                return words.allSatisfy { text.contains($0) }
            }
        }
        if let category = selectedCategory {
            result = result.filter { categoryMatches($0.description, category: category) }
        }
        return result
    }

    private func loadCheats() {
        cheatManager.loadCheatsForROM(rom)
        cheats = cheatManager.cheats(for: rom)
        onCountsChanged?(totalCount, enabledCount)
    }

    private func addCheat() {
        let trimmedCode = newCheatCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = newCheatName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }
        let format = CheatParser.detectFormat(trimmedCode)
        let cheat = Cheat(
            index: cheatManager.cheats(for: rom).count,
            description: trimmedDesc.isEmpty ? loc.localized("cheat.customCheat") : trimmedDesc,
            code: trimmedCode,
            enabled: true,
            format: format
        )
        cheatManager.addCheat(cheat, for: rom)
        showAddCheat = false
        newCheatName = ""
        newCheatCode = ""
        loadCheats()
    }

    @MainActor
    private func downloadCheats() async {
        guard let systemID = rom.systemID else {
            downloadMessage = loc.localized("cheats.noSystemAssigned")
            downloadMessageTone = .warning
            return
        }

        isDownloading = true
        downloadMessage = loc.localized("cheats.startingDownload")
        downloadMessageTone = .info

        let cheatCountBefore = cheatManager.totalCount(for: rom)
        do {
            let success = try await withTimeout(seconds: 120) {
                try await cheatDownloadService.downloadCheatForROM(rom, systemID: systemID)
            }
            if success {
                loadCheats()
                let cheatsFound = totalCount - cheatCountBefore
                if cheatsFound > 0 {
                    downloadMessage = loc.localized("cheats.downloadedCheatsFound")
                        .replacingOccurrences(of: "{0}", with: "\(cheatsFound)")
                        .replacingOccurrences(of: "{1}", with: cheatsFound == 1 ? "" : "s")
                } else {
                    downloadMessage = loc.localized("cheats.downloadedCheatFor")
                        .replacingOccurrences(of: "{0}", with: rom.displayName)
                }
                downloadMessageTone = .success
            } else {
                downloadMessage = loc.localized("cheats.noCheatFileFound")
                    .replacingOccurrences(of: "{0}", with: rom.displayName)
                downloadMessageTone = .warning
            }
        } catch is TimeoutError {
            downloadMessage = loc.localized("cheats.downloadTimedOut")
            downloadMessageTone = .error
        } catch {
            downloadMessage = loc.localized("cheats.downloadFailed")
                .replacingOccurrences(of: "{0}", with: error.localizedDescription)
            downloadMessageTone = .error
        }
        isDownloading = false
    }

    private func openCheatSettings() {
        AppSettings.set("pending_settings_page", value: SettingsView.Page.cheats.rawValue)
        NotificationCenter.default.post(name: .openAppSettings, object: nil)
    }

    private func categoryMatches(_ description: String, category: CheatCategory) -> Bool {
        let lower = description.lowercased()
        switch category {
        case .gameplay:
            return lower.contains("life") || lower.contains("health") || lower.contains("energy") ||
                   lower.contains("infinite") || lower.contains("invincib") || lower.contains("speed")
        case .items:
            return lower.contains("weapon") || lower.contains("ammo") || lower.contains("gold") ||
                   lower.contains("money") || lower.contains("item") || lower.contains("power")
        case .debug:
            return lower.contains("debug") || lower.contains("level") || lower.contains("stage") ||
                   lower.contains("select") || lower.contains("test")
        case .custom:
            return false
        }
    }
}
