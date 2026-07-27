import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers
import Compression
import Combine

// MARK: - Slot Info

// Represents a single save state slot's metadata
struct SlotInfo: Identifiable, Equatable {
    let id: Int // slot number (0-9, -1 for auto)
    let exists: Bool
    let fileSize: Int64?
    let modificationDate: Date?
    let progressiveVersion: Int?
    // Optional user-defined display label for this slot. Persisted via
    // SaveStateManager as a sidecar `.meta.json` file. Empty for the auto
    // slot (-1) and for user slots that have never been named.
    var customName: String?

    static func == (lhs: SlotInfo, rhs: SlotInfo) -> Bool {
        lhs.id == rhs.id
            && lhs.progressiveVersion == rhs.progressiveVersion
            && lhs.customName == rhs.customName
    }

    // Computed: display slot name (or "Auto" for slot -1).
    // Honors a user-supplied customName when present (user slots only),
    // otherwise falls back to "Slot <id>" or "Auto".
    var displayName: String {
        if id == -1 { return "Auto" }
        if let name = customName, !name.isEmpty {
            return name
        }
        return "Slot \(id)"
    }
}

// MARK: - Save State Manager
// Thread-safe for concurrent access.
class SaveStateManager: ObservableObject, @unchecked Sendable {
    
  // MARK: - Published State

  // Base directory for all save states (computed from SaveDirectoryManager)
  var savesDirectory: URL {
    SaveDirectoryManager.shared.statesDirectory
  }
  
  private var cancellables = Set<AnyCancellable>()

  // MARK: - Initialization

  init() {
    // Observe for directory changes
    SaveDirectoryManager.shared.$activeSaveDirectory
      .sink { [weak self] _ in
        self?.updateDirectoryPaths()
      }
      .store(in: &cancellables)

    ensureDirectoriesExist()
  }
    
    // MARK: - Directory Management
    
  // Ensures the base save states directory exists
  private func ensureDirectoriesExist() {
    do {
      try FileManager.default.createDirectory(
        at: savesDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      LoggerService.info(category: "SaveStateManager", "ERROR creating base directory: \(error)")
    }
  }
  
  // Updates directory paths when save directory changes
  private func updateDirectoryPaths() {
    // The savesDirectory is now immutable after init, but we can
    // trigger a refresh of any cached data if needed
    #if LOG_DEBUG
    LoggerService.debug(category: "SaveStateManager", "Save directory changed: \(savesDirectory.path)")
    #endif
  }
    
    // Returns the system-specific subdirectory, creating it if needed
    func systemDirectory(systemID: String) -> URL {
        let dir = savesDirectory.appendingPathComponent(safePathComponent(systemID))
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        } catch {
            LoggerService.info(category: "SaveStateManager", "ERROR creating system directory: \(error)")
        }
        return dir
    }
    
    // MARK: - Path Resolution
    
// Returns the full URL for a save state file
// - Parameters:
// - gameName: The display name of the game (used for filename)
// - systemID: The system identifier (used for subdirectory)
// - slot: Slot number (0-9 for user slots, -1 for auto-save)
// - Returns: URL to the .state file
func statePath(gameName: String, systemID: String, slot: Int) -> URL {
    let sysDir = systemDirectory(systemID: systemID)
    let safeName = safeGameStateName(gameName)

    let fileName: String
    if slot == -1 {
        fileName = "\(safeName)__autosave"
    } else {
        fileName = "\(safeName)__slot_\(slot)"
    }

return sysDir.appendingPathComponent(fileName)
    }
    
    // Returns the full URL for a save state thumbnail
    // - Parameters:
    //   - gameName: The display name of the game
    //   - systemID: The system identifier
    //   - slot: Slot number
    // - Returns: URL to the .png thumbnail file
    func thumbnailPath(gameName: String, systemID: String, slot: Int) -> URL {
        let stateURL = statePath(gameName: gameName, systemID: systemID, slot: slot)
        return stateURL.appendingPathExtension("png")
    }
    
    // MARK: - Slot Information
    
    // Returns info for a specific slot
    func slotInfo(gameName: String, systemID: String, slot: Int) -> SlotInfo {
        let path = statePath(gameName: gameName, systemID: systemID, slot: slot)
        let fm = FileManager.default

        guard let attrs = try? fm.attributesOfItem(atPath: path.path) else {
            return SlotInfo(id: slot, exists: false, fileSize: nil, modificationDate: nil, progressiveVersion: nil, customName: loadSlotName(gameName: gameName, systemID: systemID, slot: slot))
        }

        return SlotInfo(
            id: slot,
            exists: true,
            fileSize: attrs[.size] as? Int64,
            modificationDate: attrs[.modificationDate] as? Date,
            progressiveVersion: nil,
            customName: loadSlotName(gameName: gameName, systemID: systemID, slot: slot)
        )
    }
    
    // Returns info for all user slots (0-9) plus auto slot (-1)
    // Uses progressive saves as the source of truth; marks slot as existing if any progressive version exists
    func allSlotInfo(gameName: String, systemID: String) -> [SlotInfo] {
        return (-1...9).map { slot in
            let versions = progressiveSlotVersions(gameName: gameName, systemID: systemID, slot: slot)
            if !versions.isEmpty {
                let newestVersion = versions.max() ?? 1
                let info = progressiveSlotInfo(gameName: gameName, systemID: systemID, slot: slot, version: newestVersion)
                return SlotInfo(id: slot, exists: true, fileSize: info.fileSize, modificationDate: info.modificationDate, progressiveVersion: nil, customName: loadSlotName(gameName: gameName, systemID: systemID, slot: slot))
            }
            // Fallback: check base file
            return slotInfo(gameName: gameName, systemID: systemID, slot: slot)
        }
    }
    
    // Returns only user slots with existing save files, useful for cleanup
    func existingSlots(gameName: String, systemID: String) -> [SlotInfo] {
        allSlotInfo(gameName: gameName, systemID: systemID).filter { $0.exists }
    }

    // Returns the single most recently-modified save state across ALL slots
    // (auto -1 through 9) including every progressive version. Used to power
    // a "Continue" affordance that jumps straight to the newest save.
    func mostRecentSaveState(gameName: String, systemID: String) -> SlotInfo? {
        let slots = allSlotInfo(gameName: gameName, systemID: systemID)
        var best: SlotInfo?
        var bestDate: Date = .distantPast

        for slot in slots {
            let versions = progressiveSlotVersions(gameName: gameName, systemID: systemID, slot: slot.id)
            if !versions.isEmpty {
                for v in versions {
                    let info = progressiveSlotInfo(gameName: gameName, systemID: systemID, slot: slot.id, version: v)
                    if info.exists, let date = info.modificationDate, date > bestDate {
                        bestDate = date
                        best = info
                    }
                }
            }
            if slot.exists, let date = slot.modificationDate, date > bestDate {
                bestDate = date
                best = slot
            }
        }
        return best
    }
    
    // MARK: - File Operations
    
    // Checks if a save state exists for the given slot
    func hasState(gameName: String, systemID: String, slot: Int) -> Bool {
        let path = statePath(gameName: gameName, systemID: systemID, slot: slot)
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    // MARK: - Slot Display Name Persistence

    private struct SaveSlotMetaPayload: Codable {
        var name: String?
    }

    // Returns the URL of the sidecar metadata JSON for a given slot.
    // Stored next to the (possibly-absent) base `.state` file so it survives
    // progressive version rotation but is cleared when the slot is deleted.
    func slotMetaPath(gameName: String, systemID: String, slot: Int) -> URL {
        return statePath(gameName: gameName, systemID: systemID, slot: slot)
            .appendingPathExtension("meta.json")
    }

    // Reads the user-defined name for a slot, or nil if unset/empty.
    func loadSlotName(gameName: String, systemID: String, slot: Int) -> String? {
        let url = slotMetaPath(gameName: gameName, systemID: systemID, slot: slot)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let payload = try? JSONDecoder().decode(SaveSlotMetaPayload.self, from: data)
        if let name = payload?.name, !name.isEmpty {
            return name
        }
        return nil
    }

    // Persists (or clears, when name is empty/nil) the user-defined name for a
    // user slot (0-9). Auto slot (-1) is intentionally ignored.
    func setSlotName(_ name: String?, gameName: String, systemID: String, slot: Int) {
        guard slot >= 0 else { return }
        let url = slotMetaPath(gameName: gameName, systemID: systemID, slot: slot)
        let fm = FileManager.default
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
            return
        }
        let payload = SaveSlotMetaPayload(name: trimmed)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func clearSlotMeta(gameName: String, systemID: String, slot: Int) {
        let url = slotMetaPath(gameName: gameName, systemID: systemID, slot: slot)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
    }

    func deleteState(gameName: String, systemID: String, slot: Int) throws {
        let statePath = self.statePath(gameName: gameName, systemID: systemID, slot: slot)
        let thumbPath = self.thumbnailPath(gameName: gameName, systemID: systemID, slot: slot)
        
        let fm = FileManager.default
        if fm.fileExists(atPath: statePath.path) {
            try fm.removeItem(at: statePath)
        }
        if fm.fileExists(atPath: thumbPath.path) {
            try fm.removeItem(at: thumbPath)
        }
        // Clear any user-defined display name so the slot returns to "Slot N".
        clearSlotMeta(gameName: gameName, systemID: systemID, slot: slot)
    }
    
    // Deletes a slot AND all its progressive versions and thumbnails
    func deleteSlotWithProgressives(gameName: String, systemID: String, slot: Int) throws {
        try deleteState(gameName: gameName, systemID: systemID, slot: slot)
        let versions = progressiveSlotVersions(gameName: gameName, systemID: systemID, slot: slot)
        for v in versions {
            try deleteProgressiveState(gameName: gameName, systemID: systemID, slot: slot, version: v)
        }
    }

    func deleteAllStates(gameName: String, systemID: String) throws {
        let sysDir = systemDirectory(systemID: systemID)
        let safeName = safeGameStateName(gameName)
        
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(atPath: sysDir.path)
        
        for item in contents {
            if item.hasPrefix("\(safeName)__") {
                let fileURL = sysDir.appendingPathComponent(item)
                try fm.removeItem(at: fileURL)
            }
        }
    }

    func deleteAllSaveFiles(gameName: String) throws -> Int {
        let savefilesDir = SaveDirectoryManager.shared.savefilesDirectory
        let fm = FileManager.default
        var deletedCount = 0
        let safeName = safeGameStateName(gameName).lowercased()

        guard let files = try? fm.contentsOfDirectory(atPath: savefilesDir.path) else { return 0 }

        for file in files {
            let baseName = (file as NSString).deletingPathExtension.lowercased()
            if baseName == gameName.lowercased() || baseName == safeName {
                let fileURL = savefilesDir.appendingPathComponent(file)
                try fm.removeItem(at: fileURL)
                deletedCount += 1
            }
        }
        return deletedCount
    }
    
    // Returns total size of all save states on disk (in bytes)
    func totalDiskUsage() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: savesDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    // MARK: - Thumbnail Operations
    
    // Save a thumbnail image for a save state slot
    // - Parameters:
    //   - image: The NSImage to save as thumbnail
    //   - gameName: The display name of the game
    //   - systemID: The system identifier
    //   - slot: Slot number
    func saveThumbnail(_ image: NSImage, gameName: String, systemID: String, slot: Int) {
        let thumbURL = thumbnailPath(gameName: gameName, systemID: systemID, slot: slot)
        #if LOG_DEBUG
        LoggerService.debug(category: "SaveStateManager", "Saving thumbnail: gameName='\(gameName)', systemID='\(systemID)', slot=\(slot), path: \(thumbURL.path)")
        #endif
        
        // Downscale to 320x240 for consistent thumbnails
        let targetSize = NSSize(width: 320, height: 240)
        
        // Create scaled image manually since extension may not be visible
        let scaledImage = NSImage(size: targetSize)
        scaledImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        scaledImage.unlockFocus()
        
        // Convert to PNG data using CGImageDestination (more reliable than NSBitmapImageRep)
        guard let cgImage = scaledImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            LoggerService.info(category: "SaveStateManager", "ERROR: Could not get CGImage from NSImage")
            return
        }
        
        guard let destination = CGImageDestinationCreateWithURL(
            thumbURL as CFURL,
            "public.png" as CFString,  // UTType for PNG
            1,
            nil
        ) else {
            LoggerService.info(category: "SaveStateManager", "ERROR: Could not create CGImageDestination")
            return
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        if !CGImageDestinationFinalize(destination) {
            LoggerService.info(category: "SaveStateManager", "ERROR: Could not finalize PNG file")
            return
        }
        
        // Verify file was created
        guard FileManager.default.fileExists(atPath: thumbURL.path) else {
            #if LOG_DEBUG
            LoggerService.debug(category: "SaveStateManager", "ERROR: Thumbnail file was not created")
            #endif
            return
        }
    }
    
    // Load a thumbnail image for a save state slot
    // - Parameters:
    //   - gameName: The display name of the game
    //   - systemID: The system identifier
    //   - slot: Slot number
    // - Returns: The loaded NSImage, or nil if not found
    func loadThumbnail(gameName: String, systemID: String, slot: Int) -> NSImage? {
        let thumbURL = thumbnailPath(gameName: gameName, systemID: systemID, slot: slot)
        #if LOG_DEBUG
        LoggerService.debug(category: "SaveStateManager", "Loading thumbnail: gameName='\(gameName)', systemID='\(systemID)', slot=\(slot)")
        #endif
        
        // Also check what other files exist in the directory
        if !FileManager.default.fileExists(atPath: thumbURL.path) {
            let dir = thumbURL.deletingLastPathComponent()
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                #if LOG_DEBUG
                LoggerService.debug(category: "SaveStateManager", "Thumbnail not found, directory contents: \(contents)")
                #endif
            }
        }
        
        guard FileManager.default.fileExists(atPath: thumbURL.path) else { return nil }
        return NSImage(contentsOf: thumbURL)
    }
    
    // Delete a thumbnail for a save state slot
    func deleteThumbnail(gameName: String, systemID: String, slot: Int) throws {
        let thumbURL = thumbnailPath(gameName: gameName, systemID: systemID, slot: slot)
        if FileManager.default.fileExists(atPath: thumbURL.path) {
            try FileManager.default.removeItem(at: thumbURL)
        }
    }
    
    // MARK: - Helpers
    
    // Sanitize game name to be filesystem-safe
    func safeGameStateName(_ name: String) -> String {
        // Remove dangerous characters and use a consistent format
        let sanitized = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "..", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "unknown" : sanitized
    }
    
    // Sanitize a path component
    private func safePathComponent(_ s: String) -> String {
        return safeGameStateName(s)
    }
    
    // MARK: - Progressive Save Support

// Returns the path for a progressive (versioned) save state
func progressiveStatePath(gameName: String, systemID: String, slot: Int, version: Int) -> URL {
    let sysDir = systemDirectory(systemID: systemID)
    let safeName = safeGameStateName(gameName)
    if slot == -1 {
        return sysDir.appendingPathComponent("\(safeName)__autosave__v\(version)")
    } else {
        return sysDir.appendingPathComponent("\(safeName)__slot_\(slot)__v\(version)")
    }
}

func progressiveThumbnailPath(gameName: String, systemID: String, slot: Int, version: Int) -> URL {
    progressiveStatePath(gameName: gameName, systemID: systemID, slot: slot, version: version).appendingPathExtension("png")
}

    // Rotates progressive versions and returns 1 (always the newest slot).
    // Before saving, shifts: N → N+1 (e.g. 2→3, 1→2), deletes the oldest (slotCount).
    // After rotation, versions 1=newest, 2=middle, 3=oldest, etc.
    func rotateProgressiveVersions(gameName: String, systemID: String, slot: Int, slotCount: Int) -> Int {
        let existing = progressiveSlotVersions(gameName: gameName, systemID: systemID, slot: slot)
        if existing.isEmpty {
            return 1
        }

        let fm = FileManager.default

        // If not all slots filled yet, just use the next empty one
        let nextEmptySlot = (1...slotCount).first { !existing.contains($0) }
        if let next = nextEmptySlot {
            return next
        }

        // All slots filled — rotate: delete highest, shift each remaining up by 1
        // Delete the oldest (slotCount) and its thumbnail
        let oldestState = progressiveStatePath(gameName: gameName, systemID: systemID, slot: slot, version: slotCount)
        let oldestThumb = progressiveThumbnailPath(gameName: gameName, systemID: systemID, slot: slot, version: slotCount)
        try? fm.removeItem(at: oldestState)
        try? fm.removeItem(at: oldestThumb)

        // Shift versions down from (slotCount-1) to 1, renaming each to version+1
        for v in (1..<(slotCount)).reversed() {
            let srcState = progressiveStatePath(gameName: gameName, systemID: systemID, slot: slot, version: v)
            let dstState = progressiveStatePath(gameName: gameName, systemID: systemID, slot: slot, version: v + 1)
            let srcThumb = progressiveThumbnailPath(gameName: gameName, systemID: systemID, slot: slot, version: v)
            let dstThumb = progressiveThumbnailPath(gameName: gameName, systemID: systemID, slot: slot, version: v + 1)

            if fm.fileExists(atPath: srcState.path) {
                try? fm.moveItem(at: srcState, to: dstState)
            }
            if fm.fileExists(atPath: srcThumb.path) {
                try? fm.moveItem(at: srcThumb, to: dstThumb)
            }
        }

        return 1
    }

func progressiveSlotVersions(gameName: String, systemID: String, slot: Int) -> [Int] {
    let sysDir = systemDirectory(systemID: systemID)
    let safeName = safeGameStateName(gameName)
    let prefix: String
    if slot == -1 {
        prefix = "\(safeName)__autosave__v"
    } else {
        prefix = "\(safeName)__slot_\(slot)__v"
    }
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: sysDir.path) else {
        return []
    }
    return contents.compactMap { file in
        guard file.hasPrefix(prefix) else { return nil }
        let versionStr = file.dropFirst(prefix.count)
        return Int(versionStr)
    }.sorted()
}

// Slot info for a progressive version
    func progressiveSlotInfo(gameName: String, systemID: String, slot: Int, version: Int) -> SlotInfo {
        let path = progressiveStatePath(gameName: gameName, systemID: systemID, slot: slot, version: version)
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path.path) else {
            return SlotInfo(id: slot, exists: false, fileSize: nil, modificationDate: nil, progressiveVersion: nil, customName: nil)
        }
        return SlotInfo(
            id: slot,
            exists: true,
            fileSize: attrs[.size] as? Int64,
            modificationDate: attrs[.modificationDate] as? Date,
            progressiveVersion: version,
            customName: nil
        )
    }

// Save a thumbnail for a progressive version
func saveProgressiveThumbnail(image: NSImage, gameName: String, systemID: String, slot: Int, version: Int) {
    let thumbURL = progressiveThumbnailPath(gameName: gameName, systemID: systemID, slot: slot, version: version)
    let targetSize = NSSize(width: 320, height: 240)
    let scaledImage = NSImage(size: targetSize)
    scaledImage.lockFocus()
    image.draw(
        in: NSRect(origin: .zero, size: targetSize),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1.0
    )
    scaledImage.unlockFocus()
    guard let cgImage = scaledImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        LoggerService.info(category: "SaveStateManager", "ERROR: Could not get CGImage for progressive thumbnail")
        return
    }
    guard let destination = CGImageDestinationCreateWithURL(thumbURL as CFURL, "public.png" as CFString, 1, nil) else {
        LoggerService.info(category: "SaveStateManager", "ERROR: Could not create CGImageDestination for progressive thumbnail")
        return
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    CGImageDestinationFinalize(destination)
}

// Load a progressive version thumbnail
func loadProgressiveThumbnail(gameName: String, systemID: String, slot: Int, version: Int) -> NSImage? {
    let thumbURL = progressiveThumbnailPath(gameName: gameName, systemID: systemID, slot: slot, version: version)
    guard FileManager.default.fileExists(atPath: thumbURL.path) else { return nil }
    return NSImage(contentsOf: thumbURL)
}

// Delete a progressive save state and its thumbnail
func deleteProgressiveState(gameName: String, systemID: String, slot: Int, version: Int) throws {
    let statePath = progressiveStatePath(gameName: gameName, systemID: systemID, slot: slot, version: version)
    let thumbPath = progressiveThumbnailPath(gameName: gameName, systemID: systemID, slot: slot, version: version)
    let fm = FileManager.default
    if fm.fileExists(atPath: statePath.path) {
        try fm.removeItem(at: statePath)
    }
    if fm.fileExists(atPath: thumbPath.path) {
        try fm.removeItem(at: thumbPath)
    }
    // If this was the last version AND no base .state remains, also clear any
    // user-defined slot name so the slot label reverts to "Slot N".
    if progressiveSlotVersions(gameName: gameName, systemID: systemID, slot: slot).isEmpty
        && !fm.fileExists(atPath: self.statePath(gameName: gameName, systemID: systemID, slot: slot).path) {
        clearSlotMeta(gameName: gameName, systemID: systemID, slot: slot)
    }
}

// Returns all progressive versions for a game, grouped by slot
func allProgressiveSlots(gameName: String, systemID: String) -> [Int: [SlotInfo]] {
    var result: [Int: [SlotInfo]] = [:]
    // Check slots -1 through 9
    for slot in (-1...9) {
        let versions = progressiveSlotVersions(gameName: gameName, systemID: systemID, slot: slot)
        if !versions.isEmpty {
            result[slot] = versions.map { progressiveSlotInfo(gameName: gameName, systemID: systemID, slot: slot, version: $0) }
        }
    }
    return result
}

// MARK: - Save Discovery

// Extract game name from a save state filename
private func extractGameName(from stateFile: String) -> String {
    let patterns = [
        try! NSRegularExpression(pattern: "__autosave__v\\d+$"),
        try! NSRegularExpression(pattern: "__slot_\\d+__v\\d+$"),
        try! NSRegularExpression(pattern: "__slot_\\d+$"),
        try! NSRegularExpression(pattern: "__autosave$"),
    ]
    var name = stateFile
    for pattern in patterns {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        if let match = pattern.firstMatch(in: name, range: range) {
            name = String(name[..<Range(match.range, in: name)!.lowerBound])
            break
        }
    }
    return name
}

// Returns all system directories that contain save states
func systemsWithSaves() -> [String] {
    guard let systemDirs = try? FileManager.default.contentsOfDirectory(
        at: savesDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else { return [] }
    return systemDirs
        .filter { $0.hasDirectoryPath }
        .map { $0.lastPathComponent }
        .sorted()
}

// Returns all distinct game names that have saves in a given system
func gamesWithSaves(inSystem systemID: String) -> [String] {
    let sysDir = systemDirectory(systemID: systemID)
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: sysDir.path) else { return [] }
    let stateFiles = files.filter { f in
        guard !f.hasSuffix(".png") else { return false }
        return f.contains("__autosave") || f.contains("__slot_")
    }
    return Array(Set(stateFiles.map { extractGameName(from: $0) })).sorted()
}

// All save-related files for a given game in a system (state files + save files)
func allFilesForGame(gameName: String, systemID: String) -> ([SlotInfo], [URL]) {
    let sysDir = systemDirectory(systemID: systemID)
    let safeName = safeGameStateName(gameName)

    // Collect all state files including progressive versions
    var stateSlots: [SlotInfo] = []
    if let files = try? FileManager.default.contentsOfDirectory(atPath: sysDir.path) {
        let stateFiles = files.filter { f in
            guard !f.hasSuffix(".png") else { return false }
            return f.hasPrefix("\(safeName)__autosave") || f.hasPrefix("\(safeName)__slot_")
        }
        for file in stateFiles {
            let fileURL = sysDir.appendingPathComponent(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
                let slot: Int
                if file.hasPrefix("\(safeName)__autosave") {
                    slot = -1
                } else if let slotRange = file.range(of: "__slot_") {
                    let afterSlot = file[slotRange.upperBound...]
                    let digits = afterSlot.prefix(while: { $0.isNumber })
                    slot = Int(digits) ?? 0
                } else {
                    slot = 0
                }
                stateSlots.append(SlotInfo(
                    id: slot,
                    exists: true,
                    fileSize: attrs[.size] as? Int64,
                    modificationDate: attrs[.modificationDate] as? Date,
                    progressiveVersion: nil
                ))
            }
        }
    }

    // Collect SRAM save files
    var saveFiles: [URL] = []
    let savefilesDir = SaveDirectoryManager.shared.savefilesDirectory
    if let files = try? FileManager.default.contentsOfDirectory(atPath: savefilesDir.path) {
        let rawName = gameName  // SRAM files use the filename-based name
        for file in files {
            let baseName = (file as NSString).deletingPathExtension
            if baseName == rawName || baseName.lowercased() == rawName.lowercased() {
                saveFiles.append(savefilesDir.appendingPathComponent(file))
            }
        }
    }

    return (stateSlots, saveFiles)
}

// MARK: - Compression Utilities
    
    // Compressed save state format:
    // - Bytes 0-3: Magic header "TCS2" (TruChie State v2)
    // - Bytes 4-7: Original uncompressed size (UInt32, little-endian)
    // - Bytes 8+:  LZ4 compressed data
    private static let compressedMagicHeader: [UInt8] = [0x54, 0x43, 0x53, 0x32] // "TCS2"
    
    // Compress state data using LZ4 compression
    // - Parameter data: Raw state data
    // - Returns: Compressed data with magic header prefix, or raw data if compression fails
    static func compressStateData(_ data: Data) -> Data? {
        let algorithm = COMPRESSION_LZ4_RAW
        
        // Use NSData compression via compression_stream
        let sourceBuffer = [UInt8](data)
        let sourceSize = sourceBuffer.count
        
        // Allocate scratch buffer
        let scratchSize = compression_encode_scratch_buffer_size(algorithm)
        let destSize = sourceSize + scratchSize
        var destBuffer = [UInt8](repeating: 0, count: destSize)
        
        let compressedSize = sourceBuffer.withUnsafeBufferPointer { srcBuf in
            return destBuffer.withUnsafeMutableBufferPointer { destBuf in
                return compression_encode_buffer(
                    destBuf.baseAddress!, destSize,
                    srcBuf.baseAddress!, sourceSize,
                    nil,
                    algorithm
                )
            }
        }
        
        guard compressedSize > 0 && compressedSize < sourceSize else {
            return data
        }
        
        // Build result: magic (4) + original size (4) + compressed data
        var result = Data(compressedMagicHeader)
        // Store original size as UInt32 little-endian
        let sizeBytes = withUnsafeBytes(of: UInt32(sourceSize).littleEndian) { Array($0) }
        result.append(contentsOf: sizeBytes)
        result.append(Data(destBuffer.prefix(compressedSize)))
        return result
    }
    
    // Decompress state data
    // - Parameter data: Compressed or raw state data
    // - Returns: Decompressed data, or nil on failure
    static func decompressStateData(_ data: Data) -> Data? {
        let headerSize = 8  // 4 bytes magic + 4 bytes original size
        guard data.count >= headerSize else {
            // Too small to be compressed - return as-is (might be raw data)
            return data
        }
        
        let headerBytes = [UInt8](data.prefix(4))
        let isCompressed = headerBytes.elementsEqual(compressedMagicHeader)
        
        if isCompressed {
            // Read original size from bytes 4-7
            let sizeBytes = [UInt8](data.subdata(in: 4..<8))
            let originalSize = sizeBytes.withUnsafeBytes { ptr in
                ptr.load(as: UInt32.self).littleEndian
            }
            
            let compressedData = [UInt8](data.dropFirst(headerSize))
            let compressedSize = compressedData.count
            let algorithm = COMPRESSION_LZ4_RAW
            
            // Allocate buffer with exact original size
            var destBuffer = [UInt8](repeating: 0, count: Int(originalSize))
            
            let decompressedSize = compressedData.withUnsafeBufferPointer { srcBuf in
                return destBuffer.withUnsafeMutableBufferPointer { destBuf in
                    return compression_decode_buffer(
                        destBuf.baseAddress!, Int(originalSize),
                        srcBuf.baseAddress!, compressedSize,
                        nil,
                        algorithm
                    )
                }
            }
            
            guard decompressedSize > 0 else {
                LoggerService.info(category: "SaveStateManager", "ERROR: Decompression failed (got \(decompressedSize) bytes)")
                return nil
            }
            
            return Data(destBuffer.prefix(decompressedSize))
        } else {
            // Not compressed (raw state data or old format without header)
            return data
        }
    }
}

// MARK: - Human-readable file size

extension Int64 {
    // Format bytes as a human-readable string (e.g., "15.2 MB")
    var formattedByteSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}

// MARK: - SlotInfo date formatting helper

extension SlotInfo {
    // Formatted modification date string for UI display
    var formattedDate: String? {
        guard let date = modificationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}