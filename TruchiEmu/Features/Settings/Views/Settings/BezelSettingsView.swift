import SwiftUI
import AppKit

struct BezelSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var apiService = BezelAPIService.shared
    @ObservedObject private var storageManager = BezelStorageManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    
    @State private var downloadResult: String?
    @State private var showClearConfirmation = false
    @State private var selectedSystem: String = "all"
    
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?
    let searchKeywords: String = "bezel frame overlay monitor"

    init(systemID: String? = nil, searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
        if let sid = systemID {
            _selectedSystem = State(initialValue: sid)
        }
    }
    
    private var showStorageSection: Bool {

        if SettingsSearchRuntime.pageMatches(.bezels, query: searchText) { return true }
        return searchText.isEmpty || SettingsIndex.matches(haystack: "storage path folder directory", query: searchText)
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    private var showDownloadsSection: Bool {
        if SettingsSearchRuntime.pageMatches(.bezels, query: searchText) { return true }
        return searchText.isEmpty || SettingsIndex.matches(haystack: "download bezels project update", query: searchText)
    }

    private var showStatisticsSection: Bool {
        if SettingsSearchRuntime.pageMatches(.bezels, query: searchText) { return true }
        return searchText.isEmpty || SettingsIndex.matches(haystack: "statistics files space supported", query: searchText)
    }

    private var showDangerZoneSection: Bool {
        if SettingsSearchRuntime.pageMatches(.bezels, query: searchText) { return true }
        return searchText.isEmpty || SettingsIndex.matches(haystack: "delete remove clear bezels", query: searchText)
    }
    
    private var hasAnyResults: Bool {
        showStorageSection || showDownloadsSection || showStatisticsSection || showDangerZoneSection
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            Form {
                if searchText.isEmpty {
                    if sectionVisible("section-statistics") { statisticsSection }
                    if sectionVisible("section-storage") { storageSection }
                    if sectionVisible("section-downloads") { downloadsSection }
                    if sectionVisible("section-dangerZone") { dangerZoneSection }
                } else {
                    if showStatisticsSection && sectionVisible("section-statistics") {
                        statisticsSection
                    }
                    if showStorageSection && sectionVisible("section-storage") {
                        storageSection
                    }
                    if showDownloadsSection && sectionVisible("section-downloads") {
                        downloadsSection
                    }
                    if showDangerZoneSection && sectionVisible("section-dangerZone") {
                        dangerZoneSection
                    }

                    if !hasAnyResults {
                        noResultsView
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .formStyle(.grouped)
            .onChange(of: focusedSectionID) { _, newID in
                guard let id = newID else { return }
                withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
            }
            .onChange(of: scopedSectionID) { _, newScope in
                guard let id = newScope else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
                }
            }
        }
        .frame(minWidth: 500)
        .navigationTitle(loc.localized("bezel.settings"))
        .confirmationDialog(loc.localized("bezel.deleteBezelsTitle"), isPresented: $showClearConfirmation) {
            Button(loc.localized("bezel.deleteAll"), role: .destructive) { 
                do {
                    try storageManager.clearAllBezels()
                } catch {
                    LoggerService.error(category: "BezelSettings", "Error clearing bezels: \(error)")
                }
            }
        } message: {
            Text(loc.localized("bezel.deleteAllWarning"))
        }
    }
    
    private var storageSection: some View {
        Section {
            LabeledContent(loc.localized("bezel.currentPath")) {
                Text(storageManager.bezelRootDirectory.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(storageManager.bezelRootDirectory.path)
            }
            
            Picker(loc.localized("bezel.storageMode"), selection: Binding(
                get: { storageManager.storageMode },
                set: { newValue in
                    Task { await handleStorageMigration(to: newValue) }
                }
            )) {
                ForEach(BezelStorageMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            Button(action: { storageManager.openInFinder() }) {
                Label { Text(loc.localized("bezel.showInFinder")) } icon: { Image(systemName: "folder") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } header: {
            Label { Text(loc.localized("bezel.storage")) } icon: { Image(systemName: "folder.fill") }
        }
        .id("section-storage")
    }
    
    private var downloadsSection: some View {
        Section {
VStack(alignment: .leading, spacing: AppSpacing.xs) {
    Text(loc.localized("bezel.theBezelProject"))
        .font(.subheadline)
                    .fontWeight(.medium)
                Text(loc.localized("bezel.download1080Info"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
            
            if let lastDate = apiService.progressTracker.lastDownloadDate {
                Text("\(loc.localized("bezel.updated")) \(lastDate.formatted(.dateTime.month().day().year()))")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
            
            HStack {
                Picker(loc.localized("bezel.view"), selection: $selectedSystem) {
                    Text(loc.localized("bezel.allSystems")).tag("all")
                    Divider()
                    ForEach(systemDatabase.systemsForDisplay.sorted(by: { $0.name < $1.name })) { sys in
                        Text(sys.name).tag(sys.id)
                    }
                }
                .labelsHidden()
                .disabled(apiService.progressTracker.isRunning)
                
                Spacer()
                
                Button(action: runDownload) {
                    if apiService.progressTracker.isRunning {
                        ProgressView().controlSize(.small).padding(.horizontal, AppSpacing.xs)
                    } else {
                        Label(downloadButtonLabel, systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiService.progressTracker.isRunning)
            }
            
            if apiService.progressTracker.isRunning {
                downloadProgressBlock
            }
            
            if let result = downloadResult {
                resultBanner(result: result)
            }
        } header: {
            Label { Text(loc.localized("bezel.downloads")) } icon: { Image(systemName: "arrow.down.circle.fill") }
        }
        .id("section-downloads")
    }
    
    private var statisticsSection: some View {
        Section {
            StatGroup(
                AppStatCard(
                    icon: "photo.fill",
                    value: "\(storageManager.downloadedBezelCount())",
                    label: loc.localized("bezel.files"),
                    accent: AppColors.brandAccent
                ),
                AppStatCard(
                    icon: "internaldrive.fill",
                    value: formatByteSize(storageManager.bezelStorageSize()),
                    label: loc.localized("bezel.storageLabel"),
                    accent: AppColors.accentTertiary
                ),
                AppStatCard(
                    icon: "gamecontroller.fill",
                    value: "\(BezelSystemMapping.configurations.count)",
                    label: loc.localized("bezel.supported"),
                    accent: AppColors.warning(colorScheme)
                )
            )
        } header: {
            Label { Text(loc.localized("bezel.statistics")) } icon: { Image(systemName: "chart.bar.fill") }
        }
        .id("section-statistics")
    }

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label { Text(loc.localized("bezel.deleteAllBezels")) } icon: { Image(systemName: "trash.fill") }
            }
            .buttonStyle(.bordered)
            .tint(AppColors.error(colorScheme))
            .controlSize(.small)
        } header: {
            Label { Text(loc.localized("bezel.dangerZone")) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
        }
        .id("section-dangerZone")
    }
    
    private var noResultsView: some View {
        ContentUnavailableView {
            Label { Text(loc.localized("bezel.noResults")) } icon: { Image(systemName: "magnifyingglass") }
        } description: {
            Text("\(loc.localized("bezel.noSettingsMatch")) '\(searchText)'")
        }
        .padding(.vertical, AppSpacing.xl5)
    }
    
    var downloadProgressBlock: some View {
VStack(alignment: .leading, spacing: AppSpacing.sm) {
    ProgressView(value: apiService.progressTracker.progress)
        .progressViewStyle(.linear)
            
            HStack {
                Text(apiService.progressTracker.downloadStatus)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                Spacer()
                Text("\(apiService.progressTracker.currentDownloadedCount)/\(apiService.progressTracker.totalItemsToDownload)")
                    .font(.caption2.monospacedDigit())
                
                Button(loc.localized("bezel.stop")) {
                    apiService.progressTracker.cancelDownload()
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
    }

func statItem(label: String, value: String, icon: String) -> some View {
    HStack(spacing: AppSpacing.md) {
        Image(systemName: icon)
            .font(.title2)
            .foregroundStyle(AppColors.brandAccent)
        .frame(width: 30)

        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
    }
}

    var downloadButtonLabel: String {
        if selectedSystem == "all" { return loc.localized("bezel.downloadAll") }
        return "\(loc.localized("bezel.downloadAll")) \(selectedSystem.capitalized)"
    }
    
    func resultBanner(result: String) -> some View {
        HStack {
            Text(result)
                .font(.caption)
            Spacer()
            Button(action: { downloadResult = nil }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
    .padding(AppSpacing.md)
    .background(AppColors.brandAccent.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }

    func runDownload() {
        Task {
            if selectedSystem == "all" {
                let result = await apiService.downloadAllSystems()
                downloadResult = result.message
            } else {
                let result = await apiService.downloadAllBezels(systemID: selectedSystem)
                downloadResult = result.message
            }
        }
    }
    
    @MainActor
    func handleStorageMigration(to mode: BezelStorageMode) async {
        guard mode != storageManager.storageMode else { return }
        
        let alert = NSAlert()
        alert.messageText = loc.localized("bezel.changeStorageLocation")
        alert.informativeText = loc.localized("bezel.moveExistingPrompt")
        alert.addButton(withTitle: loc.localized("bezel.moveExisting"))
        alert.addButton(withTitle: loc.localized("bezel.changeOnly"))
        alert.addButton(withTitle: loc.localized("bezel.cancel"))
        
        let response = alert.runModal()
        if response == .alertThirdButtonReturn { return }

        if mode == .customFolder {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            if panel.runModal() == .OK, let url = panel.url {
                storageManager.customFolderPath = url
            } else {
                return
            }
        }

        if response == .alertFirstButtonReturn {
        }
        
        storageManager.storageMode = mode
    }
    
    func formatByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}