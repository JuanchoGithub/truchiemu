# LaunchBox Metadata Service

## Objective
Replace the broken `LaunchBoxGamesDBService` (751 lines of dead HTML scraping code) with a new service that downloads the public `Metadata.zip` (501MB), stream-parses Metadata.xml (183,999 games, 68,263 alternate names, 1,301,898 images), and writes per-platform JSON lookup files for lightweight on-demand metadata enrichment + box art queries.

## Background
- LaunchBox GamesDB was redesigned as a Nuxt.js SPA — the old server-rendered HTML that the scraper relied on no longer exists
- Image CDN URLs changed to UUID-based filenames: `https://images.launchbox-app.com/{uuid}.jpg`
- LaunchBox publishes the full database as `Metadata.zip` at `https://gamesdb.launchbox-app.com/Metadata.zip` (updated daily)
- This zip has been publicly linked by LaunchBox staff for years; multiple well-known open-source projects (RomM, artwork4DMD, msleuth, launchbox-to-json) use it without issue
- The XML has three relevant sections: `<Game>` (metadata), `<GameAlternateName>` (alternate titles), `<GameImage>` (UUID filenames + type + region + CRC32)

## XML Structure

### `<Game>` elements (183,999 entries)
```
<Game>
  <Name>Super Mario World</Name>
  <ReleaseDate>1990-11-21T00:00:00+00:00</ReleaseDate>
  <ReleaseYear>1990</ReleaseYear>
  <Overview>A platform game developed by Nintendo...</Overview>
  <Developer>Nintendo EAD</Developer>
  <Publisher>Nintendo</Publisher>
  <Genres>Platform</Genres>
  <Platform>Nintendo - Super Nintendo Entertainment System</Platform>
  <DatabaseID>12345</DatabaseID>
  <CommunityRating>4.5</CommunityRating>
  <ESRB>E</ESRB>
  <MaxPlayers>2</MaxPlayers>
  <Cooperative>true</Cooperative>
  <VideoURL>https://...</VideoURL>
  <WikipediaURL>https://...</WikipediaURL>
</Game>
```

### `<GameAlternateName>` elements (68,263 entries)
```
<GameAlternateName>
  <AlternateName>Super Mario World 2</AlternateName>
  <DatabaseID>12345</DatabaseID>
</GameAlternateName>
```

### `<GameImage>` elements (1,301,898 entries)
```
<GameImage>
  <DatabaseID>1</DatabaseID>
  <FileName>a109008e-a8dc-4c4a-8a25-d4eade4d67b3.jpg</FileName>
  <Type>Box - Front</Type>
  <Region>Spain</Region>
  <CRC32>1100199168</CRC32>
</GameImage>
```

Image URL template: `https://images.launchbox-app.com/{FileName}`

### Image type breakdown (partial)
| Type | Count |
|---|---|
| Box - Front | 202,031 |
| Screenshot - Gameplay | ~350k |
| Clear Logo | ~120k |
| Fanart - Box - Front | ~100k |
| Screenshot - Game Title | ~80k |
| Banner | ~50k |
| + 27 more types | rest |

## Data Model

### New structs (in `LaunchBoxMetadataService.swift`)
```swift
struct LaunchBoxGame: Codable, Hashable {
    let databaseID: Int
    let name: String
    let platform: String
    let releaseDate: String?
    let releaseYear: String?
    let overview: String?
    let developer: String?
    let publisher: String?
    let genres: String?
    let communityRating: Double?
    let esrb: String?
    let maxPlayers: Int?
    let cooperative: Bool?
    let videoURL: String?
    let wikipediaURL: String?
    let alternateNames: [String]
    let images: [LaunchBoxImageRef]
}

struct LaunchBoxImageRef: Codable, Hashable {
    let fileName: String
    let type: String
    let region: String?
    let crc32: String?
}
```

### Per-platform JSON files
```
~/Library/Application Support/TruchiEmu/LaunchBox/
  Metadata.zip                          # downloaded zip (cached)
  Platforms/
    Nintendo - Nintendo Entertainment System.json
    Sega - Genesis.json
    Sony - PlayStation.json
    ...
```

## Implementation Phases

### Phase 1: `LaunchBoxMetadataService.swift` (NEW — ~500 lines)

`@MainActor ObservableObject` following `CheatDownloadService` progress pattern:

**Progress properties:**
```swift
@Published var isDownloading = false
@Published var downloadProgress: Double = 0
@Published var downloadStatus: String = ""
@Published var totalItems: Int = 0
@Published var completedItems: Int = 0
@Published var currentPhase: Phase = .idle

enum Phase { case idle, downloading, parsing, indexing, ready }
```

**Core methods:**
| Method | Purpose |
|---|---|
| `downloadAndParseIfNeeded() async -> Bool` | Check staleness (24h), download Metadata.zip, stream-parse XML, write per-platform JSON |
| `games(for platformName: String) -> [LaunchBoxGame]` | Read platform JSON from disk, cache in memory |
| `bestMatch(for gameName: String, platformName: String) -> LaunchBoxGame?` | Fuzzy match against name + alternateNames using `String.fuzzyMatch()` |
| `boxArtRef(for game: LaunchBoxGame) -> LaunchBoxImageRef?` | Pick best Box - Front by region preference |
| `cdnURL(for imageRef: LaunchBoxImageRef) -> URL` | Construct `https://images.launchbox-app.com/{uuid}.{ext}` |
| `fetchAndApplyMetadata(for rom: ROM, library: ROMLibrary) async -> Bool` | Lookup + merge fields + download box art |

**XMLParser state machine:**
```swift
private enum ParseState {
    case idle
    case inGame(currentDbID: Int, currentPlatform: String)
    case inGameField(name: String)
    case inAlternateName(currentDbID: Int)
    case inGameImage(currentDbID: Int)
}
```
Stream through the 501MB XML in order (Games → AlternateNames → GameImages), accumulating into:
- `games: [Int: LaunchBoxGame]` (built from `<Game>` elements)
- Then attach alternate names from `<GameAlternateName>`
- Then attach image refs from `<GameImage>`

After all three sections parsed, group by platform and write one JSON per platform. Then free the big dictionaries.

**Threading:**
- XML parsing on `Task.detached(priority: .utility)` — 501MB will take ~5–10 seconds
- `@Published` progress updates marshalled to MainActor (throttled to 50ms)
- Per-platform JSON writes via `data.write(to:options:.atomic)` on background

### Phase 2: Gut `LaunchBoxGamesDBService.swift` (751 → ~60 lines)

**Remove (dead web-scraping code):**
- `searchGamesWeb()`, `parseGameSearchResults()`, `extractFirstBoxartURL()`
- `fetchBoxArtFromDetailWeb()`, `extractBoxartFromDetailHTML()`
- `downloadAndCache()` (old box art downloader)
- `fetchBoxArt()`, `fetchBoxArtInner()`, `batchDownloadBoxArt()`
- `batchSyncLibrary()`, `cleanAlternateTitle()`
- `private lazy var urlSession`

**Keep:**
```swift
enum LaunchBoxPlatformMapper { static func launchBoxPlatformName(for:) -> String? }
var isEnabled: Bool          // now gates LaunchBoxMetadataService
var downloadAfterScan: Bool  // still used by LibraryAutomationCoordinator
var lastSyncDate: Date?
func recordSyncDate()
func setEnabled(_:)
func fetchAndApplyMetadata(for rom: ROM, library: ROMLibrary) async -> Bool
```

The `fetchAndApplyMetadata` becomes a thin delegate:
```swift
func fetchAndApplyMetadata(for rom: ROM, library: ROMLibrary) async -> Bool {
    await LaunchBoxMetadataService.shared.fetchAndApplyMetadata(for: rom, library: library)
}
```

### Phase 3: Rewrite `MetadataSyncCoordinator.swift` (111 lines)

Replace the old web-scraping `launchbox.fetchAndApplyMetadata` calls with new `LaunchBoxMetadataService` flow:

```swift
func runAfterLibraryUpdate(library: ROMLibrary, targetROMs: [ROM]?) async {
    guard LaunchBoxGamesDBService.shared.isEnabled else { return }
    let metadataService = LaunchBoxMetadataService.shared
    guard await metadataService.downloadAndParseIfNeeded() else { return }
    
    let scope = targetROMs ?? library.roms
    let needMetadata = scope.filter { needsLaunchBoxEnrichment($0) }
    guard !needMetadata.isEmpty else { return }
    
    isActive = true; phase = .syncing; defer { isActive = false; phase = .idle }
    let total = needMetadata.count
    var completed = 0
    
    for rom in needMetadata {
        let ok = await metadataService.fetchAndApplyMetadata(for: rom, library: library)
        completed += 1
        progress = Double(completed) / Double(total)
        statusLine = "Enriching: \(completed)/\(total) — \(rom.displayName)"
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    
    LaunchBoxGamesDBService.shared.recordSyncDate()
}
```

Remove dead `fullSync()` method.

### Phase 4: Update `BoxArtService.swift` LaunchBox Fallback

Replace the old broken box art fallback at `BoxArtService.fetchBoxArt()` step 3:

```swift
// New LaunchBox box art path (3rd priority):
let platformName = LaunchBoxPlatformMapper.launchBoxPlatformName(for: rom.systemID ?? "")
if let meta = await LaunchBoxMetadataService.shared.bestMatch(
    for: rom.displayName,
    platformName: platformName
), let imageRef = LaunchBoxMetadataService.shared.boxArtRef(for: meta) {
    let cdnURL = LaunchBoxMetadataService.cdnURL(for: imageRef)
    return await downloadAndCache(artURL: cdnURL, for: rom)
}
```

### Phase 5: Update `LibraryAutomationCoordinator.swift`

Replace `LaunchBoxGamesDBService.shared.batchDownloadBoxArt(...)` call with `MetadataSyncCoordinator` trigger:

```swift
if LaunchBoxGamesDBService.shared.downloadAfterScan {
    let stillMissing = scope.filter { !$0.hasBoxArt }
    if !stillMissing.isEmpty {
        statusLine = localizedStatus("library.automation.tryingLaunchbox", "\(stillMissing.count)")
        await MetadataSyncCoordinator.shared.runAfterLibraryUpdate(
            library: library,
            targetROMs: stillMissing
        )
    }
}
```

### Phase 6: Update Settings UI + Translations

**BoxArtSettingsView.swift:** Rename section, add last-sync date and "Sync Now" button.

**Translation keys to add:**
| Key | English |
|---|---|
| `launchbox.section` | `LaunchBox Games Database` |
| `launchbox.enable` | `Enable LaunchBox` |
| `launchbox.autoSync` | `Auto-sync after scan` |
| `launchbox.lastSync` | `Last synced` |
| `launchbox.syncNow` | `Sync Now` |
| `launchbox.description` | `Enriches ROM metadata (overview, genre, developer, publisher) and provides box art from the LaunchBox Games Database. Data is community-curated.` |

Remove old keys: `boxArt.enableLaunchBox`, `boxArt.autoDownloadBoxArt`, `boxArt.launchBoxDescription`.

## File Change Summary

| File | Action | Lines |
|---|---|---|
| `plans/launchbox-metadata-service.md` | NEW | +200 |
| `Services/LaunchBoxMetadataService.swift` | NEW | +500 |
| `Services/LaunchBoxGamesDBService.swift` | GUT | -690, +40 |
| `Services/MetadataSyncCoordinator.swift` | REWRITE | -50, +80 |
| `Services/BoxArtService.swift` | PATCH | -5, +25 |
| `Features/Library/Services/LibraryAutomationCoordinator.swift` | PATCH | -4, +6 |
| `Features/Settings/Views/Settings/BoxArtSettingsView.swift` | PATCH | -10, +30 |
| `Resources/Translations/en.json` | PATCH | +7 |
| `Resources/Translations/es.json` | PATCH | +7 |
| `Resources/Translations/pt.json` | PATCH | +7 |

**Total: ~700 lines new code, ~750 lines deleted (dead web scraper gone).**

## Open Questions (Resolved in Planning)

1. **LaunchBox images?** YES — `<GameImage>` elements provide UUIDs; CDN at `images.launchbox-app.com` serves them publicly. Proceed with both images + metadata.
2. **Legality?** Metadata.zip is publicly linked by LaunchBox staff. RomM and other projects use it for images without issue. No ToS exists. Proceed.
3. **Fuzzy matching?** Use `String.fuzzyMatch()` from `SearchMatch.swift` — character-by-character sequential matching, already used throughout the codebase.
4. **Region preference for images?** Use `SystemPreferences.shared.systemLanguage.noIntroRegionPreference` — same as libretro CDN path.
5. **TLV parsing?** No — use Foundation `XMLParser` for stream-based parsing. Avoid loading 501MB into memory.
