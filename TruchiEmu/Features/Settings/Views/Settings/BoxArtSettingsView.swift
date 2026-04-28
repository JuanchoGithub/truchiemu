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
                    Toggle("Use Libretro thumbnail CDN", isOn: $useLibretroThumbnails)
                    TextField("CDN base URL", text: $thumbnailBaseURLString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Picker("Try first", selection: $thumbnailPriorityRaw) {
                        ForEach(LibretroThumbnailPriority.allCases) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    Toggle("Match ROM using CRC + No-Intro DAT", isOn: $useCRCMatching)
                    Toggle("Fallback to sanitized filename if CRC not in DAT", isOn: $fallbackFilename)
                    Toggle("Use HTTP HEAD before downloading (fewer bytes on miss)", isOn: $useHeadCheck)
                } header: {
                    Label("Libretro Thumbnails", systemImage: "photo.on.rectangle.angled")
                } footer: {
                    Text("Uses thumbnails.libretro.com with CRC-based names from Libretro DAT files when available, then Named_Boxarts → Named_Titles → Named_Snaps, with a fuzzy name pass.")
                }
            }

            // LaunchBox GamesDB Section
            if !isSearching || matchesSearch("launchbox gamesdb box art download scan third-party fallback") {
                Section {
                    Toggle("Enable LaunchBox GamesDB", isOn: $useLaunchBox)
                    Toggle("Auto-download box art after scan", isOn: $launchBoxDownloadAfterScan)
                } header: {
                    Label("LaunchBox GamesDB", systemImage: "gamecontroller.fill")
                } footer: {
                    Text("Queries gamesdb.launchbox-app.com as a third-party fallback when the Libretro CDN has no box art. Enable auto-download to fill gaps after scanning your library.")
                }
            }

            // ScreenScraper Account Section
            if !isSearching || matchesSearch("screenscraper account credentials box art free account username password") {
                Section {
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    Button("Save Credentials") {
                        BoxArtService.shared.saveCredentials(
                            BoxArtService.ScreenScraperCredentials(username: username, password: password))
                        saved = true
                    }
                } header: {
                    Label("ScreenScraper Account", systemImage: "person.badge.key")
                } footer: {
                    Text("Optional fallback when Libretro CDN has no art. Create a free account at [screenscraper.fr](https://www.screenscraper.fr). Your credentials are stored locally on this device only.")
                }
                if saved {
                    Label("Credentials saved!", systemImage: "checkmark.circle.fill")
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
                                Text("Asset Indexing")
                                    .font(.body)
                                Text("Indexes help the app skip broken or missing URLs instantly.")
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
                                        Text("Indexing...")
                                    }
                                } else {
                                    Label("Refresh Index", systemImage: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(manifestService.isRefreshing)
                        }
                        
                        if manifestService.isRefreshing {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: manifestService.refreshProgress)
                                    .progressViewStyle(.linear)
                                Text("Current: \(manifestService.currentRepoRefreshing)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                            .padding(.top, 4)
                        }
                    }
                } header: {
                    Label("Performance & Indexing", systemImage: "bolt.fill")
                } footer: {
                    Text("Refresh the index to sync with the latest Libretro repository listings. This significantly improves speed when browsing large libraries by eliminating 'blind' 404 checks.")
                }
            }
            
            // No results message
            if isSearching && !hasMatchingSections {
                Section {
                    Text("No matching settings found for \"\(searchText)\"")
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
