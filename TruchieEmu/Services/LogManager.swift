import Foundation
import AppKit

// MARK: - LogManager

/// Manages log file storage, paths, and file system operations for TruchieEmu.
final class LogManager: @unchecked Sendable {
    static let shared = LogManager()
    
    // MARK: - Constants
    
    /// Default log file name
    static let defaultLogFileName = "TruchieEmu.log"
    
    /// UserDefaults key for custom log folder URL
    private static let customLogFolderKey = "custom_log_folder_url"
    
    // MARK: - Log File URL
    
    /// The current log file URL, using custom path if set.
    var currentLogURL: URL {
        if let customURL = customLogFolderURL {
            return customURL.appendingPathComponent(Self.defaultLogFileName)
        }
        return defaultLogURL
    }
    
    /// Default log file location in Application Support.
    var defaultLogURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("TruchieEmu")
            .appendingPathComponent("Logs")
            .appendingPathComponent(Self.defaultLogFileName)
    }
    
    /// Current log folder URL (custom or default).
    var currentLogFolderURL: URL {
        if let customURL = customLogFolderURL {
            return customURL
        }
        return defaultLogFolderURL
    }
    
    /// Default log folder URL.
    var defaultLogFolderURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchieEmu").appendingPathComponent("Logs")
    }
    
    // MARK: - Custom Log Folder
    
    /// Get custom log folder URL if set by user.
    var customLogFolderURL: URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.customLogFolderKey) else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }
    
    /// Save a custom log folder bookmark.
    func setLogFolder(_ url: URL) {
        do {
            _ = url.startAccessingSecurityScopedResource()
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope)
            UserDefaults.standard.set(bookmarkData, forKey: Self.customLogFolderKey)
            LoggerService.shared.setLevel(LoggerService.shared.currentLevel) // Re-setup file logging
            LoggerService.info(category: "LogManager", "Log folder changed to \(url.path)")
        } catch {
            LoggerService.debug(category: "LogManager", "Failed to save log folder bookmark: \(error)")
        }
    }
    
    /// Reset to default log folder.
    func resetToDefaultLogFolder() {
        UserDefaults.standard.removeObject(forKey: Self.customLogFolderKey)
        LoggerService.shared.setLevel(LoggerService.shared.currentLevel) // Re-setup file logging
        LoggerService.info(category: "LogManager", "Log folder reset to default")
    }
    
    // MARK: - Finder Integration
    
    /// Open the log file in Finder (reveals the file).
    func showLogInFinder() {
        let logURL = currentLogURL
        
        // Ensure directory exists
        let directoryURL = logURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            } catch {
                NSAlert.showAlert(title: "Log Folder Error", message: "Could not create log folder: \(error.localizedDescription)")
                return
            }
        }
        
        // Create empty log file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }
    
    /// Open the log folder in Finder (reveals the directory).
    func showLogFolderInFinder() {
        let folderURL = currentLogFolderURL
        
        if FileManager.default.fileExists(atPath: folderURL.path) {
            NSWorkspace.shared.open(folderURL)
        } else {
            NSAlert.showAlert(title: "Log Folder Not Found", message: "The log folder does not exist at \(folderURL.path)")
        }
    }
    
    // MARK: - Cleanup
    
    /// Clean up old log files (rotated files older than 7 days).
    func cleanupOldRotatedLogs() {
        let folderURL = currentLogFolderURL
        let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        
        guard let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey]) else { return }
        
        while let fileURL = enumerator.nextObject() as? URL {
            do {
                let values = try fileURL.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])
                guard values.isRegularFile == true,
                      let creationDate = values.creationDate else { continue }
                
                // Check if this is a rotated log file (*.log.1, *.log.2)
                let isRotated = fileURL.pathExtension == "1" || fileURL.pathExtension == "2"
                
                if isRotated && Date().timeIntervalSince(creationDate) > maxAge {
                    try FileManager.default.removeItem(at: fileURL)
                    LoggerService.debug(category: "LogManager", "Cleaned up old rotated log: \(fileURL.lastPathComponent)")
                }
            } catch {
                // Skip files we can't read
            }
        }
    }
    
    /// Quick trim of logs: keep only the most recent entries to stay under 5MB.
    func quickTrimLog() {
        LoggerService.shared.trimOldEntries(olderThanDays: 7)
    }
    
    /// Get human-readable file size string.
    var currentLogFileSizeString: String {
        let size = LoggerService.shared.currentLogFileSize()
        if size == 0 { return "0 KB (empty)" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024.0) }
        return String(format: "%.2f MB", Double(size) / (1024.0 * 1024.0))
    }
    
    /// Get human-readable total file size string (includes rotated files).
    var totalLogFileSizeString: String {
        let size = LoggerService.shared.totalLogFileSize()
        if size == 0 { return "0 KB (empty)" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024.0) }
        return String(format: "%.2f MB", Double(size) / (1024.0 * 1024.0))
    }
    
    /// Get age of current log file as human-readable string.
    var currentLogFileAgeString: String {
        guard let age = LoggerService.shared.currentLogFileAge() else { return "Unknown" }
        if age < 60 { return "Just now" }
        if age < 3600 { return "\(Int(age / 60)) minutes ago" }
        if age < 86400 { return "\(Int(age / 3600)) hours ago" }
        let days = Int(age / 86400)
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }
    
    // MARK: - Initialization
    
    private init() {
        // Set up default folder structure
        ensureLogDirectoryExists()
    }
    
    /// Create the log directory if it doesn't exist.
    private func ensureLogDirectoryExists() {
        let logURL = currentLogURL
        let directoryURL = logURL.deletingLastPathComponent()
        
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            } catch {
                LoggerService.info(category: "LogManager", "Could not create default log directory: \(error)")
            }
        }
    }
}

// MARK: - NSAlert Helper

extension NSAlert {
    static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}