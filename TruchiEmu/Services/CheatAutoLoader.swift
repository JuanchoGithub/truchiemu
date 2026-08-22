import Foundation

// MARK: - Cheat Auto-Loader

// Automatically loads cheat files for a ROM when a game is launched.
// Searches multiple directories for matching .cht files.
class CheatAutoLoader {
    
    // MARK: - Cheat Search Directories
    
    // Directory for system-wide cheats
    static var systemCheatsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchiEmu/cheats")
    }
    
    // Directory for downloaded cheats (from libretro database)
    static var downloadedCheatsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchiEmu/cheats_downloaded")
    }
    
    // Get the cheats directory for a specific system
    static func systemCheatsDirectory(for systemID: String) -> URL {
        systemCheatsDirectory.appendingPathComponent(systemID)
    }
    
    // Get the downloaded cheats directory for a specific system
    static func downloadedCheatsDirectory(for systemID: String) -> URL {
        downloadedCheatsDirectory.appendingPathComponent(systemID)
    }
    
    // MARK: - Auto-Loading
    
    // Build list of possible cheat filenames for a ROM (includes filename, metadata title, and display name).
    static func possibleFilenames(for rom: ROM) -> [String] {
        var names: [String] = []
        
        // 1. ROM filename without extension
        let romFilename = rom.path.deletingPathExtension().lastPathComponent
        names.append(romFilename)
        
        // 2. ROM metadata title (from No-Intro DAT, e.g. "Super Mario Bros. 3 (USA) (Rev 1)")
        if let datTitle = rom.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !datTitle.isEmpty {
            // Only add if different from romFilename
            if datTitle != romFilename {
                names.append(datTitle)
            }
        }
        
        // 3. Display name (custom name or metadata title or name)
        let displayName = rom.displayName
        if !names.contains(displayName) && displayName != romFilename {
            names.append(displayName)
        }
        
        LoggerService.info(category: "CheatAutoLoader", "Possible cheat filenames: \(names)")
        return names
    }
    
    // Find and load cheats for a given ROM.
    // Returns an array of Cheat objects.
    @MainActor
    static func loadCheats(for rom: ROM) -> [Cheat] {
        var allCheats: [Cheat] = []
        let systemID = rom.systemID ?? "unknown"
        let possibleNames = possibleFilenames(for: rom)
        
        // Helper to try loading a cheat file
        func tryLoadFromDirectory(directory: URL, names: [String], label: String, source: CheatSource) -> [Cheat]? {
            for name in names {
                let chtPath = directory.appendingPathComponent("\(name).cht")
                let exists = FileManager.default.fileExists(atPath: chtPath.path)
                LoggerService.info(category: "CheatAutoLoader", "\(label) '\(name)': \(chtPath.path) \(exists ? "EXISTS" : "not found")")
                if exists, let cheats = loadCheatFile(chtPath, source: source) {
                    LoggerService.info(category: "CheatAutoLoader", "Found cheats via \(label) '\(name)': \(chtPath.path)")
                    return cheats
                }
            }
            return nil
        }
        
        // Priority 1: Cheats alongside ROM file
        let romFolder = rom.path.deletingLastPathComponent()
        for name in possibleNames {
            let chtPath = romFolder.appendingPathComponent("\(name).cht")
            let exists = FileManager.default.fileExists(atPath: chtPath.path)
            LoggerService.info(category: "CheatAutoLoader", "P1 ROM folder '\(name)': \(chtPath.path) \(exists ? "EXISTS" : "not found")")
            if exists, let cheats = loadCheatFile(chtPath, source: .autoDetected) {
                LoggerService.info(category: "CheatAutoLoader", "Found cheats in ROM folder: \(chtPath.path)")
                allCheats.append(contentsOf: cheats)
                break
            }
        }
        
// Priority 2: Downloaded cheats directory (system-specific) - loaded first, lower priority
        let downloadedDir = downloadedCheatsDirectory(for: systemID)
        if let dlCheats = tryLoadFromDirectory(directory: downloadedDir, names: possibleNames, label: "P2 Downloaded cheats", source: .libretroDatabase) {
            allCheats.append(contentsOf: dlCheats)
        }

        // Priority 3: System cheats directory (custom user cheats) - loaded second, higher priority
        let systemDir = systemCheatsDirectory(for: systemID)
        if let sysCheats = tryLoadFromDirectory(directory: systemDir, names: possibleNames, label: "P3 Custom cheats", source: .libretroDatabase) {
            allCheats.append(contentsOf: sysCheats)
        }

        // Priority 4: Global downloaded cheats directory
        if let globalDlCheats = tryLoadFromDirectory(directory: downloadedCheatsDirectory, names: possibleNames, label: "P4 Global downloaded", source: .libretroDatabase) {
            allCheats.append(contentsOf: globalDlCheats)
        }

        // Priority 5: Global cheats directory (global custom cheats)
        if let globalCheats = tryLoadFromDirectory(directory: systemCheatsDirectory, names: possibleNames, label: "P5 Global custom", source: .libretroDatabase) {
            allCheats.append(contentsOf: globalCheats)
        }
        
        // Merge duplicates (prefer later sources)
        allCheats = mergeCheats(allCheats)
        
        LoggerService.info(category: "CheatAutoLoader", "Loaded \(allCheats.count) cheats for \(rom.displayName) [systemID=\(systemID), names=\(possibleNames)]")
        
        return allCheats
    }
    
    // Load and parse a single .cht file if it exists.
    private static func loadCheatFile(_ url: URL, source: CheatSource) -> [Cheat]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        guard let cheats = CheatParser.parseChtFile(url: url) else {
            LoggerService.error(category: "CheatAutoLoader", "Failed to parse cheat file: \(url.path)")
            return nil
        }
        
        return cheats
    }
    
    // MARK: - Merge Logic
    
    // Merge cheats from multiple sources, deduplicating by index.
    private static func mergeCheats(_ allCheats: [Cheat]) -> [Cheat] {
        var cheatByIndex: [Int: Cheat] = [:]
        
        // Later sources override earlier ones
        for cheat in allCheats {
            if let existing = cheatByIndex[cheat.index] {
                // Keep the one with a description if the other doesn't have one
                let shouldReplace = !cheat.description.isEmpty && existing.description.isEmpty
                if shouldReplace {
                    cheatByIndex[cheat.index] = cheat
                }
            } else {
                cheatByIndex[cheat.index] = cheat
            }
        }
        
        // Sort by index
        return cheatByIndex.values.sorted { $0.index < $1.index }
    }
    
    // MARK: - Directory Setup
    
    // Ensure cheat directories exist.
    static func ensureDirectoriesExist() {
        let directories = [systemCheatsDirectory, downloadedCheatsDirectory] 
            + SystemDatabase.systems.map { systemCheatsDirectory(for: $0.id) }
            + SystemDatabase.systems.map { downloadedCheatsDirectory(for: $0.id) }
        
        for dir in directories {
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) || !isDir.boolValue {
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    LoggerService.info(category: "CheatAutoLoader", "Created cheat directory: \(dir.path)")
                } catch {
                    LoggerService.error(category: "CheatAutoLoader", "Failed to create cheat directory: \(dir.path) - \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Cheat Discovery
    
    // Save cheats to the custom cheats directory (cheats/{systemID}/{romName}.cht)
    // Saves to ALL possible filenames so they match on next load
    static func saveCustomCheats(_ cheats: [Cheat], for rom: ROM) -> Bool {
        let systemID = rom.systemID ?? "unknown"
        let possibleNames = possibleFilenames(for: rom)
        
        let customDir = systemCheatsDirectory(for: systemID)
        
        // Ensure directory exists
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: customDir.path, isDirectory: &isDir) || !isDir.boolValue {
            do {
                try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
            } catch {
                LoggerService.error(category: "CheatAutoLoader", "Failed to create custom cheats directory: \(error.localizedDescription)")
                return false
            }
        }
        
        // Save under the canonical ROM filename. loadCheatsForROM resolves the
        // same possibleFilenames set, so a single stable name is sufficient.
        guard let name = possibleNames.first else { return false }
        let chtPath = customDir.appendingPathComponent("\(name).cht")
        return saveCheatsToFile(cheats, url: chtPath)
    }
    
    // Save cheats to a specific .cht file
    private static func saveCheatsToFile(_ cheats: [Cheat], url: URL) -> Bool {
        var content = "cheats = \(cheats.count)\n\n"
        
        for (index, cheat) in cheats.enumerated() {
            content += "cheat\(index)_desc = \"\(cheat.description)\"\n"
            content += "cheat\(index)_code = \"\(cheat.code)\"\n"
            content += "cheat\(index)_enable = \(cheat.enabled ? "true" : "false")\n"
            content += "cheat\(index)_type = \"\(cheat.format.displayName)\"\n"
            content += "\n"
        }
        
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            LoggerService.info(category: "CheatAutoLoader", "Saved \(cheats.count) cheats to: \(url.path)")
            return true
        } catch {
            LoggerService.error(category: "CheatAutoLoader", "Failed to save cheats to \(url.path): \(error.localizedDescription)")
            return false
        }
    }
    
    // Find all available .cht files for a ROM (searching multiple filename variants).
    static func findAvailableCheatFiles(for rom: ROM) -> [URL] {
        var found: [URL] = []
        let systemID = rom.systemID ?? "unknown"
        let possibleNames = possibleFilenames(for: rom)
        
        func findInDirectory(_ directory: URL) {
            for name in possibleNames {
                let chtPath = directory.appendingPathComponent("\(name).cht")
                if FileManager.default.fileExists(atPath: chtPath.path), !found.contains(chtPath) {
                    found.append(chtPath)
                }
            }
        }
        
        // Same folder as ROM
        let romFolder = rom.path.deletingLastPathComponent()
        findInDirectory(romFolder)
        
        // System directory
        findInDirectory(systemCheatsDirectory(for: systemID))
        
        // Downloaded cheats directory (system-specific)
        findInDirectory(downloadedCheatsDirectory(for: systemID))
        
        // Global directory
        findInDirectory(systemCheatsDirectory)
        
        // Global downloaded cheats directory
        findInDirectory(downloadedCheatsDirectory)
        
        return found
    }
}
