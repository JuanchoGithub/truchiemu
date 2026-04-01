import Foundation
import os.log

private let cheatLoaderLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "CheatAutoLoader")

// MARK: - Cheat Auto-Loader

/// Automatically loads cheat files for a ROM when a game is launched.
/// Searches multiple directories for matching .cht files.
class CheatAutoLoader {
    
    // MARK: - Cheat Search Directories
    
    /// Directory for system-wide cheats
    static var systemCheatsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchieEmu/cheats")
    }
    
    /// Get the cheats directory for a specific system
    static func systemCheatsDirectory(for systemID: String) -> URL {
        systemCheatsDirectory.appendingPathComponent(systemID)
    }
    
    // MARK: - Auto-Loading
    
    /// Find and load cheats for a given ROM.
    /// Returns an array of Cheat objects.
    @MainActor
    static func loadCheats(for rom: ROM) -> [Cheat] {
        var allCheats: [Cheat] = []
        
        let systemID = rom.systemID ?? "unknown"
        let romFilename = rom.path.deletingPathExtension().lastPathComponent
        
        // Priority 1: Cheats alongside ROM file
        if let romFolderCheats = loadFromSameFolderAsROM(rom: rom) {
            allCheats.append(contentsOf: romFolderCheats)
        }
        
        // Priority 2: System cheats directory
        let systemDir = systemCheatsDirectory(for: systemID)
        if let systemCheats = loadFromSystemDirectory(directory: systemDir, filename: romFilename) {
            allCheats.append(contentsOf: systemCheats)
        }
        
        // Priority 3: Global cheats directory
        if let globalCheats = loadFromSystemDirectory(directory: systemCheatsDirectory, filename: romFilename) {
            allCheats.append(contentsOf: globalCheats)
        }
        
        // Merge duplicates (prefer later sources)
        allCheats = mergeCheats(allCheats)
        
        cheatLoaderLog.info("Loaded \(allCheats.count) cheats for \(rom.displayName)")
        
        return allCheats
    }
    
    /// Load cheats from .cht files alongside the ROM file.
    private static func loadFromSameFolderAsROM(rom: ROM) -> [Cheat]? {
        let folder = rom.path.deletingLastPathComponent()
        let romFilename = rom.path.deletingPathExtension().lastPathComponent
        
        // Look for: <romname>.cht
        let chtPath = folder.appendingPathComponent("\(romFilename).cht")
        
        if let cheats = loadCheatFile(chtPath, source: .autoDetected) {
            cheatLoaderLog.info("Found cheats in ROM folder: \(chtPath.path)")
            return cheats
        }
        
        return nil
    }
    
    /// Load cheats from a system/global cheats directory.
    private static func loadFromSystemDirectory(directory: URL, filename: String) -> [Cheat]? {
        let chtPath = directory.appendingPathComponent("\(filename).cht")
        
        if let cheats = loadCheatFile(chtPath, source: .libretroDatabase) {
            cheatLoaderLog.info("Found cheats in system directory: \(chtPath.path)")
            return cheats
        }
        
        return nil
    }
    
    /// Load and parse a single .cht file if it exists.
    private static func loadCheatFile(_ url: URL, source: CheatSource) -> [Cheat]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        guard let cheats = CheatParser.parseChtFile(url: url) else {
            cheatLoaderLog.error("Failed to parse cheat file: \(url.path)")
            return nil
        }
        
        return cheats
    }
    
    // MARK: - Merge Logic
    
    /// Merge cheats from multiple sources, deduplicating by index.
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
    
    /// Ensure cheat directories exist.
    static func ensureDirectoriesExist() {
        let directories = [systemCheatsDirectory] + SystemDatabase.systems.map { systemCheatsDirectory(for: $0.id) }
        
        for dir in directories {
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) || !isDir.boolValue {
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    cheatLoaderLog.info("Created cheat directory: \(dir.path)")
                } catch {
                    cheatLoaderLog.error("Failed to create cheat directory: \(dir.path) - \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Cheat Discovery
    
    /// Find all available .cht files for a ROM.
    static func findAvailableCheatFiles(for rom: ROM) -> [URL] {
        var found: [URL] = []
        
        let systemID = rom.systemID ?? "unknown"
        let romFilename = rom.path.deletingPathExtension().lastPathComponent
        
        // Same folder as ROM
        let folder = rom.path.deletingLastPathComponent()
        let romFolderCht = folder.appendingPathComponent("\(romFilename).cht")
        if FileManager.default.fileExists(atPath: romFolderCht.path) {
            found.append(romFolderCht)
        }
        
        // System directory
        let systemDir = systemCheatsDirectory(for: systemID)
        let systemCht = systemDir.appendingPathComponent("\(romFilename).cht")
        if FileManager.default.fileExists(atPath: systemCht.path) {
            found.append(systemCht)
        }
        
        // Global directory
        let globalCht = systemCheatsDirectory.appendingPathComponent("\(romFilename).cht")
        if FileManager.default.fileExists(atPath: globalCht.path) {
            found.append(globalCht)
        }
        
        return found
    }
}