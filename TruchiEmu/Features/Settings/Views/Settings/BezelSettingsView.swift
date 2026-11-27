import SwiftUI
import AppKit

// MARK: - Bezel Settings

struct BezelSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var apiService = BezelAPIService.shared
    @ObservedObject private var storageManager = BezelStorageManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase

    @State private var downloadResult: String?
    @State private var showClearConfirmation = false
    @State private var selectedSystem: String = "all"
    @State private var contentLoaded = false

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
        Group {
            if contentLoaded {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            if searchText.isEmpty {
                                statPillsRow
                            }

                            if sectionVisible("section-statistics") && showStatisticsSection {
                                settingsCard(
                                    id: "section-statistics",
                                    title: loc.localized("bezel.statistics"),
                                    icon: "chart.bar.fill",
                                    keywords: "statistics files space supported"
                                ) {
                                    statisticsSectionContent
                                }
                            }

                            if sectionVisible("section-storage") && showStorageSection {
                                settingsCard(
                                    id: "section-storage",
                                    title: loc.localized("bezel.storage"),
                                    icon: "folder.fill",
                                    keywords: "storage path folder directory"
                                ) {
                                    storageSectionContent
                                }
                            }

                            if sectionVisible("section-downloads") && showDownloadsSection {
                                settingsCard(
                                    id: "section-downloads",
                                    title: loc.localized("bezel.downloads"),
                                    icon: "arrow.down.circle.fill",
                                    keywords: "download bezels project update"
                                ) {
                                    downloadsSectionContent
                                }
                            }

                            if sectionVisible("section-dangerZone") && showDangerZoneSection {
                                settingsCard(
                                    id: "section-dangerZone",
                                    title: loc.localized("bezel.dangerZone"),
                                    icon: "exclamationmark.triangle.fill",
                                    keywords: "delete remove clear bezels"
                                ) {
                                    dangerZoneSectionContent
                                }
                            }

                            if searchText.isEmpty == false && !hasAnyResults {
                                noResultsView
                            }

                            Spacer(minLength: AppSpacing.xl5)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .frame(minWidth: 500)
        .navigationTitle(loc.localized("bezel.settings"))
        .onAppear {
            contentLoaded = true
        }
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

    // MARK: - Card Helper

    @ViewBuilder
    private func settingsCard<Content: View>(
        id: String,
        title: String,
        icon: String,
        keywords: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                Text(title)
                    .font(AppTypography.headingSmall)
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
            }
            content()
        }
        .padding(AppSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl)
                        .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
        )
        .cardHoverEffect(colorScheme: colorScheme)
        .id(id)
    }

    // MARK: - Stat Pills

    private var statPillsRow: some View {
        HStack(spacing: AppSpacing.md) {
            SettingsStatPill(item: .init(
                id: "bezelFiles",
                number: "\(storageManager.downloadedBezelCount())",
                label: loc.localized("bezel.files"),
                icon: "photo.fill"
            ))
            SettingsStatPill(item: .init(
                id: "bezelSize",
                number: formatByteSize(storageManager.bezelStorageSize()),
                label: loc.localized("bezel.storageLabel"),
                icon: "internaldrive.fill"
            ))
            SettingsStatPill(item: .init(
                id: "bezelSupported",
                number: "\(BezelSystemMapping.configurations.count)",
                label: loc.localized("bezel.supported"),
                icon: "gamecontroller.fill"
            ))
        }
        .padding(.bottom, AppSpacing.xs)
    }

    // MARK: - Section Content

    private var storageSectionContent: some View {
        Group {
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

            SettingsActionButton(loc.localized("bezel.showInFinder"), systemImage: "folder", action: { storageManager.openInFinder() })
            .controlSize(.small)
        }
    }

    private var downloadsSectionContent: some View {
        Group {
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

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xl) {
                Picker(loc.localized("bezel.view"), selection: $selectedSystem) {
                    Text(loc.localized("bezel.allSystems")).tag("all")
                    Divider()
                    ForEach(systemDatabase.systemsForDisplay.sorted(by: { $0.name < $1.name })) { sys in
                        Text(sys.name).tag(sys.id)
                    }
                }
                .labelsHidden()
                .disabled(apiService.progressTracker.isRunning)

                Spacer(minLength: AppSpacing.md)

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
        }
    }

    private var statisticsSectionContent: some View {
        Group {
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
        }
    }

    private var dangerZoneSectionContent: some View {
        Group {
            SettingsActionButton(loc.localized("bezel.deleteAllBezels"), systemImage: "trash.fill", role: .destructive) {
                showClearConfirmation = true
            }
        }
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
