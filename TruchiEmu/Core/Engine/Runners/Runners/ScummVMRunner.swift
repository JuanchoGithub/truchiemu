import Foundation
import MetalKit

// MARK: - ScummVM Cache Manager (static, called from ROMLibrary)

// Shared cache manager for ScummVM extracted files.
// Provides static methods for cleanup that can be called during library scanning.
enum ScummVMCacheManager {
    
    // Directory where extracted ScummVM games are stored
    static var scummVMDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchiEmu/ScummVMExtracted")
    }
    
    // Clean up extracted ScummVM folders whose source ZIP files no longer exist in the library.
    // - Parameter activeScummvmPaths: Set of paths for ScummVM ZIP files currently in the library.
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
                LoggerService.info(category: "ScummVM", "Removing orphaned cache: \(folder.path)")
                try? fm.removeItem(at: folder)
            }
        }
    }
}

// ScummVM-specific emulator runner that handles ZIP files by:
// 1. Extracting the ZIP to a cache directory
// 2. Detecting the game ID from filenames
// 3. Generating a .scummvm hook file
// 4. Passing the .scummvm file to the core instead of the ZIP
class ScummVMRunner: EmulatorRunner, @unchecked Sendable {
    
    // MARK: - Game ID Detection Patterns
    

    // Audio file extensions that indicate ScummVM game data
    static let scummVMAudioExtensions: Set<String> = [
        "flac", "ogg", "wav", "mp3", "aif", "aiff"
    ]
    
    // ScummVM-specific data file extensions
    static let scummVMDataExtensions: Set<String> = [
        "sou", "000", "001", "002", "003", "004", "005",
        "flc", "flx", "san", "bun", "ws6",
        "scr", "00", "lfl", "hex"
    ]
    
    // MARK: - Cache Management
    
    // Directory where extracted ScummVM games are stored
    private var scummVMDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchiEmu/ScummVMExtracted")
    }
    
    // Get the extracted game folder path for a given ZIP file
    private func extractedPath(for zipPath: URL) -> URL {
        let baseName = zipPath.deletingPathExtension().lastPathComponent
        return scummVMDirectory.appendingPathComponent(baseName)
    }
    
    // Get the .scummvm hook file path for a given ZIP file
    private func hookFilePath(in gameFolder: URL) -> URL {
        let gameID = detectGameID(in: gameFolder)
        return gameFolder.appendingPathComponent("\(gameID).scummvm")
    }
    
    // MARK: - ZIP Extraction
    
    // Extract a ZIP file to the cache directory if not already extracted
    // Returns the path to the extracted folder
    func extractIfNeeded(zipPath: URL) -> URL? {
        let destFolder = extractedPath(for: zipPath)
        
        // Check if already extracted
        if FileManager.default.fileExists(atPath: destFolder.path) {
            // Verify extraction is complete (has game files)
            if hasGameFiles(in: destFolder) {
                LoggerService.debug(category: "ScummVM", "Using cached extraction: \(destFolder.path)")
                return destFolder
            } else {
                // Corrupted or incomplete extraction, remove and re-extract
                LoggerService.info(category: "ScummVM", "Cached extraction is incomplete, removing and re-extracting: \(destFolder.path)")
                try? FileManager.default.removeItem(at: destFolder)
            }
        }
        
        // Create destination folder
        do {
            try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        } catch {
            LoggerService.info(category: "ScummVM", "Failed to create extraction directory: \(error)")
            return nil
        }
        
        // Extract using unzip (standard macOS utility)
        LoggerService.info(category: "ScummVM", "Extracting ZIP to: \(destFolder.path)")
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
                LoggerService.debug(category: "ScummVM", "Extraction successful")
                return destFolder
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                LoggerService.info(category: "ScummVM", "Extraction failed: \(errorMsg)")
                
                // Try alternative: use ditto
                LoggerService.debug(category: "ScummVM", "Trying ditto as fallback...")
                return extractWithDitto(zipPath: zipPath, destFolder: destFolder)
            }
        } catch {
            LoggerService.info(category: "ScummVM", "Exception during extraction: \(error)")
            return extractWithDitto(zipPath: zipPath, destFolder: destFolder)
        }
    }
    
    // Fallback extraction using ditto
    private func extractWithDitto(zipPath: URL, destFolder: URL) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", "--sequesterRsrc", zipPath.path, destFolder.path]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                LoggerService.debug(category: "ScummVM", "ditto extraction successful")
                return destFolder
            } else {
                LoggerService.info(category: "ScummVM", "ditto extraction failed with status: \(process.terminationStatus)")
                return nil
            }
        } catch {
            LoggerService.debug(category: "ScummVM", "ditto extraction exception: \(error)")
            return nil
        }
    }
    
    // MARK: - Game ID Detection
    
    // Detect the ScummVM game ID by scanning files in the extracted folder
    func detectGameID(in folder: URL) -> String? {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            
            // First pass: look for known game file patterns
            for file in files {
                let upperFile = file.uppercased()
                let nameWithoutExt = (upperFile as NSString).deletingPathExtension               
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
                LoggerService.debug(category: "ScummVM", "Detected ScummVM data files but no specific game ID")
            }
            
        } catch {
            LoggerService.info(category: "ScummVM", "Failed to read extracted folder: \(error)")
        }
        
        // Fallback: derive game ID from the folder/ZIP name
        let folderName = (folder.lastPathComponent as NSString).deletingPathExtension
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        
        // We do not fallback to a cleaned folder name because passing an invalid
        // shortname via the hook file causes ScummVM to open the launcher GUI.
        LoggerService.info(category: "ScummVM", "Could not confidently detect game ID, will use auto-detect.")
        return nil
    }
    
    // MARK: - Hook File Generation
    
    // Create a .scummvm hook file in the game folder
    // Returns the path to the hook file
    func createHookFile(in gameFolder: URL, gameID: String) -> URL? {
        let hookPath = gameFolder.appendingPathComponent("\(gameID).scummvm")
        
        // Check if hook file already exists with correct format
        if FileManager.default.fileExists(atPath: hookPath.path) {
            // Validate that it has the correct format (just the game ID on the first line)
            let existingContent = (try? String(contentsOf: hookPath, encoding: .utf8)) ?? ""
            let firstLine = existingContent.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if firstLine == gameID {
                LoggerService.debug(category: "ScummVM", "Hook file already exists with valid format: \(hookPath.path)")
                return hookPath
            } else {
                // Wrong format, remove and recreate
                LoggerService.debug(category: "ScummVM", "Hook file has wrong format (first line='\(firstLine)'), recreating...")
                try? FileManager.default.removeItem(at: hookPath)
            }
        }
        
        // Create the hook file with the game ID on the first line only.
        // The scummvm_libretro core reads ONLY the first line of the .scummvm file
        // and uses it as the target/game ID for game detection.
        // See: backends/platform/libretro/src/libretro-core.cpp:retro_load_game()
        let content = gameID
        
        do {
            try content.write(to: hookPath, atomically: true, encoding: .utf8)
            LoggerService.info(category: "ScummVM", "Created hook file with game ID: \(gameID)")
            return hookPath
        } catch {
            LoggerService.info(category: "ScummVM", "Failed to create hook file: \(error)")
            return nil
        }
    }
    
    // MARK: - Game File Detection
    
    // Check if a folder contains ScummVM game files
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

            }
        } catch {
            LoggerService.debug(category: "ScummVM", "Failed to check for game files: \(error)")
        }
        return false
    }
    
    // MARK: - Override Launch
    
    // Find any valid game file in the folder to trigger ScummVM auto-detect
    private func findAnyGameFile(in folder: URL) -> URL? {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            
            // Prioritize data files
            if let dataFile = files.first(where: { Self.scummVMDataExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
                return folder.appendingPathComponent(dataFile)
            }
            
            // Fallback to audio files
            if let audioFile = files.first(where: { Self.scummVMAudioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
                return folder.appendingPathComponent(audioFile)
            }
            
            // If none, just return the first file that is not a directory and is not a hidden file
            for file in files {
                if file.hasPrefix(".") { continue }
                let filePath = folder.appendingPathComponent(file)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: filePath.path, isDirectory: &isDir), !isDir.boolValue {
                    return filePath
                }
            }
        } catch {
            LoggerService.debug(category: "ScummVM", "Failed to check for game files: \(error)")
        }
        return nil
    }
    
    @MainActor
    override func launch(rom: ROM, coreID: String) {
        // Force "No Shader" (passthrough) for ScummVM.
        // ScummVM renders point-and-click adventure games at higher resolutions (320x200, 640x480+)
        // that look best with raw pixels — CRT scanlines, barrel distortion, and phosphor masks
        // are designed for low-res console output and are destructive on ScummVM's output.
        if let preset = ShaderPreset.preset(id: "builtin-none") {
            ShaderManager.shared.activatePreset(preset)
            LoggerService.info(category: "ScummVM", "Forced Passthrough shader (raw pixels) for ScummVM")
        }
        
        let romPath = rom.path
        let fileExt = romPath.pathExtension.lowercased()
        
        // Only handle ZIP files - pass through other formats directly
        if fileExt == "zip" {
            LoggerService.info(category: "ScummVM", "Processing ZIP file: \(romPath.path)")
            
            // Step 1: Extract the ZIP
            guard let extractedFolder = extractIfNeeded(zipPath: romPath) else {
                LoggerService.info(category: "ScummVM", "Failed to extract ZIP: \(romPath.path)")
                return
            }
            
            // Step 2: Detect game ID
            if let gameID = detectGameID(in: extractedFolder) {
                // Step 3: Create hook file
                guard let hookPath = createHookFile(in: extractedFolder, gameID: gameID) else {
                    LoggerService.info(category: "ScummVM", "Failed to create hook file in: \(extractedFolder.path)")
                    return
                }
                
                // Step 4: Launch with hook file instead of ZIP
                LoggerService.info(category: "ScummVM", "Launching with hook file: \(hookPath.path), gameID: \(gameID)")
                
                // Create a temporary ROM with the hook file path
                var modifiedRom = rom
                modifiedRom.path = hookPath
                
                // Store the hook path for the bridge
                self.romPath = hookPath.path
                
                super.launch(rom: modifiedRom, coreID: coreID)
            } else {
                // We couldn't detect a specific ID. Let's find any valid game file in the folder 
                // and pass it directly to let ScummVM auto-detect the game from the directory.
                guard let fallbackFile = findAnyGameFile(in: extractedFolder) else {
                    LoggerService.info(category: "ScummVM", "No valid game files found for auto-detect in: \(extractedFolder.path)")
                    return
                }
                
                LoggerService.info(category: "ScummVM", "Auto-detecting game using file: \(fallbackFile.path)")
                
                var modifiedRom = rom
                modifiedRom.path = fallbackFile
                self.romPath = fallbackFile.path
                
                super.launch(rom: modifiedRom, coreID: coreID)
            }
        } else {
            // Non-ZIP file (maybe already a .scummvm file), launch normally
            LoggerService.debug(category: "ScummVM", "Launching non-ZIP file normally")
            super.launch(rom: rom, coreID: coreID)
        }
    }
}