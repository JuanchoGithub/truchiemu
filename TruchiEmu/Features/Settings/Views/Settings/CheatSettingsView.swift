import SwiftUI

// MARK: - Cheat Settings View

struct CheatSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var library: ROMLibrary
    @StateObject private var downloadService = CheatDownloadService.shared
    @StateObject private var cheatManager = CheatManagerService.shared
    @ObservedObject var prefs = SystemPreferences.shared
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var downloadResult: String?
    @State private var showClearConfirmation = false
    @State private var showDownloadAllConfirmation = false
    @State private var showSystemDownloadConfirmation = false
    @State private var pendingSystem: SystemInfo?
    @State private var isExporting = false

    @Binding var searchText: String

    let systemID: String?

    let searchKeywords = "cheats codes cheat code action replay"

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.cheats, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private var hasAnyResults: Bool {
        matchesSearch("Cheat Library Summary files storage custom") ||
        matchesSearch("Online Database download network") ||
        matchesSearch("Apply Cheats on Launch Behavior notifications") ||
        matchesSearch("Actions Show in Finder Clear Downloaded Cheats")
    }

    private var systemsWithROMs: [SystemInfo] {
        systemDatabase.systemsForDisplay
            .filter { (library.romCounts[$0.id] ?? 0) > 0 }
            .sorted { $0.name < $1.name }
    }

    init(systemID: String? = nil, searchText: Binding<String> = .constant("")) {
        self.systemID = systemID
        self._searchText = searchText
    }

    var body: some View {
        Form {
            // MARK: - Library Section
            if !isSearching || matchesSearch("Cheat Library Summary files storage custom last updated") {
                Section {
                    StatGroup(
                        AppStatCard(
                            icon: "doc.on.doc.fill",
                            value: "\(downloadService.getDownloadedCheatCount())",
                            label: loc.localized("cheats.files"),
                            accent: AppColors.brandAccent
                        ),
                        AppStatCard(
                            icon: "internaldrive.fill",
                            value: formatByteSize(downloadService.getDownloadedCheatSize()),
                            label: loc.localized("cheats.storage"),
                            accent: AppColors.accentTertiary
                        ),
                        AppStatCard(
                            icon: "wand.and.stars",
                            value: AppSettings.getData("cheats_v2") != nil ? "Active" : "None",
                            label: loc.localized("cheats.custom"),
                            accent: AppColors.warning(colorScheme)
                        )
                    )

                    LabeledContent(loc.localized("cheats.lastUpdated")) {
                        Text((downloadService.lastDownloadDate ?? Date()).formatted(date: .abbreviated, time: .shortened))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }
                } header: {
                    Label { Text(loc.localized("cheats.librarySummary")) } icon: { Image(systemName: "chart.bar.fill") }
                }
            }

            // MARK: - Behavior Section
            if !isSearching || matchesSearch("apply on launch notifications behavior") {
                Section {
                    Toggle(isOn: $prefs.applyCheatsOnLaunch) {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(loc.localized("cheats.applyOnLaunch"))
                            Text(loc.localized("cheats.applyOnLaunchDescription"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                        }
                    }
                    .onChange(of: prefs.applyCheatsOnLaunch) { _, _ in
                        AppSettings.setBool("applyCheatsOnLaunch", value: prefs.applyCheatsOnLaunch)
                    }

                    Toggle(isOn: $prefs.showCheatNotifications) {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(loc.localized("cheats.notifications"))
                            Text(loc.localized("cheats.notificationsDescription"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                        }
                    }
                    .onChange(of: prefs.showCheatNotifications) { _, _ in
                        AppSettings.setBool("showCheatNotifications", value: prefs.showCheatNotifications)
                    }
                } header: {
                    Label(loc.localized("cheats.behavior"), systemImage: "gearshape")
                } footer: {
                    Text(loc.localized("cheats.onlineDatabaseDescription"))
                }
            }

            // MARK: - Download Section
            if !isSearching || matchesSearch("Online Database download network update") {
                Section {
                    if downloadService.isDownloading {
                        downloadProgressView
                    } else {
                        downloadActionButtons
                    }
                } header: {
                    Label(loc.localized("cheats.onlineDatabase"), systemImage: "network")
                }
            }

            // MARK: - Actions Section
            if !isSearching || matchesSearch("Actions Show in Finder Clear Downloaded Cheats") {
                Section(header: Label(loc.localized("cheats.actions"), systemImage: "hammer")) {
                    Button(action: openCheatDirectory) {
                        Label { Text(loc.localized("cheats.showInFinder")) } icon: { Image(systemName: "folder") }
                    }

                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label { Text(loc.localized("cheats.clearDownloadedCheats")) } icon: { Image(systemName: "trash") }
                            .foregroundStyle(AppColors.error(colorScheme))
                    }
                }
            }

            // MARK: - No Results
            if isSearching && !hasAnyResults {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: AppSpacing.md) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                            Text(loc.localized("cheats.noResults"))
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                            Text(loc.localized("cheats.tryDifferentSearch"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textMuted(colorScheme))
                        }
                        .padding(.vertical, AppSpacing.xl5)
                        Spacer()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .navigationTitle(loc.localized("cheats.title"))
        .confirmationDialog(
            loc.localized("cheats.clearDownloadedCheats"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(loc.localized("cheats.clearAll"), role: .destructive) {
                do {
                    try downloadService.clearDownloadedCheats()
                } catch {
                    #if LOG_DEBUG
                    LoggerService.debug(category: "Cheats", "Failed to clear: \(error)")
                    #endif
                }
            }
        } message: {
            Text(loc.localized("cheats.clearConfirmation"))
        }
        .confirmationDialog(loc.localized("cheats.downloadAll"), isPresented: $showDownloadAllConfirmation, titleVisibility: .visible) {
            Button(loc.localized("cheats.downloadAll")) {
                Task {
                    let result = await downloadService.downloadAllCheats()
                    handleResult(result)
                }
            }
            Button(loc.localized("app.cancel"), role: .cancel) { }
        } message: {
            Text(loc.localized("cheats.downloadAllConfirmation"))
        }
        .confirmationDialog(loc.localized("cheats.updateSystem"), isPresented: $showSystemDownloadConfirmation, titleVisibility: .visible) {
            Button(loc.localized("cheats.download")) {
                if let sid = systemID, let sys = systemDatabase.system(forID: sid) {
                    downloadForSystem(sys.id, name: sys.name)
                }
            }
            Button(loc.localized("app.cancel"), role: .cancel) { }
        } message: {
            Text(loc.localized("cheats.updateSystemConfirmation"))
        }
        .overlay(alignment: .bottom) {
            if let result = downloadResult {
                AppToast(message: result, style: .info, duration: 3, onDismiss: { downloadResult = nil })
            }
        }
    }

    // MARK: - Improved Download Progress (No Layout Shifts)

    private var downloadProgressView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text(downloadService.downloadStatus)
                    .font(.caption.monospacedDigit())
                Spacer()
                Text("\(downloadService.currentDownloadedCount)/\(downloadService.totalItemsToDownload)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(AppColors.textSecondary(colorScheme))

            ProgressView(value: Double(downloadService.currentDownloadedCount), total: max(Double(downloadService.totalItemsToDownload), 1))
                .progressViewStyle(.linear)

            HStack {
                if downloadService.currentlyDownloadingCount > 0 {
                    Label("\(downloadService.currentlyDownloadingCount) active threads", systemImage: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(AppColors.brandAccent)
                } else {
                    Label { Text(loc.localized("cheats.statusIdle")) } icon: { Image(systemName: "circle") }
                        .font(.caption2)
                        .opacity(0)
                }
            }
            .frame(height: 16)

            if !downloadService.downloadLog.isEmpty {
                DownloadLogView(logEntries: downloadService.downloadLog)
                    .frame(height: 120)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .cornerRadius(AppRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .stroke(AppColors.divider(colorScheme), lineWidth: 1)
                    )
            }
        }
        .padding(AppSpacing.lg)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(AppRadius.md)
    }
    private var downloadActionButtons: some View {
        HStack(spacing: AppSpacing.lg) {
            Button {
                showDownloadAllConfirmation = true
            } label: {
                Label { Text(loc.localized("cheats.downloadAll")) } icon: { Image(systemName: "arrow.down.circle") }
            }
            .buttonStyle(.borderedProminent)

            if let sid = systemID, let sys = systemDatabase.system(forID: sid) {
                Button("\(loc.localized("cheats.updateSystem")) \(sys.name)") {
                    showSystemDownloadConfirmation = true
                }
            } else {
                if let sys = pendingSystem {
                    Button("Download \(sys.name)") {
                        downloadForSystem(sys.id, name: sys.name)
                        pendingSystem = nil
                    }
                    .buttonStyle(.borderedProminent)
                }

                Menu(loc.localized("cheats.updateSpecific")) {
                    ForEach(systemsWithROMs) { sys in
                        Button(sys.name) {
                            pendingSystem = sys
                        }
                    }
                }
            }
        }
    }

    // MARK: - Logic Helpers

    private func downloadForSystem(_ id: String, name: String) {
        Task {
            do {
                let count = try await downloadService.downloadCheatsForSystem(id)
                downloadResult = count > 0 ? "Downloaded \(count) files for \(name)" : "No files found for \(name)"
            } catch {
                downloadResult = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    private func handleResult(_ result: CheatDownloadResult) {
        switch result {
        case .success(_, _, let message): downloadResult = message
        case .failed(let message): downloadResult = message
        case .alreadyDownloading: break
        }
    }

    private func formatByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func openCheatDirectory() {
        let cheatsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TruchiEmu/cheats_downloaded")
        NSWorkspace.shared.selectFile(cheatsDir.path, inFileViewerRootedAtPath: cheatsDir.path)
    }
}

// MARK: - Download Log Components

struct DownloadLogView: View {
    let logEntries: [CheatDownloadLogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(logEntries) { entry in
                        LogEntryRow(entry: entry)
                    }
                }
                .padding(AppSpacing.xs)
                .onChange(of: logEntries.count) { _, _ in
                    if let lastId = logEntries.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: CheatDownloadLogEntry
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.system(size: 10, weight: .bold))

            Text(entry.fileName)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)

            Spacer()

            Text(statusMessage)
                .font(.system(size: 9))
                .foregroundStyle(statusColor)
        }
        .id(entry.id)
    }

    private var statusIcon: String {
        switch entry.status {
        case .inProgress: return "arrow.down.circle"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .inProgress: return AppColors.brandAccent
        case .success: return AppColors.success(colorScheme)
        case .failed: return AppColors.error(colorScheme)
        }
    }

    private var statusMessage: String {
        switch entry.status {
        case .inProgress: return loc.localized("cheats.downloading")
        case .success: return loc.localized("cheats.ok")
        case .failed(let reason): return reason.prefix(20) + "..."
        }
    }
}

#Preview {
    CheatSettingsView()
}
