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
    
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?
    
    @ObservedObject private var loc = LocalizationManager.shared
    
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

    var body: some View {
        ScrollViewReader { proxy in
        Form {
            // Libretro Thumbnails
            if (!isSearching || matchesSearch("libretro thumbnail CDN URL source")) && sectionVisible("section-libretroCDN") {
                Section {
                    Toggle(loc.localized("boxArt.useLibretroCDN"), isOn: $useLibretroThumbnails)
                    if useLibretroThumbnails {
                        TextField(loc.localized("boxArt.cdnBaseURL"), text: $thumbnailBaseURLString)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }
                } header: {
                    Label { Text(loc.localized("boxArt.libretroThumbnails")) } icon: { Image(systemName: "photo.on.rectangle.angled") }
                } footer: {
                    Text(loc.localized("boxArt.libretroDescription"))
                }
                .id("section-libretroCDN")
            }

            // LaunchBox GamesDB
            if (!isSearching || matchesSearch("launchbox gamesdb box art download scan third-party fallback")) && sectionVisible("section-launchbox") {
                Section {
                    Toggle(loc.localized("boxArt.enableLaunchBox"), isOn: $useLaunchBox)
                    if useLaunchBox {
                        Toggle(loc.localized("boxArt.autoDownloadBoxArt"), isOn: $launchBoxDownloadAfterScan)
                    }
                } header: {
                    Label { Text(loc.localized("boxArt.launchBoxGamesDB")) } icon: { Image(systemName: "gamecontroller.fill") }
                } footer: {
                    Text(loc.localized("boxArt.launchBoxDescription"))
                }
                .id("section-launchbox")
            }

            // ScreenScraper Account
            if (!isSearching || matchesSearch("screenscraper account credentials box art free account username password")) && sectionVisible("section-screenscraper") {
                Section {
                    TextField(loc.localized("boxArt.username"), text: $username)
                    SecureField(loc.localized("boxArt.password"), text: $password)
                    Button(loc.localized("boxArt.saveCredentials")) {
                        BoxArtService.shared.saveCredentials(
                            BoxArtService.ScreenScraperCredentials(username: username, password: password))
                        saved = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    if saved {
                        Label { Text(loc.localized("boxArt.credentialsSaved")) } icon: { Image(systemName: "checkmark.circle.fill") }
                            .foregroundStyle(AppColors.success(colorScheme))
                            .font(.caption)
                    }
                } header: {
                    Label { Text(loc.localized("boxArt.screenScraperAccount")) } icon: { Image(systemName: "person.badge.key") }
                } footer: {
                    Text(loc.localized("boxArt.screenScraperDescription"))
                }
                .id("section-screenscraper")
            }

            // Matching Section
            if (!isSearching || matchesSearch("priority CRC matching filename fallback HTTP head check box art matching")) && sectionVisible("section-priority") {
                Section {
                    Picker(loc.localized("boxArt.tryFirst"), selection: $thumbnailPriorityRaw) {
                        ForEach(LibretroThumbnailPriority.allCases) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    Toggle(loc.localized("boxArt.matchROMCrc"), isOn: $useCRCMatching)
                    Toggle(loc.localized("boxArt.fallbackFilename"), isOn: $fallbackFilename)
                    Toggle(loc.localized("boxArt.useHttpHead"), isOn: $useHeadCheck)
                } header: {
                    Label { Text(loc.localized("boxArt.matching")) } icon: { Image(systemName: "arrow.triangle.branch") }
                } footer: {
                    Text(loc.localized("boxArt.launchBoxDescription"))
                }
                .id("section-priority")
            }

            // Maintenance Section
            if (!isSearching || matchesSearch("performance indexing manifest refresh repository library URL 404 check")) && sectionVisible("section-performance") {
                Section {
                    let manifestService = LibretroThumbnailManifestService.shared
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        HStack {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text(loc.localized("boxArt.assetIndexing"))
                                    .font(.body)
                                Text(loc.localized("boxArt.assetIndexingDescription"))
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                            }
                            Spacer()
                            Button(action: {
                                Task { await manifestService.refreshAllManifests() }
                            }) {
                                if manifestService.isRefreshing {
                                    HStack(spacing: AppSpacing.sm) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(loc.localized("boxArt.indexing"))
                                    }
                                } else {
                                    Label { Text(loc.localized("boxArt.refreshIndex")) } icon: { Image(systemName: "arrow.clockwise") }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(manifestService.isRefreshing)
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
                } header: {
                    Label { Text(loc.localized("boxArt.performanceIndexing")) } icon: { Image(systemName: "bolt.fill") }
                }
                .id("section-performance")
            }

            // No results message
            if isSearching && !hasMatchingSections {
                Section {
                    Text("\(loc.localized("boxArt.noMatchingSettings")) \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppSpacing.xl2)
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
    .onAppear {
        username = BoxArtService.shared.credentials?.username ?? ""
            useLibretroThumbnails = BoxArtService.shared.useLibretroThumbnails
            thumbnailServerURLStorage = BoxArtService.shared.thumbnailServerURL.absoluteString
            // Use rawValue directly (e.g., "boxart") to match the Picker tags
            thumbnailPriorityRaw = BoxArtService.shared.thumbnailPriority.rawValue
            useCRCMatching = BoxArtService.shared.useCRCMatchingForThumbnails
            fallbackFilename = BoxArtService.shared.fallbackToFilenameForThumbnails
            useHeadCheck = BoxArtService.shared.useHeadBeforeThumbnailDownload
            useLaunchBox = LaunchBoxGamesDBService.shared.isEnabled
            launchBoxDownloadAfterScan = LaunchBoxGamesDBService.shared.downloadAfterScan
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
        .onChange(of: useLaunchBox) { _, newVal in LaunchBoxGamesDBService.shared.isEnabled = newVal; AppSettings.setBool("launchbox_use_for_boxart", value: newVal) }
        .onChange(of: launchBoxDownloadAfterScan) { _, newVal in LaunchBoxGamesDBService.shared.downloadAfterScan = newVal; AppSettings.setBool("launchbox_download_after_scan", value: newVal) }
    }
    
    private var hasMatchingSections: Bool {
        matchesSearch("libretro thumbnail CDN URL source") ||
        matchesSearch("launchbox gamesdb box art download scan third-party fallback") ||
        matchesSearch("screenscraper account credentials box art free account username password") ||
        matchesSearch("priority CRC matching filename fallback HTTP head check box art matching") ||
        matchesSearch("performance indexing manifest refresh repository library URL 404 check")
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }
}
