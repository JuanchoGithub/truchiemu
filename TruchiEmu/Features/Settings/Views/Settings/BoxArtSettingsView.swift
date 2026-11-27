import SwiftUI
// MARK: - Box Art Settings

struct BoxArtSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var username = ""
    @State private var password = ""
    @State private var saved = false
    @State private var thumbnailBaseURLString = ""

    @State private var useLibretroThumbnails = true
    @State private var thumbnailServerURLStorage = ""
    @State private var thumbnailPriorityRaw = "boxart"
    @State private var useCRCMatching = true
    @State private var fallbackFilename = true
    @State private var useHeadCheck = false
    @State private var useLaunchBox = false
    @State private var launchBoxDownloadAfterScan = true
    @State private var launchBoxLastSync: Date?
    @State private var autoGenerateHoloMasks = false
    
    @EnvironmentObject var library: ROMLibrary
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?
    
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var syncCoordinator = MetadataSyncCoordinator.shared
    @ObservedObject var themeManager = ThemeManager.shared
    
    init(searchText: Binding<String> = .constant(""),
         focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }
    
    private var isSearching: Bool {
        !searchText.isEmpty
    }
    
    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.boxArt, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }
    
    var body: some View {
        Group {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        if !isSearching {
                            statPillsRow
                        }

                        settingsCard(
                            id: "section-libretroCDN",
                            title: loc.localized("boxArt.libretroThumbnails"),
                            icon: "photo.on.rectangle.angled",
                            keywords: "libretro thumbnail CDN URL source"
                        ) {
                            Toggle(loc.localized("boxArt.useLibretroCDN"), isOn: $useLibretroThumbnails)
                            if useLibretroThumbnails {
                                TextField(loc.localized("boxArt.cdnBaseURL"), text: $thumbnailBaseURLString)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)
                            }
                        }

                        settingsCard(
                            id: "section-launchbox",
                            title: loc.localized("launchbox.section"),
                            icon: "books.vertical",
                            keywords: "launchbox gamesdb metadata enrichment box art download scan"
                        ) {
                            launchBoxSectionContent
                        }

                        settingsCard(
                            id: "section-screenscraper",
                            title: loc.localized("boxArt.screenScraperAccount"),
                            icon: "person.badge.key",
                            keywords: "screenscraper account credentials box art free account username password"
                        ) {
                            TextField(loc.localized("boxArt.username"), text: $username)
                            SecureField(loc.localized("boxArt.password"), text: $password)
                            SettingsActionButton(loc.localized("boxArt.saveCredentials")) {
                                BoxArtService.shared.saveCredentials(
                                    BoxArtService.ScreenScraperCredentials(username: username, password: password))
                                saved = true
                            }
                            if saved {
                                Label { Text(loc.localized("boxArt.credentialsSaved")) } icon: { Image(systemName: "checkmark.circle.fill") }
                                    .foregroundStyle(AppColors.success(colorScheme))
                                    .font(.caption)
                            }
                        }

                        settingsCard(
                            id: "section-priority",
                            title: loc.localized("boxArt.matching"),
                            icon: "arrow.triangle.branch",
                            keywords: "priority CRC matching filename fallback HTTP head check box art matching"
                        ) {
                            Picker(loc.localized("boxArt.tryFirst"), selection: $thumbnailPriorityRaw) {
                                ForEach(LibretroThumbnailPriority.allCases) { p in
                                    Text(p.displayName).tag(p.rawValue)
                                }
                            }
                            Toggle(loc.localized("boxArt.matchROMCrc"), isOn: $useCRCMatching)
                            Toggle(loc.localized("boxArt.fallbackFilename"), isOn: $fallbackFilename)
                            Toggle(loc.localized("boxArt.useHttpHead"), isOn: $useHeadCheck)
                        }

                        settingsCard(
                            id: "section-holoMasks",
                            title: loc.localized("boxArt.holoMasks"),
                            icon: "sparkles.rectangle.stack",
                            keywords: "holo mask generation automatic post-scan holographic foil"
                        ) {
                            Toggle(loc.localized("boxArt.autoGenerateHoloMasks"), isOn: $autoGenerateHoloMasks)
                        }

                        settingsCard(
                            id: "section-performance",
                            title: loc.localized("boxArt.performanceIndexing"),
                            icon: "bolt.fill",
                            keywords: "performance indexing manifest refresh repository library URL 404 check"
                        ) {
                            let manifestService = LibretroThumbnailManifestService.shared
                            VStack(alignment: .leading, spacing: AppSpacing.md) {
                                SettingsRow(
                                    loc.localized("boxArt.assetIndexing"),
                                    description: loc.localized("boxArt.assetIndexingDescription")
                                ) {
                                    if manifestService.isRefreshing {
                                        HStack(spacing: AppSpacing.sm) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text(loc.localized("boxArt.indexing"))
                                        }
                                    } else {
                                        SettingsActionButton(loc.localized("boxArt.refreshIndex"), systemImage: "arrow.clockwise") {
                                            Task { await manifestService.refreshAllManifests() }
                                        }
                                        .disabled(manifestService.isRefreshing)
                                    }
                                }

                                if manifestService.isRefreshing {
                                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                        ProgressView(value: manifestService.refreshProgress)
                                            .progressViewStyle(.linear)
                                        Text("\(loc.localized("boxArt.current")) \(manifestService.currentRepoRefreshing)")
                                            .font(.caption2)
                                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                                            .italic()
                                    }
                                    .padding(.top, AppSpacing.xs)
                                }
                            }
                        }

                        if isSearching && !hasMatchingSections {
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
        }
        .onAppear {
            username = BoxArtService.shared.credentials?.username ?? ""
                useLibretroThumbnails = BoxArtService.shared.useLibretroThumbnails
                thumbnailServerURLStorage = BoxArtService.shared.thumbnailServerURL.absoluteString
                thumbnailPriorityRaw = BoxArtService.shared.thumbnailPriority.rawValue
                useCRCMatching = BoxArtService.shared.useCRCMatchingForThumbnails
                fallbackFilename = BoxArtService.shared.fallbackToFilenameForThumbnails
                useHeadCheck = BoxArtService.shared.useHeadBeforeThumbnailDownload
                useLaunchBox = LaunchBoxGamesDBService.shared.isEnabled
                launchBoxDownloadAfterScan = LaunchBoxGamesDBService.shared.downloadAfterScan
                launchBoxLastSync = LaunchBoxGamesDBService.shared.lastSyncDate
                autoGenerateHoloMasks = AppSettings.getBool("auto_generate_holo_masks", defaultValue: false)
                thumbnailBaseURLString = thumbnailServerURLStorage.isEmpty
                    ? LibretroThumbnailResolver.defaultBaseURL.absoluteString
                    : thumbnailServerURLStorage
            }
            .onChange(of: thumbnailBaseURLString) { _, newValue in
                thumbnailServerURLStorage = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: thumbnailServerURLStorage), url.scheme != nil {
                    BoxArtService.shared.thumbnailServerURL = url
                }
                AppSettings.set("thumbnail_server_url", value: thumbnailServerURLStorage)
            }
            .onChange(of: useLibretroThumbnails) { _, newVal in BoxArtService.shared.useLibretroThumbnails = newVal; AppSettings.setBool("thumbnail_use_libretro", value: newVal) }
            .onChange(of: thumbnailPriorityRaw) { _, newValue in
                if let p = LibretroThumbnailPriority(rawValue: newValue) {
                    BoxArtService.shared.thumbnailPriority = p
                    AppSettings.set("thumbnail_priority", value: newValue)
                }
            }
            .onChange(of: useCRCMatching) { _, newVal in BoxArtService.shared.useCRCMatchingForThumbnails = newVal; AppSettings.setBool("thumbnail_use_crc_matching", value: newVal) }
            .onChange(of: fallbackFilename) { _, newVal in BoxArtService.shared.fallbackToFilenameForThumbnails = newVal; AppSettings.setBool("thumbnail_fallback_filename", value: newVal) }
            .onChange(of: useHeadCheck) { _, newVal in BoxArtService.shared.useHeadBeforeThumbnailDownload = newVal; AppSettings.setBool("thumbnail_use_head_check", value: newVal) }
            .onChange(of: useLaunchBox) { _, newVal in
                LaunchBoxGamesDBService.shared.isEnabled = newVal
                AppSettings.setBool("launchbox_use_for_boxart", value: newVal)
                if !newVal { launchBoxLastSync = nil }
            }
            .onChange(of: launchBoxDownloadAfterScan) { _, newVal in LaunchBoxGamesDBService.shared.downloadAfterScan = newVal; AppSettings.setBool("launchbox_download_after_scan", value: newVal) }
            .onChange(of: autoGenerateHoloMasks) { _, newVal in AppSettings.setBool("auto_generate_holo_masks", value: newVal) }
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
        if sectionVisible(id) && matchesSearch(keywords) {
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
    }

    // MARK: - Stat Pills

    private var statPillsRow: some View {
        HStack(spacing: AppSpacing.md) {
            SettingsStatPill(item: .init(
                id: "boxArtSources",
                number: "3",
                label: "sources",
                icon: "photo.stack.fill"
            ))
        }
        .padding(.bottom, AppSpacing.xs)
    }

    // MARK: - Section Content

    @ViewBuilder
    private var launchBoxSectionContent: some View {
        Toggle(loc.localized("launchbox.enable"), isOn: $useLaunchBox)
        if useLaunchBox {
            Toggle(loc.localized("launchbox.autoSync"), isOn: $launchBoxDownloadAfterScan)
            if let syncDate = launchBoxLastSync {
                LabeledContent(loc.localized("launchbox.lastSync")) {
                    Text(syncDate, style: .date)
                        .foregroundStyle(.secondary)
                }
            }
            SettingsActionButton(loc.localized("launchbox.syncNow")) {
                Task {
                    await syncCoordinator.forceSync(library: library)
                    launchBoxLastSync = LaunchBoxGamesDBService.shared.lastSyncDate
                }
            }
            .disabled(syncCoordinator.isActive)
            if syncCoordinator.isActive {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(syncCoordinator.statusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    ProgressView(value: syncCoordinator.progress)
                        .progressViewStyle(.linear)
                }
            }
        }
    }

    // MARK: - Helpers

    private var hasMatchingSections: Bool {
        matchesSearch("libretro thumbnail CDN URL source") ||
        matchesSearch("launchbox gamesdb metadata enrichment box art download scan") ||
        matchesSearch("screenscraper account credentials box art free account username password") ||
        matchesSearch("priority CRC matching filename fallback HTTP head check box art matching") ||
        matchesSearch("performance indexing manifest refresh repository library URL 404 check") ||
        matchesSearch("holo mask generation automatic post-scan holographic foil")
    }

    private var noResultsView: some View {
        VStack {
            Text("\(loc.localized("boxArt.noMatchingSettings")) \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppSpacing.xl2)
        }
        .frame(maxWidth: .infinity)
    }
}
