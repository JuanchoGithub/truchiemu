# Implementation Plan

[Overview]
Replace `boxArtPath: URL?` with `hasBoxArt: Bool` on the ROM struct to track whether a game has valid box art, since the box art path is deterministic (`rom.path/boxart/<romname>_boxart.png`).

The current `boxArtPath` field stores a URL that is always computed the same way from the ROM's path. This is redundant. Instead, we add a simple `hasBoxArt: Bool` that gets set to `true` when the image loads successfully and `false` when it fails. The filter checks this boolean instead of checking file existence.

[Types]
Add `hasBoxArt: Bool = false` to the `ROM` struct and remove `boxArtPath: URL?`. Also replace `boxArtPath: String?` with `hasBoxArt: Bool` in SwiftData models (`ROMRecord`, `ROMEntry`) and `ROMMetadataRecord`.

```swift
// In ROM.swift — replace line 8:
// var boxArtPath: URL?
// With:
var hasBoxArt: Bool = false

// Update needsAutomaticBoxArt (lines 68-72):
var needsAutomaticBoxArt: Bool {
    return !hasBoxArt
}
```

[Files]

### TruchieEmu/Models/ROM.swift
- **Line 8**: Replace `var boxArtPath: URL?` with `var hasBoxArt: Bool = false`
- **Lines 68-72**: Replace `needsAutomaticBoxArt` computed property:
  ```swift
  // BEFORE:
  var needsAutomaticBoxArt: Bool {
      let fm = FileManager.default
      if let p = boxArtPath, fm.fileExists(atPath: p.path) { return false }
      return !fm.fileExists(atPath: boxArtLocalPath.path)
  }
  // AFTER:
  var needsAutomaticBoxArt: Bool {
      return !hasBoxArt
  }
  ```

### TruchieEmu/Views/Library/LibraryGridView.swift
- **Lines 153-155**: Replace `GameFilterOption.noBoxArt.matches` switch case:
  ```swift
  // BEFORE:
  case .noBoxArt:
      if let p = rom.boxArtPath { return !fm.fileExists(atPath: p.path) }
      return true
  // AFTER:
  case .noBoxArt:
      return !rom.hasBoxArt
  ```
- Remove `let fm = FileManager.default` from `matches()` (line 151) if no longer needed by other cases (it is — other cases don't use it).

### TruchieEmu/Views/GameCardView.swift
- **Lines 152-170**: Replace `.task(id: rom.id)` block to set `hasBoxArt`:
  ```swift
  .task(id: rom.id) {
      // Deterministic path — always the same for a given ROM
      let artPath = rom.boxArtLocalPath
      
      if let img = await ImageCache.shared.image(for: artPath) {
          self.image = img
          await MainActor.run {
              if !rom.hasBoxArt {
                  var updated = rom
                  updated.hasBoxArt = true
                  library.updateROM(updated)
              }
          }
      } else {
          // Image not found or invalid — ensure hasBoxArt is false
          await MainActor.run {
              if rom.hasBoxArt {
                  var updated = rom
                  updated.hasBoxArt = false
                  library.updateROM(updated)
              }
              self.image = nil
          }
      }
  }
  ```
- **Lines 238-301**: Replace `resolveBoxArtOnDemand(for:)` — simplify to check `boxArtLocalPath` only (path is deterministic):
  ```swift
  nonisolated
  static func resolveBoxArtOnDemand(for rom: ROM) async -> URL? {
      let artPath = rom.boxArtLocalPath
      if FileManager.default.fileExists(atPath: artPath.path) {
          return artPath
      }
      return nil
  }
  ```

### TruchieEmu/Services/BoxArtService.swift
- **Lines 115-134**: Replace `resolveLocalBoxArtIfNeeded(for:library:)`:
  ```swift
  @MainActor
  func resolveLocalBoxArtIfNeeded(for rom: ROM, library: ROMLibrary) -> URL? {
      if rom.hasBoxArt { return rom.boxArtLocalPath }
      
      LoggerService.info(category: "BoxArt", "Lazy-resolving local boxart for '\(rom.displayName)' (system: \(rom.systemID ?? "unknown"))")
      
      if let localURL = resolveLocalBoxArt(for: rom) {
          var updated = rom
          updated.hasBoxArt = true
          library.updateROM(updated)
          LoggerService.info(category: "BoxArt", "✅ Local boxart found: \(localURL.lastPathComponent) for '\(rom.displayName)'")
          return localURL
      }
      return nil
  }
  ```
- **Lines 211-221**: Replace `resolveLocalBoxArtBatch(for:)` to set `hasBoxArt`:
  ```swift
  func resolveLocalBoxArtBatch(for roms: [ROM]) -> [ROM] {
      var found: [ROM] = []
      for rom in roms {
          if let localURL = resolveLocalBoxArt(for: rom) {
              var updated = rom
              updated.hasBoxArt = true
              found.append(updated)
          }
      }
      return found
  }
  ```
- **Lines 225-239**: Replace `resolveAllLocalBoxArtAndPersist(library:)`:
  ```swift
  func resolveAllLocalBoxArtAndPersist(library: ROMLibrary) {
      let romsWithoutArt = library.roms.filter { !$0.hasBoxArt }
      guard !romsWithoutArt.isEmpty else { return }

      LoggerService.info(category: "BoxArt", "Scanning \(romsWithoutArt.count) ROM(s) for local boxart in /boxart folders...")
      let found = resolveLocalBoxArtBatch(for: romsWithoutArt)

      if !found.isEmpty {
          LoggerService.info(category: "BoxArt", "Found local boxart for \(found.count) ROM(s)")
          for rom in found {
              library.updateROM(rom)
          }
          signalBoxArtUpdated(for: UUID())
      }
  }
  ```
- **Lines 542-576**: Remove `isValidImageFile(at:)` method entirely (no longer needed — SwiftUI `Image(nsImage:)` handles validation).
- **Lines 582-586**: Remove `isBoxArtBroken(rom:)` method.
- **Lines 589-591**: Remove `findBrokenBoxArts(in:)` method.
- **Lines 593-610**: Remove `cleanBrokenBoxArts(for:)` method.
- **Lines 613-621**: Replace `romsNeedingBoxArt(in:)`:
  ```swift
  func romsNeedingBoxArt(in roms: [ROM]) -> [ROM] {
      roms.filter { !$0.hasBoxArt }
  }
  ```
- **Lines 632-637**: Remove broken boxart cleanup from `batchDownloadBoxArtLibretro`:
  ```swift
  // Remove lines 632-637 (broken boxart detection and cleaning at start of method)
  ```
- **Line 674**: Replace `completedRom.boxArtPath = savedURL` with `completedRom.hasBoxArt = true`
- **Line 718-729**: Remove broken boxart cleanup from `batchDownloadBoxArtGoogle`:
  ```swift
  // Remove broken boxart detection and cleaning at start of method
  ```
- **Line 757**: Replace `completedRom.boxArtPath = savedURL` with `completedRom.hasBoxArt = true`
- **Lines 358-377**: Simplify `downloadAndCache` — remove content-type validation since we rely on Image() to validate:
  - Keep HTTP status code check (2xx range) since it prevents saving non-200 responses
  - Remove `validImageTypes` check and `contentType` validation (lines 371-376)

### TruchieEmu/Services/ROMScanner.swift
- **Lines 128-130**: Replace box art check:
  ```swift
  // BEFORE:
  if !rom.isBios && fm.fileExists(atPath: rom.boxArtLocalPath.path) {
      rom.boxArtPath = rom.boxArtLocalPath
  }
  // AFTER:
  if !rom.isBios && fm.fileExists(atPath: rom.boxArtLocalPath.path) {
      rom.hasBoxArt = true
  }
  ```
- **Lines 843-845**: Same change in the `scan(urls:)` method:
  ```swift
  if !rom.isBios && fm.fileExists(atPath: rom.boxArtLocalPath.path) {
      rom.hasBoxArt = true
  }
  ```

### TruchieEmu/Services/LibraryAutomationCoordinator.swift
- **Line 35**: Replace filter:
  ```swift
  // BEFORE: let romsToCheck = snapshot.filter { $0.boxArtPath == nil }
  // AFTER:
  let romsToCheck = snapshot.filter { !$0.hasBoxArt }
  ```
- **Lines 122-125**: Replace `stillMissing` filter:
  ```swift
  // BEFORE:
  let stillMissing = library.roms.filter { rom in
      let hasBoxart = rom.boxArtPath.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
      return rom.needsAutomaticBoxArt && !hasBoxart
  }
  // AFTER:
  let stillMissing = library.roms.filter { rom in
      !rom.hasBoxArt
  }
  ```

### TruchieEmu/Services/BoxArtPreloaderService.swift
- **Line 127**: Change `guard let artPath = rom.boxArtPath` to use deterministic path:
  ```swift
  // BEFORE:
  guard let artPath = rom.boxArtPath else { continue }
  // AFTER:
  guard rom.hasBoxArt else { continue }
  let artPath = rom.boxArtLocalPath
  ```
- **Lines 173-181**: Replace `invalidateImage(for:)`:
  ```swift
  func invalidateImage(for rom: ROM) {
      let url = rom.boxArtLocalPath
      Task {
          await ImageCache.shared.removeImage(for: url)
          await ImageCache.shared.removeThumbnail(for: url)
      }
  }
  ```

### TruchieEmu/Services/SetupWizardState.swift
- **Lines 154-155**: Replace box art checking:
  ```swift
  // BEFORE:
  if let artPath = rom.boxArtPath, fm.fileExists(atPath: artPath.path) {
      boxArtImage = NSImage(contentsOf: artPath)
  }
  // AFTER:
  if rom.hasBoxArt {
      boxArtImage = NSImage(contentsOf: rom.boxArtLocalPath)
  }
  ```

### TruchieEmu/Services/CLIManager.swift
- Search for `boxArtPath: nil` in ROM creation and remove it (ROM struct default handles it).

### TruchieEmu/Services/Persistence/ROMRepository.swift
- Search for `boxArtPath: nil` in ROM creation and remove it.

### TruchieEmu/Services/ROMLibrary.swift
- **Line**: Replace `roms[i].boxArtPath = nil` with `roms[i].hasBoxArt = false`

### TruchieEmu/Services/LaunchBoxGamesDBService.swift
- Find all `completedRom.boxArtPath = savedURL` and replace with `completedRom.hasBoxArt = true`
- Find all `updated.boxArtPath = boxArtURL` and replace with `updated.hasBoxArt = true`

### TruchieEmu/Models/SwiftDataModels.swift
- **Line 12**: Replace `var boxArtPath: String?` with `var hasBoxArt: Bool = false` in `ROMEntry`
- **Lines 46**: Remove `boxArtPath: String? = nil` from `init` parameters
- **Line 68**: Remove `self.boxArtPath = boxArtPath` from init body
- **Line 105**: Keep `boxArtPath: String?` in `ROMMetadataEntry` for backwards compat with legacy metadata, or replace with `hasBoxArt: Bool = false`

### TruchieEmu/Models/LibraryMetadataStore.swift
- **Line 27**: Replace `var boxArtPath: String?` with `var hasBoxArt: Bool = false` in `ROMMetadataRecord`
- **Line 50**: Replace `boxArtPath = rom.boxArtPath?.path` with `hasBoxArt = rom.hasBoxArt`
- **Lines 71-73**: Replace boxArtPath application:
  ```swift
  // BEFORE:
  if let p = boxArtPath, FileManager.default.fileExists(atPath: p) {
      r.boxArtPath = URL(fileURLWithPath: p)
  }
  // AFTER:
  r.hasBoxArt = hasBoxArt
  ```
- **Lines 110, 131, 259**: Replace `boxArtPath` references with `hasBoxArt` in `ROMMetadataEntry` and `updateEntryFromRecord`

### TruchieEmu/Views/Detail/GameDetailView.swift
- **Line**: Remove `.onChange(of: currentROM.boxArtPath)` or replace with `.onChange(of: currentROM.hasBoxArt)`
- Find all `currentROM.boxArtPath` references and replace with `currentROM.boxArtLocalPath` when path is needed for loading, or check `currentROM.hasBoxArt` for display logic
- Replace `u.boxArtPath = url` with `u.hasBoxArt = true`

### TruchieEmu/Views/BoxArt/BoxArtPickerView.swift
- Replace `updated.boxArtPath = nil` with `updated.hasBoxArt = false`
- Replace `updated.boxArtPath = localURL` with `updated.hasBoxArt = true`

[Functions]
- **ROM.needsAutomaticBoxArt** — Change body to `return !hasBoxArt`
- **GameFilterOption.noBoxArt.matches()** — Change to `return !rom.hasBoxArt`
- **BoxArtService.resolveLocalBoxArtIfNeeded()** — Set `hasBoxArt = true` when found
- **BoxArtService.resolveAllLocalBoxArtAndPersist()** — Filter by `!hasBoxArt`, set `hasBoxArt = true` for found ROMs
- **BoxArtService.romsNeedingBoxArt()** — Return `roms.filter { !$0.hasBoxArt }`
- **BoxArtService.isValidImageFile()** — Remove entirely
- **BoxArtService.isBoxArtBroken()** — Remove entirely
- **BoxArtService.findBrokenBoxArts()** — Remove entirely
- **BoxArtService.cleanBrokenBoxArts()** — Remove entirely
- **GameCardView.resolveBoxArtOnDemand()** — Simplify to check `boxArtLocalPath` only
- **BoxArtPreloaderService.invalidateImage()** — Use `rom.boxArtLocalPath` instead of `rom.boxArtPath`

[Classes]
- **ROM struct** — Replace `boxArtPath: URL?` with `hasBoxArt: Bool = false`
- **ROMEntry @Model** — Replace `boxArtPath: String?` with `hasBoxArt: Bool`
- **ROMMetadataRecord** — Replace `boxArtPath: String?` with `hasBoxArt: Bool`
- **ROMMetadataEntry @Model** — Replace `boxArtPath: String?` with `hasBoxArt: Bool`
- **BoxArtService** — Remove `isValidImageFile`, `isBoxArtBroken`, `findBrokenBoxArts`, `cleanBrokenBoxArts` methods
- **BoxArtPreloaderService** — Update `preloadBoxArt` and `invalidateImage` to use `hasBoxArt`

[Dependencies]
No new dependencies.

[Testing]
- Test "No Box Art" filter shows only games without valid box art
- Test games with box art are excluded from filter
- Test box art download sets `hasBoxArt = true`
- Test box art picker sets `hasBoxArt` correctly
- Test that broken/invalid box art files result in `hasBoxArt = false`
- Test ROMScanner sets `hasBoxArt = true` when local box art exists
- Test LibraryAutomationCoordinator correctly identifies ROMs needing art
- Test batch download methods update `hasBoxArt` on success

[Implementation Order]
1. Add `hasBoxArt: Bool` to ROM struct, update `needsAutomaticBoxArt` to `return !hasBoxArt`
2. Update `GameFilterOption.noBoxArt.matches()` in LibraryGridView to `return !rom.hasBoxArt`
3. Update GameCardView `.task(id: rom.id)` to set `hasBoxArt` based on ImageCache load success/failure; simplify `resolveBoxArtOnDemand`
4. Update BoxArtService: refactor `resolveLocalBoxArtIfNeeded`, `resolveAllLocalBoxArtAndPersist`, `resolveLocalBoxArtBatch` to set `hasBoxArt`; remove `isValidImageFile`, `isBoxArtBroken`, `findBrokenBoxArts`, `cleanBrokenBoxArts`; update `romsNeedingBoxArt` and batch download methods
5. Update ROMScanner (both `scan(folder:)` and `scan(urls:)` methods), LibraryAutomationCoordinator, and BoxArtPreloaderService
6. Update SetupWizardState, CLIManager (remove `boxArtPath: nil`), ROMRepository (remove `boxArtPath: nil`), ROMLibrary, LaunchBoxGamesDBService
7. Update SwiftDataModels: `ROMEntry` replace `boxArtPath` with `hasBoxArt`; `ROMMetadataRecord` and `ROMMetadataEntry` same change; update `LibraryMetadataStore` conversions
8. Update GameDetailView (`.onChange`, load logic) and BoxArtPickerView (set `hasBoxArt`)
9. Search for remaining `boxArtPath` references and remove/replace all of them
10. Build, test, and verify the "No Box Art" filter works correctly