import Foundation
import MetalKit

// MARK: - ScummVM Cache Manager (static, called from ROMLibrary)

/// Shared cache manager for ScummVM extracted files.
/// Provides static methods for cleanup that can be called during library scanning.
enum ScummVMCacheManager {
    
    /// Directory where extracted ScummVM games are stored
    static var scummVMDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchieEmu/ScummVMExtracted")
    }
    
    /// Clean up extracted ScummVM folders whose source ZIP files no longer exist in the library.
    /// - Parameter activeScummvmPaths: Set of paths for ScummVM ZIP files currently in the library.
    static func cleanupOrphanedCaches(activeScummvmPaths: Set<String>) {
        let fm = FileManager.default
        guard let extractedFolders = try? fm.contentsOfDirectory(at: scummVMDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for folder in extractedFolders {
            // The extraction folder name is derived from the original ZIP filename
            // e.g., "Day Of The Tentacle (CD Dos).zip" -> "Day Of The Tentacle (CD Dos)"
            // We need to check if any active ScummVM path's base filename (without extension)
            // matches this folder name
            
            let folderName = folder.lastPathComponent
            let isActive = activeScummvmPaths.contains { romPath in
                let zipName = URL(fileURLWithPath: romPath).deletingPathExtension().lastPathComponent
                return zipName == folderName
            }
            
            if !isActive {
                print("[ScummVMCache] Removing orphaned cache: \(folder.path)")
                try? fm.removeItem(at: folder)
            }
        }
    }
}

/// ScummVM-specific emulator runner that handles ZIP files by:
/// 1. Extracting the ZIP to a cache directory
/// 2. Detecting the game ID from filenames
/// 3. Generating a .scummvm hook file
/// 4. Passing the .scummvm file to the core instead of the ZIP
class ScummVMRunner: EmulatorRunner {
    
    // MARK: - Game ID Detection Patterns
    
    /// Known ScummVM game file patterns - maps distinctive files to game IDs
    static let gameFilePatterns: [(pattern: String, gameID: String)] = [
        // LucasArts games
        ("TENTACLE", "tentacle"),           // Day of the Tentacle
        ("TENTACLE.", "tentacle"),
        ("SAMN", "samnmax"),                // Sam & Max Hit the Road
        ("SAMNMAX", "samnmax"),
        ("MONKEY", "monkey"),               // The Secret of Monkey Island
        ("MONKEY2", "monkey2"),             // Monkey Island 2
        ("COMI", "comi"),                   // Curse of Monkey Island
        ("INDY3", "indy3"),                 // Indiana Jones and the Last Crusade
        ("INDYLALA", "indy4"),              // Indiana Jones and the Fate of Atlantis
        ("LOOM", "loom"),
        ("ZAK", "zak25"),                   // Zak McKracken and the Alien Mindbenders
        ("MANIAC", "maniac"),               // Maniac Mansion
        
        // Sierra games
        ("SIERRA", "sierra"),
        ("QFG1", "qfg1"),                   // Quest for Glory 1
        ("QFG2", "qfg2"),                   // Quest for Glory 2
        ("KQ1", "kq1"),                     // King's Quest 1
        ("KQ2", "kq2"),                     // King's Quest 2
        ("KQ3", "kq3"),                     // King's Quest 3
        ("KQ4", "kq4"),                     // King's Quest 4
        ("KQ5", "kq5"),                     // King's Quest 5
        ("KQ6", "kq6"),                     // King's Quest 6
        ("KQ7", "kq7"),                     // King's Quest 7
        ("SQ1", "sq1"),                     // Space Quest 1
        ("SQ2", "sq2"),                     // Space Quest 2
        ("SQ3", "sq3"),                     // Space Quest 3
        ("SQ4", "sq4"),                     // Space Quest 4
        ("SQ5", "sq5"),                     // Space Quest 5
        ("SQ6", "sq6"),                     // Space Quest 6
        ("LH1", "lh1"),                     // Leisure Suit Larry 1
        ("LH2", "lh2"),                     // Leisure Suit Larry 2  
        ("LH3", "lh3"),                     // Leisure Suit Larry 3
        ("LH5", "lh5"),                     // Leisure Suit Larry 5
        ("LH6", "lh6"),                     // Leisure Suit Larry 6
        
        // Other classic games
        ("DIG", "dig"),                     // The Dig
        ("FULLTHROTTLE", "fullthrottle"),   // Full Throttle
        ("FT", "fullthrottle"),
        ("GROOVE", "groove"),               // Full Throttle (alternative)
        ("TOUCHE", "tuche"),                // Touche: The Adventures of the 5th Musketeer
    ]
    
    /// Audio file extensions that indicate ScummVM game data
    static let scummVMAudioExtensions: Set<String> = [
        "flac", "ogg", "wav", "mp3", "aif", "aiff"
    ]
    
    /// ScummVM-specific data file extensions
    static let scummVMDataExtensions: Set<String> = [
        "sou", "000", "001", "002", "003", "004", "005",
        "flc", "flx", "san", "bun", "ws6",
        "scr", "00", "lfl", "hex"
    ]
    
    // MARK: - Cache Management
    
    /// Directory where extracted ScummVM games are stored
    private var scummVMDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchieEmu/ScummVMExtracted")
    }
    
    /// Get the extracted game folder path for a given ZIP file
    private func extractedPath(for zipPath: URL) -> URL {
        let baseName = zipPath.deletingPathExtension().lastPathComponent
        return scummVMDirectory.appendingPathComponent(baseName)
    }
    
    /// Get the .scummvm hook file path for a given ZIP file
    private func hookFilePath(in gameFolder: URL) -> URL? {
        // Find the game ID first
        let gameID = detectGameID(in: gameFolder)
        if let gameID = gameID {
            return gameFolder.appendingPathComponent("\(gameID).scummvm")
        }
        return nil
    }
    
    // MARK: - ZIP Extraction
    
    /// Extract a ZIP file to the cache directory if not already extracted
    /// Returns the path to the extracted folder
    func extractIfNeeded(zipPath: URL) -> URL? {
        let destFolder = extractedPath(for: zipPath)
        
        // Check if already extracted
        if FileManager.default.fileExists(atPath: destFolder.path) {
            // Verify extraction is complete (has game files)
            if hasGameFiles(in: destFolder) {
                print("[ScummVM] Using cached extraction: \(destFolder.path)")
                return destFolder
            } else {
                // Corrupted or incomplete extraction, remove and re-extract
                try? FileManager.default.removeItem(at: destFolder)
            }
        }
        
        // Create destination folder
        do {
            try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        } catch {
            print("[ScummVM] Failed to create extraction directory: \(error)")
            return nil
        }
        
        // Extract using unzip (standard macOS utility)
        print("[ScummVM] Extracting ZIP to: \(destFolder.path)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipPath.path, "-d", destFolder.path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("[ScummVM] Extraction successful")
                return destFolder
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                print("[ScummVM] Extraction failed: \(errorMsg)")
                
                // Try alternative: use ditto
                print("[ScummVM] Trying ditto as fallback...")
                return extractWithDitto(zipPath: zipPath, destFolder: destFolder)
            }
        } catch {
            print("[ScummVM] Exception during extraction: \(error)")
            return extractWithDitto(zipPath: zipPath, destFolder: destFolder)
        }
    }
    
    /// Fallback extraction using ditto
    private func extractWithDitto(zipPath: URL, destFolder: URL) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", "--sequesterRsrc", zipPath.path, destFolder.path]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("[ScummVM] ditto extraction successful")
                return destFolder
            } else {
                print("[ScummVM] ditto extraction failed with status: \(process.terminationStatus)")
                return nil
            }
        } catch {
            print("[ScummVM] ditto extraction exception: \(error)")
            return nil
        }
    }
    
    // MARK: - Game ID Detection
    
    /// Detect the ScummVM game ID by scanning files in the extracted folder
    func detectGameID(in folder: URL) -> String? {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            
            // First pass: look for known game file patterns
            for file in files {
                let upperFile = file.uppercased()
                let nameWithoutExt = (upperFile as NSString).deletingPathExtension
                
                // Check against known patterns
                for (pattern, gameID) in Self.gameFilePatterns {
                    if nameWithoutExt == pattern || nameWithoutExt.hasPrefix(pattern + ".") {
                        print("[ScummVM] Detected game ID: \(gameID) from file: \(file)")
                        return gameID
                    }
                }
            }
            
            // Second pass: check for audio/data files to confirm it's ScummVM
            let hasAudioFiles = files.contains { file in
                let ext = (file as NSString).pathExtension.lowercased()
                return Self.scummVMAudioExtensions.contains(ext)
            }
            
            let hasDataFiles = files.contains { file in
                let ext = (file as NSString).pathExtension.lowercased()
                return Self.scummVMDataExtensions.contains(ext)
            }
            
            if hasAudioFiles || hasDataFiles {
                // We have ScummVM game files but couldn't detect specific game
                // Return "auto" to use fallback detection from the folder name
                print("[ScummVM] Detected ScummVM data files but no specific game ID")
            }
            
        } catch {
            print("[ScummVM] Failed to read extracted folder: \(error)")
        }
        
        // Fallback: derive game ID from the folder/ZIP name
        let folderName = (folder.lastPathComponent as NSString).deletingPathExtension
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        
        // Try to match from known patterns on the folder name
        for (pattern, gameID) in Self.gameFilePatterns {
            if folderName.contains(pattern.lowercased()) {
                print("[ScummVM] Detected game ID from folder name: \(gameID)")
                return gameID
            }
        }
        
        // Last resort: use a cleaned folder name as ID
        if !folderName.isEmpty && folderName.count > 2 {
            let cleanID = folderName
                .filter { $0.isLetter || $0.isNumber }
            if !cleanID.isEmpty {
                print("[ScummVM] Using fallback game ID: \(cleanID)")
                return cleanID
            }
        }
        
        print("[ScummVM] Could not detect game ID")
        return nil
    }
    
    // MARK: - Hook File Generation
    
    /// Create a .scummvm hook file in the game folder
    /// Returns the path to the hook file
    func createHookFile(in gameFolder: URL, gameID: String) -> URL? {
        let hookPath = gameFolder.appendingPathComponent("\(gameID).scummvm")
        
        // Check if hook file already exists
        if FileManager.default.fileExists(atPath: hookPath.path) {
            print("[ScummVM] Hook file already exists: \(hookPath.path)")
            return hookPath
        }
        
        // Create the hook file with the game ID as content
        do {
            try gameID.write(to: hookPath, atomically: true, encoding: .utf8)
            print("[ScummVM] Created hook file: \(hookPath.path)")
            return hookPath
        } catch {
            print("[ScummVM] Failed to create hook file: \(error)")
            return nil
        }
    }
    
    // MARK: - Game File Detection
    
    /// Check if a folder contains ScummVM game files
    func hasGameFiles(in folder: URL) -> Bool {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            
            for file in files {
                let ext = (file as NSString).pathExtension.lowercased()
                let upperName = file.uppercased()
                
                // Check for common game file indicators
                if Self.scummVMDataExtensions.contains(ext) {
                    return true
                }
                if Self.scummVMAudioExtensions.contains(ext) {
                    return true
                }
                
                // Check for known game files
                for (pattern, _) in Self.gameFilePatterns {
                    if upperName.contains(pattern) {
                        return true
                    }
                }
            }
        } catch {
            print("[ScummVM] Failed to check for game files: \(error)")
        }
        return false
    }
    
    // MARK: - Override Launch
    
    @MainActor
    override func launch(rom: ROM, coreID: String) {
        let romPath = rom.path
        let fileExt = romPath.pathExtension.lowercased()
        
        // Only handle ZIP files - pass through other formats directly
        if fileExt == "zip" {
            print("[ScummVM] Processing ZIP file: \(romPath.path)")
            
            // Step 1: Extract the ZIP
            guard let extractedFolder = extractIfNeeded(zipPath: romPath) else {
                print("[ScummVM-ERR] Failed to extract ZIP")
                return
            }
            
            // Step 2: Detect game ID
            guard let gameID = detectGameID(in: extractedFolder) else {
                print("[ScummVM-ERR] Could not detect game ID from extracted files")
                return
            }
            
            // Step 3: Create hook file
            guard let hookPath = createHookFile(in: extractedFolder, gameID: gameID) else {
                print("[ScummVM-ERR] Failed to create hook file")
                return
            }
            
            // Step 4: Launch with hook file instead of ZIP
            print("[ScummVM] Launching with hook file: \(hookPath.path)")
            
            // Create a temporary ROM with the hook file path
            var modifiedRom = rom
            modifiedRom.path = hookPath
            
            // Store the hook path for the bridge
            self.romPath = hookPath.path
            
            super.launch(rom: modifiedRom, coreID: coreID)
        } else {
            // Non-ZIP file (maybe already a .scummvm file), launch normally
            print("[ScummVM] Launching non-ZIP file normally")
            super.launch(rom: rom, coreID: coreID)
        }
    }
}