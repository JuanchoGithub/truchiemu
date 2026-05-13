import SwiftUI
// MARK: - Box Art Settings
struct BoxArtSettingsView: View {
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
    
    @ObservedObject private var loc = LocalizationManager.shared
    
    init(searchText: Binding<String> = .constant("")) {
        self._searchText = searchText
    }
    
    private var isSearching: Bool {
        !searchText.isEmpty
    }
    
    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        return keywords.localizedLowercase.fuzzyMatch(searchText) || 
               keywords.localizedLowercase.contains(searchText.lowercased())
    }

    var body: some View {
        Form {
            // Libretro Thumbnails Section
            if !isSearching || matchesSearch("libretro thumbnail CDN CRC No-Intro DAT box art named boxarts named titles named snaps fuzzy name") {
                Section {
                    Toggle(loc.localized("boxArt.useLibretroCDN"), isOn: $useLibretroThumbnails)
                    TextField(loc.localized("boxArt.cdnBaseURL"), text: $thumbnailBaseURLString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Picker(loc.localized("boxArt.tryFirst"), selection: $thumbnailPriorityRaw) {
                        ForEach(LibretroThumbnailPriority.allCases) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    Toggle(loc.localized("boxArt.matchROMCrc"), isOn: $useCRCMatching)
                    Toggle(loc.localized("boxArt.fallbackFilename"), isOn: $fallbackFilename)
                    Toggle(loc.localized("boxArt.useHttpHead"), isOn: $useHeadCheck)
                } header: {
                    Label(loc.localized("boxArt.libretroThumbnails"), systemImage: "photo.on.rectangle.angled")
                } footer: {
                    Text(loc.localized("boxArt.libretroDescription"))
                }
            }

            // LaunchBox GamesDB Section
            if !isSearching || matchesSearch("launchbox gamesdb box art download scan third-party fallback") {
                Section {
                    Toggle(loc.localized("boxArt.enableLaunchBox"), isOn: $useLaunchBox)
                    Toggle(loc.localized("boxArt.autoDownloadBoxArt"), isOn: $launchBoxDownloadAfterScan)
                } header: {
                    Label(loc.localized("boxArt.launchBoxGamesDB"), systemImage: "gamecontroller.fill")
                } footer: {
                    Text(loc.localized("boxArt.launchBoxDescription"))
                }
            }

            // ScreenScraper Account Section
            if !isSearching || matchesSearch("screenscraper account credentials box art free account username password") {
                Section {
                    TextField(loc.localized("boxArt.username"), text: $username)
                    SecureField(loc.localized("boxArt.password"), text: $password)
                    Button(loc.localized("boxArt.saveCredentials")) {
                        BoxArtService.shared.saveCredentials(
                            BoxArtService.ScreenScraperCredentials(username: username, password: password))
                        saved = true
                    }
                } header: {
                    Label(loc.localized("boxArt.screenScraperAccount"), systemImage: "person.badge.key")
                } footer: {
                    Text(loc.localized("boxArt.screenScraperDescription"))
                }
                if saved {
                    Label(loc.localized("boxArt.credentialsSaved"), systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            // Performance & Indexing Section
            if !isSearching || matchesSearch("performance indexing manifest refresh repository library URL 404 check") {
                Section {
                    let manifestService = LibretroThumbnailManifestService.shared
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loc.localized("boxArt.assetIndexing"))
                                    .font(.body)
                                Text(loc.localized("boxArt.assetIndexingDescription"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(action: {
                                Task {
                                    await manifestService.refreshAllManifests()
                                }
                            }) {
                                if manifestService.isRefreshing {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(loc.localized("boxArt.indexing"))
                                    }
                                } else {
                                    Label(loc.localized("boxArt.refreshIndex"), systemImage: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(manifestService.isRefreshing)
                        }
                        
                        if manifestService.isRefreshing {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: manifestService.refreshProgress)
                                    .progressViewStyle(.linear)
                                Text("\(loc.localized("boxArt.current")) \(manifestService.currentRepoRefreshing)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                            .padding(.top, 4)
                        }
                    }
                } header: {
                    Label(loc.localized("boxArt.performanceIndexing"), systemImage: "bolt.fill")
                } footer: {
                    Text(loc.localized("boxArt.performanceDescription"))
                }
            }
            
            // No results message
            if isSearching && !hasMatchingSections {
                Section {
                    Text("\(loc.localized("boxArt.noMatchingSettings")) \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
        }
        .formStyle(.grouped)
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
        matchesSearch("libretro thumbnail CDN CRC No-Intro DAT box art named boxarts named titles named snaps fuzzy name") ||
        matchesSearch("launchbox gamesdb box art download scan third-party fallback") ||
        matchesSearch("screenscraper account credentials box art free account username password") ||
        matchesSearch("performance indexing manifest refresh repository library URL 404 check")
    }
}
