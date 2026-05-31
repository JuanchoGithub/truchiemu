import Foundation
import MetalKit
import GameController

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

    private var analogMouseButtonLeft: String = "a"
    private var analogMouseButtonDownRight: String = "b"
    private var analogMouseButtonDownMiddle: String = "x"
    private var analogMouseTimer: Timer?

    override func stop() {
        analogMouseTimer?.invalidate()
        analogMouseTimer = nil
        super.stop()
    }

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
        if let gameID = detectGameID(in: gameFolder) {
            return gameFolder.appendingPathComponent("\(gameID).scummvm")
        }
        return gameFolder.appendingPathComponent("unknown.scummvm")
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
                _ = (upperFile as NSString).deletingPathExtension               
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
        _ = (folder.lastPathComponent as NSString).deletingPathExtension
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
                _ = file.uppercased()
                
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
    
    // MARK: - Analog Mouse Configuration

    @MainActor
    private func configureAnalogMouse() {
        let sysID = "scummvm"
        let enabled = AppSettings.getBool("analogMouse_enabled_\(sysID)", defaultValue: false)

        if enabled {
            let sensitivity = Float(AppSettings.getDouble("analogMouse_sensitivity_\(sysID)", defaultValue: 1.0))
            let deadZone = Float(AppSettings.getDouble("analogMouse_deadZone_\(sysID)", defaultValue: 0.15))
            let stickString = AppSettings.getString("analogMouse_stick_\(sysID)", defaultValue: "left") ?? "left"
            let stickIndex = stickString == "right" ? 1 : 0

            XPCBridgeAdapter.shared.setAnalogMouseConfig(player: 0, enabled: true, sensitivity: sensitivity, deadzone: deadZone, stickIndex: stickIndex)

            analogMouseButtonLeft = AppSettings.getString("analogMouse_buttonLeft_\(sysID)", defaultValue: "a") ?? "a"
            analogMouseButtonDownRight = AppSettings.getString("analogMouse_buttonRight_\(sysID)", defaultValue: "b") ?? "b"
            analogMouseButtonDownMiddle = AppSettings.getString("analogMouse_buttonMiddle_\(sysID)", defaultValue: "x") ?? "x"

            LoggerService.info(category: "ScummVM", "Analog mouse enabled: sensitivity=\(sensitivity), deadZone=\(deadZone), stick=\(stickString), left=\(analogMouseButtonLeft), right=\(analogMouseButtonDownRight), middle=\(analogMouseButtonDownMiddle)")
        } else {
            XPCBridgeAdapter.shared.setAnalogMouseConfig(player: 0, enabled: false, sensitivity: 1.0, deadzone: 0.15, stickIndex: 0)
            LoggerService.debug(category: "ScummVM", "Analog mouse disabled")
        }
    }

    @MainActor
    override func launch(rom: ROM, coreID: String, shaderUniformOverrides: [String: Float] = [:]) {
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
                
                super.launch(rom: modifiedRom, coreID: coreID, shaderUniformOverrides: shaderUniformOverrides)
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
                
                super.launch(rom: modifiedRom, coreID: coreID, shaderUniformOverrides: shaderUniformOverrides)
            }
        } else {
            // Non-ZIP file (maybe already a .scummvm file), launch normally
            LoggerService.debug(category: "ScummVM", "Launching non-ZIP file normally")
            super.launch(rom: rom, coreID: coreID, shaderUniformOverrides: shaderUniformOverrides)
        }
        
        // Auto-start input capture for ScummVM games
        if let window = self.window, !InputCaptureManager.shared.isCapturing {
            InputCaptureManager.shared.startCapture(window: window)
        }

        configureAnalogMouse()
    }

    @MainActor
    override func setupGamepadInput() {
        super.setupGamepadInput()

        guard AppSettings.getBool("analogMouse_enabled_scummvm", defaultValue: false) else { return }

        let cs = ControllerService.shared
        let sysID = "scummvm"
        let sensitivity = Float(AppSettings.getDouble("analogMouse_sensitivity_\(sysID)", defaultValue: 1.0))
        let deadZone = Float(AppSettings.getDouble("analogMouse_deadZone_\(sysID)", defaultValue: 0.15))
        let stickString = AppSettings.getString("analogMouse_stick_\(sysID)", defaultValue: "left") ?? "left"

        for player in cs.connectedControllers {
            guard let controller = player.gcController,
                  let extendedGamepad = controller.extendedGamepad else { continue }
            let mapping = cs.mapping(for: controller.vendorName ?? "Unknown", systemID: sysID)
            let ports = player.assignedPlayers.map { $0 - 1 }

            let stick = stickString == "right" ? extendedGamepad.rightThumbstick : extendedGamepad.leftThumbstick
            let secondaryStick = stickString == "right" ? extendedGamepad.leftThumbstick : extendedGamepad.rightThumbstick

            analogMouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                guard self != nil else { return }
                var xVal = stick.xAxis.value
                var yVal = stick.yAxis.value
                if fabsf(xVal) < deadZone { xVal = 0 }
                if fabsf(yVal) < deadZone { yVal = 0 }
                var dx = Int16(xVal * sensitivity * 8.0)
                var dy = Int16(-yVal * sensitivity * 8.0)

                let x2 = secondaryStick.xAxis.value
                let y2 = secondaryStick.yAxis.value
                if fabsf(x2) >= deadZone { dx += Int16(x2 * sensitivity * 8.0 * 0.2) }
                if fabsf(y2) >= deadZone { dy += Int16(-y2 * sensitivity * 8.0 * 0.2) }

                XPCBridgeAdapter.shared.setAnalogMouseDeltaX(dx, y: dy)
            }

            extendedGamepad.valueChangedHandler = { [weak self] _, element in
                guard let self = self else { return }
                for port in ports {
                    self.handleScummVMButtons(element, in: mapping, player: port)
                }
            }
        }
    }

    private func handleScummVMButtons(_ element: GCControllerElement, in mapping: ControllerGamepadMapping, player: Int) {
        if let dpad = element as? GCControllerDirectionPad {
            updateGamepadButton(dpad.up, in: mapping, player: player)
            updateGamepadButton(dpad.down, in: mapping, player: player)
            updateGamepadButton(dpad.left, in: mapping, player: player)
            updateGamepadButton(dpad.right, in: mapping, player: player)
            updateGamepadButton(dpad, in: mapping, player: player)
        } else {
            updateGamepadButton(element, in: mapping, player: player)
        }

        guard let btn = element as? GCControllerButtonInput else { return }
        for (retroBtn, btnMapping) in mapping.buttons {
            guard elementMatches(element, name: btnMapping.gcElementName) else { continue }
            let raw = retroBtn.rawValue
            if raw == analogMouseButtonLeft {
                XPCBridgeAdapter.shared.setMouseButton(0, pressed: btn.isPressed)
            }
            if raw == analogMouseButtonDownRight {
                XPCBridgeAdapter.shared.setMouseButton(1, pressed: btn.isPressed)
            }
            if raw == analogMouseButtonDownMiddle {
                XPCBridgeAdapter.shared.setMouseButton(2, pressed: btn.isPressed)
            }
            break
        }
    }
}