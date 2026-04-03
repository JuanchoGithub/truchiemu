import Foundation
import SwiftUI
import AppKit

/// UserDefaults keys for bezel storage configuration.
enum BezelUserDefaultsKeys {
    static let storageMode = "bezelStorageMode"
    static let customFolderPath = "bezelCustomFolderPath"
    static let initialSetupComplete = "bezelInitialSetupComplete"
    static let lastPromptedLibraryCount = "bezelLastPromptedLibraryCount"
    /// Tracks the parent folder when using library-relative mode (for multi-folder detection)
    static let libraryFolderPath = "bezelLibraryFolderPath"
}

/// Manages bezel storage location, folder setup, and migration between locations.
@MainActor
class BezelStorageManager: ObservableObject {
    static let shared = BezelStorageManager()
    
    @Published var storageMode: BezelStorageMode
    @Published var customFolderPath: URL?
    @Published var hasCompletedInitialSetup: Bool
    /// The library folder that bezels are relative to (stored for multi-folder detection)
    @Published var libraryFolderPath: URL?
    
    private init() {
        // Load stored preferences
        let modeRaw = UserDefaults.standard.string(forKey: BezelUserDefaultsKeys.storageMode) ?? ""
        self.storageMode = BezelStorageMode(rawValue: modeRaw) ?? .libraryRelative
        
        if let pathString = UserDefaults.standard.string(forKey: BezelUserDefaultsKeys.customFolderPath) {
            self.customFolderPath = URL(filePath: pathString)
        } else {
            self.customFolderPath = nil
        }
        
        if let libPathString = UserDefaults.standard.string(forKey: BezelUserDefaultsKeys.libraryFolderPath) {
            self.libraryFolderPath = URL(filePath: libPathString)
        } else {
            self.libraryFolderPath = nil
        }
        
        self.hasCompletedInitialSetup = UserDefaults.standard.bool(
            forKey: BezelUserDefaultsKeys.initialSetupComplete
        )
    }
    
    // MARK: - Storage Resolution
    
    /// Returns the root directory where bezels are stored.
    var bezelRootDirectory: URL {
        switch storageMode {
        case .libraryRelative:
            return libraryRelativeBezelsDirectory
        case .customFolder:
            return customFolderPath ?? internalManagedDirectory
        case .internalManaged:
            return internalManagedDirectory
        }
    }
    
    /// Default directory relative to the stored library folder.
    var libraryRelativeBezelsDirectory: URL {
        if let folder = libraryFolderPath {
            return folder.appendingPathComponent("bezels")
        }
        // Fallback to internal if no library folder set
        return internalManagedDirectory
    }
    
    /// Set the library folder reference for library-relative mode.
    /// Should be called when the first library folder is added.
    func setLibraryFolderPath(_ url: URL) {
        guard libraryFolderPath == nil else { return } // Only set once
        libraryFolderPath = url
        UserDefaults.standard.set(url.path, forKey: BezelUserDefaultsKeys.libraryFolderPath)
        
        // Trigger storage mode prompt if not already set up
        if !hasCompletedInitialSetup {
            Task {
                _ = await promptForStorageLocation()
            }
        }
    }
    
    /// Internal managed directory in Application Support.
    var internalManagedDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("TruchieEmu/bezels")
    }
    
    /// Get the system-specific bezel directory.
    func systemBezelsDirectory(for systemID: String) -> URL {
        bezelRootDirectory.appendingPathComponent(systemID)
    }
    
    /// Get the path to a specific bezel file.
    func bezelFilePath(systemID: String, gameName: String) -> URL {
        let sanitized = sanitizeFilename(gameName)
        return systemBezelsDirectory(for: systemID)
            .appendingPathComponent("\(sanitized).png")
    }
    
    /// Get the path to the manifest cache for a system.
    func manifestCachePath(for systemID: String) -> URL {
        return systemBezelsDirectory(for: systemID)
            .appendingPathComponent("manifest.json")
    }
    
    // MARK: - Directory Management
    
    /// Ensure the bezel directory structure exists.
    func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        
        // Create root bezel directory
        if !fm.fileExists(atPath: bezelRootDirectory.path) {
            try fm.createDirectory(at: bezelRootDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Open the bezel root directory in Finder.
    func openInFinder() {
        do {
            try ensureDirectoriesExist()
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: bezelRootDirectory.path)
        } catch {
            print("[BezelStorageManager] Failed to open bezel directory: \(error)")
        }
    }
    
    // MARK: - Storage Configuration
    
    /// Prompt user to choose bezel storage location.
    func promptForStorageLocation() async -> Bool {
        // Check if already configured
        guard !hasCompletedInitialSetup else { return true }
        
        let alert = NSAlert()
        alert.messageText = "Bezel Storage Location"
        alert.informativeText = "Where would you like to store game bezels (side art)?"
        alert.alertStyle = .informational
        
        // Add buttons
        alert.addButton(withTitle: "Library Folder")
        alert.addButton(withTitle: "Choose Folder...")
        alert.addButton(withTitle: "Internal")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Library folder (default)
            storageMode = .libraryRelative
            UserDefaults.standard.set(BezelStorageMode.libraryRelative.rawValue, 
                                      forKey: BezelUserDefaultsKeys.storageMode)
            
        case .alertSecondButtonReturn:
            // Custom folder
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select a folder for bezel storage"
            
            if panel.runModal() == .OK, let url = panel.url {
                storageMode = .customFolder
                customFolderPath = url
                UserDefaults.standard.set(BezelStorageMode.customFolder.rawValue,
                                          forKey: BezelUserDefaultsKeys.storageMode)
                UserDefaults.standard.set(url.path,
                                          forKey: BezelUserDefaultsKeys.customFolderPath)
            } else {
                // User cancelled, fall back to internal
                storageMode = .internalManaged
                UserDefaults.standard.set(BezelStorageMode.internalManaged.rawValue,
                                          forKey: BezelUserDefaultsKeys.storageMode)
            }
            
        case .alertThirdButtonReturn:
            // Internal
            storageMode = .internalManaged
            UserDefaults.standard.set(BezelStorageMode.internalManaged.rawValue,
                                      forKey: BezelUserDefaultsKeys.storageMode)
            
        default:
            // Default to library relative
            storageMode = .libraryRelative
            UserDefaults.standard.set(BezelStorageMode.libraryRelative.rawValue,
                                      forKey: BezelUserDefaultsKeys.storageMode)
        }
        
        // Mark setup as complete
        hasCompletedInitialSetup = true
        UserDefaults.standard.set(true, forKey: BezelUserDefaultsKeys.initialSetupComplete)
        
        do {
            try ensureDirectoriesExist()
        } catch {
            print("[BezelStorageManager] Failed to create directories: \(error)")
        }
        
        return true
    }
    
    /// Called when a new library folder is added. May prompt to relocate bezels.
    /// - Parameter libraryFolderCount: The current number of library folders.
    func checkMultiFolderRelocation(libraryFolderCount: Int) async {
        // Only prompt if currently in library-relative mode
        guard storageMode == .libraryRelative else { return }
        
        // Check if this is not the first folder
        guard libraryFolderCount > 1 else { return }
        
        // Check if we already prompted for this library count
        let lastCount = UserDefaults.standard.integer(forKey: BezelUserDefaultsKeys.lastPromptedLibraryCount)
        guard libraryFolderCount > lastCount else { return }
        
        let currentLocation = bezelRootDirectory.path
        let alert = NSAlert()
        alert.messageText = "Multiple Library Folders Detected"
        alert.informativeText = """
            You now have \(libraryFolderCount) library folders.
            Your bezels are currently stored in:
            \(currentLocation)
            
            Would you like to keep them here, or move them to a different location?
            """
        alert.alertStyle = .informational
        
        alert.addButton(withTitle: "Keep Current Location")
        alert.addButton(withTitle: "Choose New Location...")
        alert.addButton(withTitle: "Move to Internal")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Keep current - update last prompted count
            UserDefaults.standard.set(libraryFolderCount,
                                      forKey: BezelUserDefaultsKeys.lastPromptedLibraryCount)
            
        case .alertSecondButtonReturn:
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select a new folder for bezel storage"
            
            if panel.runModal() == .OK, let newURL = panel.url {
                try? await migrateBezels(to: newURL)
                storageMode = .customFolder
                customFolderPath = newURL
                UserDefaults.standard.set(BezelStorageMode.customFolder.rawValue,
                                          forKey: BezelUserDefaultsKeys.storageMode)
                UserDefaults.standard.set(newURL.path,
                                          forKey: BezelUserDefaultsKeys.customFolderPath)
            }
            
        case .alertThirdButtonReturn:
            let internalDir = internalManagedDirectory
            try? await migrateBezels(to: internalDir)
            storageMode = .internalManaged
            customFolderPath = nil
            UserDefaults.standard.set(BezelStorageMode.internalManaged.rawValue,
                                      forKey: BezelUserDefaultsKeys.storageMode)
            UserDefaults.standard.removeObject(forKey: BezelUserDefaultsKeys.customFolderPath)
            
        default:
            break
        }
    }
    
    // MARK: - Migration
    
    /// Migrate bezels to a new location.
    func migrateBezels(to newLocation: URL) async throws {
        let fm = FileManager.default
        let currentRoot = bezelRootDirectory
        
        // Ensure source exists
        guard fm.fileExists(atPath: currentRoot.path) else { return }
        
        // Create destination if needed
        if !fm.fileExists(atPath: newLocation.path) {
            try fm.createDirectory(at: newLocation, withIntermediateDirectories: true)
        }
        
        // Count items to move
        let contents = try fm.contentsOfDirectory(atPath: currentRoot.path)
        let totalItems = contents.count
        
        for itemName in contents {
            let source = currentRoot.appendingPathComponent(itemName)
            let destination = newLocation.appendingPathComponent(itemName)
            
            // Skip manifest cache files
            if itemName == "manifest.json" {
                continue
            }
            
            if fm.fileExists(atPath: destination.path) {
                // Remove existing and replace
                try fm.removeItem(at: destination)
            }
            
            try fm.moveItem(at: source, to: destination)
        }
        
        print("[BezelStorageManager] Migrated \(totalItems) items to \(newLocation.path)")
    }
    
    /// Clear all bezel files from current location.
    func clearAllBezels() throws {
        let fm = FileManager.default
        let root = bezelRootDirectory
        
        if fm.fileExists(atPath: root.path) {
            try fm.removeItem(at: root)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }
    
    /// Get the size of bezel storage (for statistics).
    func bezelStorageSize() -> Int64 {
        let fm = FileManager.default
        let root = bezelRootDirectory
        
        guard fm.fileExists(atPath: root.path) else { return 0 }
        
        var totalSize: Int64 = 0
        
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let size = resourceValues.fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        
        return totalSize
    }
    
    /// List all local bezel PNG files for a given system ID.
    struct LocalBezelInfo: Identifiable, Hashable {
        let id: String
        let fileURL: URL
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: LocalBezelInfo, rhs: LocalBezelInfo) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    func listLocalBezels(for systemID: String) -> [LocalBezelInfo] {
        let fm = FileManager.default
        let systemDir = systemBezelsDirectory(for: systemID)
        
        guard fm.fileExists(atPath: systemDir.path) else { return [] }
        
        var results: [LocalBezelInfo] = []
        
        if let enumerator = fm.enumerator(at: systemDir, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "png" {
                    let id = fileURL.deletingPathExtension().lastPathComponent
                    results.append(LocalBezelInfo(id: id, fileURL: fileURL))
                }
            }
        }
        
        // Sort alphabetically by id
        results.sort { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        return results
    }
    
    /// Get count of downloaded bezel files.
    func downloadedBezelCount() -> Int {
        let fm = FileManager.default
        let root = bezelRootDirectory
        
        guard fm.fileExists(atPath: root.path) else { return 0 }
        
        var count = 0
        
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "png" {
                    count += 1
                }
            }
        }
        
        return count
    }
    
    // MARK: - Helpers
    
    /// Sanitize a filename for safe file storage.
    func sanitizeFilename(_ filename: String) -> String {
        // Remove or replace problematic characters
        var sanitized = filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "*", with: "-")
            .replacingOccurrences(of: "?", with: "-")
            .replacingOccurrences(of: "\"", with: "-")
            .replacingOccurrences(of: "<", with: "-")
            .replacingOccurrences(of: ">", with: "-")
            .replacingOccurrences(of: "|", with: "-")
        
        // Trim whitespace
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Limit length
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }
        
        return sanitized.isEmpty ? "unknown" : sanitized
    }
}

// MARK: - UserDefaults Extensions

extension UserDefaults {
    var bezelStorageMode: BezelStorageMode {
        get {
            let raw = string(forKey: BezelUserDefaultsKeys.storageMode)
            return BezelStorageMode(rawValue: raw ?? "") ?? .libraryRelative
        }
        set {
            set(newValue.rawValue, forKey: BezelUserDefaultsKeys.storageMode)
        }
    }
}