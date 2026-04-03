import Foundation
import os

// MARK: - Log Level

/// Log levels for the TruchieEmu logging system.
enum LogLevel: String, Codable, CaseIterable {
    case none = "none"
    case info = "info"
    case debug = "debug"
    case extreme = "extreme"
    
    var description: String {
        switch self {
        case .none: return "No Logging"
        case .info: return "Info"
        case .debug: return "Debug"
        case .extreme: return "Extreme"
        }
    }
    
    var shouldLogInfo: Bool { self == .info || self == .debug || self == .extreme }
    var shouldLogDebug: Bool { self == .debug || self == .extreme }
    var shouldLogExtreme: Bool { self == .extreme }
    
    var label: String {
        switch self {
        case .none: return "NONE"
        case .info: return "INFO"
        case .debug: return "DEBUG"
        case .extreme: return "EXTREME"
        }
    }
}

// MARK: - LoggerService

/// Centralized logging service for TruchieEmu.
/// Routes logs to both the debug console and an optional log file.
/// Thread-safe for concurrent access.
final class LoggerService: @unchecked Sendable {
    static let shared = LoggerService()
    
    // MARK: - Configuration
    
    @Published private(set) var currentLevel: LogLevel {
        didSet {
            UserDefaults.standard.set(currentLevel.rawValue, forKey: "log_level")
        }
    }
    
    // MARK: - File Logging State
    
    private var logFileHandle: FileHandle?
    private let logFileQueue = DispatchQueue(label: "com.truchiemu.logger", qos: .utility)
    private let maxLogSizeBytes: Int64 = 5 * 1024 * 1024 // 5 MB
    private let maxLogAgeDays: Int = 7
    
    // MARK: - OS Logger (for info-level, always visible in Console.app)
    private let osLogger: OSLog
    
    // MARK: - Date formatter
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    // MARK: - Init
    
    private init() {
        // Load saved log level
        let rawLevel = UserDefaults.standard.string(forKey: "log_level") ?? "none"
        self.currentLevel = LogLevel(rawValue: rawLevel) ?? .none
        
        // Create OS logger for system console
        self.osLogger = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.truchiemu", category: "TruchieEmu")
        
        // Initialize file logging
        setupFileLogging()
    }
    
    // MARK: - Setup File Logging
    
    private func setupFileLogging() {
        // Setup must be synchronous to ensure file handle is ready before first log write
        _setupFileLoggingSync()
    }
    
    private func _setupFileLoggingSync() {
        // Close existing handle
        logFileHandle?.closeFile()
        logFileHandle = nil
        
        let logURL = LogManager.shared.currentLogURL
        print("[Logger] Setting up file logging at: \(logURL.path)")
        
        do {
            // Ensure directory exists
            let directoryURL = logURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                print("[Logger] Creating directory: \(directoryURL.path)")
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            
            // Open file for appending
            if !FileManager.default.fileExists(atPath: logURL.path) {
                print("[Logger] Creating log file at: \(logURL.path)")
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            
            logFileHandle = try FileHandle(forWritingTo: logURL)
            logFileHandle?.seekToEndOfFile()
            
            print("[Logger] File handle opened successfully, log file ready")
            
            // Write start marker directly (not through writeToFile to avoid recursion)
            let startMarker = "// Logging started at \(dateFormatter.string(from: Date())) //\n"
            if let data = startMarker.data(using: .utf8) {
                logFileHandle?.seekToEndOfFile()
                logFileHandle?.write(data)
            }
            let levelMarker = "// Log level: \(currentLevel.rawValue) //\n"
            if let data = levelMarker.data(using: .utf8) {
                logFileHandle?.seekToEndOfFile()
                logFileHandle?.write(data)
            }
            logFileHandle?.synchronizeFile()
            print("[Logger] Start markers written successfully")
            
        } catch {
            print("[Logger] ERROR setting up file logging: \(error.localizedDescription)")
            print("[Logger] Log URL: \(logURL.path)")
        }
    }
    
    // MARK: - Set Log Level
    
    func setLevel(_ level: LogLevel) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentLevel = level
            
            // Update file logging
            self.logFileQueue.async { [weak self] in
                self?.writeToFile("// Log level changed to \(level.rawValue) at \(self?.dateFormatter.string(from: Date()) ?? "") //\n")
            }
        }
    }
    
    // MARK: - Public Logging API
    
    /// Log at INFO level: general logs, games running, downloads, file operations, save/load states, zipping, online operations.
    static func info(_ message: String) {
        shared.log(.info, category: "App", message: message)
    }
    
    /// Log at INFO level with a specific category.
    static func info(category: String, _ message: String) {
        shared.log(.info, category: category, message: message)
    }
    
    /// Log at DEBUG level: more detailed logs for troubleshooting.
    static func debug(_ message: String) {
        shared.log(.debug, category: "App", message: message)
    }
    
    /// Log at DEBUG level with a specific category.
    static func debug(category: String, _ message: String) {
        shared.log(.debug, category: category, message: message)
    }
    
    /// Log at EXTREME level: every frame, timing data, etc.
    static func extreme(_ message: String) {
        shared.log(.extreme, category: "App", message: message)
    }
    
    /// Log at EXTREME level with a specific category.
    static func extreme(category: String, _ message: String) {
        shared.log(.extreme, category: category, message: message)
    }
    
    // MARK: - Internal Log Implementation
    
    private func log(_ level: LogLevel, category: String, message: String) {
        // Check if this level should be logged
        if !shouldLogLevel(level) { return }
        
        let timestamp = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone.current)
        let formatted = "\(timestamp) [\(level.label)] [\(category)] \(message)"
        
        // Always print to debug console (useful during development even in "none" mode we skip)
        print(formatted)
        
        // Write to file asynchronously
        logFileQueue.async { [weak self] in
            self?.writeToFile(formatted + "\n")
        }
        
        // Also use OS logger for INFO level (always visible in Console.app)
        if level == .info {
            os_log("%{public}@", log: osLogger, type: .info, message)
        }
    }
    
    private func shouldLogLevel(_ level: LogLevel) -> Bool {
        switch level {
        case .none:
            return false // Never log "none" messages
        case .info:
            return currentLevel.shouldLogInfo
        case .debug:
            return currentLevel.shouldLogDebug
        case .extreme:
            return currentLevel.shouldLogExtreme
        }
    }
    
    // MARK: - File Writing
    
    private func writeToFile(_ text: String) {
        guard let handle = logFileHandle else {
            print("[Logger] ERROR: writeToFile called but logFileHandle is nil")
            return
        }
        
        guard let data = text.data(using: .utf8) else {
            print("[Logger] ERROR: failed to convert text to UTF-8 data")
            return
        }
        
        // Check file size and trim if needed
        checkAndTrimLogFile(handle: handle)
        
        // Append data
        handle.seekToEndOfFile()
        handle.write(data)
    }
    
    private func checkAndTrimLogFile(handle: FileHandle) {
        // Check file size
        handle.seekToEndOfFile()
        let currentSize = handle.offsetInFile
        
        if currentSize >= maxLogSizeBytes {
            rotateLogFile()
        }
    }
    
    private func rotateLogFile() {
        let logURL = LogManager.shared.currentLogURL
        
        // Remove oldest rotated file (log.2)
        let oldestURL = logURL.appendingPathExtension("2")
        try? FileManager.default.removeItem(at: oldestURL)
        
        // Move current .log.1 to .log.2
        let middleURL = logURL.appendingPathExtension("1")
        if FileManager.default.fileExists(atPath: middleURL.path) {
            try? FileManager.default.moveItem(at: middleURL, to: oldestURL)
        }
        
        // Close current handle
        logFileHandle?.closeFile()
        logFileHandle = nil
        
        // Move current log to .log.1
        if FileManager.default.fileExists(atPath: logURL.path) {
            try? FileManager.default.moveItem(at: logURL, to: middleURL)
            // Truncate the .log.1 file content to only keep recent entries if it's large
            trimFileToRecentEntries(at: middleURL, maxLines: 500)
        }
        
        // Re-open file logging
        _setupFileLoggingSync()
    }
    
    /// Trim a log file to keep only the most recent N lines.
    private func trimFileToRecentEntries(at url: URL, maxLines: Int) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        let recentLines = lines.suffix(maxLines)
        let trimmed = recentLines.joined(separator: "\n")
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - File Management (called from main thread)
    
    /// Trim the current log file to remove entries older than N days.
    func trimOldEntries(olderThanDays days: Int) {
        logFileQueue.async { [weak self] in
            self?._trimOldEntriesSync(olderThanDays: days)
        }
    }
    
    private func _trimOldEntriesSync(olderThanDays days: Int) {
        let logURL = LogManager.shared.currentLogURL
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        
        let cutoffDate = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let cutoffStr = ISO8601DateFormatter.string(from: cutoffDate, timeZone: TimeZone.current)
        
        let lines = content.components(separatedBy: .newlines)
        let keptLines = lines.filter { line in
            // Keep lines that are newer than cutoff, or start with "//" (markers)
            guard !line.hasPrefix("//"), let firstSpace = line.firstIndex(of: " ") else { return true }
            let dateStr = String(line[..<firstSpace])
            return dateStr >= cutoffStr
        }
        
        let trimmed = keptLines.joined(separator: "\n")
        try? trimmed.write(to: logURL, atomically: true, encoding: .utf8)
        
        // Write marker
        writeToFile("// Trimmed entries older than \(cutoffDate.description) //\n")
    }
    
    /// Clear all log files (current and rotated).
    func clearAllLogs() {
        logFileQueue.async { [weak self] in
            let logURL = LogManager.shared.currentLogURL
            
            // Close current handle
            self?.logFileHandle?.closeFile()
            self?.logFileHandle = nil
            
            // Remove all log files
            try? FileManager.default.removeItem(at: logURL)
            try? FileManager.default.removeItem(at: logURL.appendingPathExtension("1"))
            try? FileManager.default.removeItem(at: logURL.appendingPathExtension("2"))
            
            // Re-setup logging
            self?._setupFileLoggingSync()
        }
    }
    
    /// Get the current log file size in bytes.
    func currentLogFileSize() -> Int64 {
        let logURL = LogManager.shared.currentLogURL
        return (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int64) ?? 0
    }
    
    /// Get total size of all log files (current + rotated).
    func totalLogFileSize() -> Int64 {
        let logURL = LogManager.shared.currentLogURL
        var total: Int64 = 0
        for ext in ["", "1", "2"] {
            let url = ext.isEmpty ? logURL : logURL.appendingPathExtension(ext)
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                total += size
            }
        }
        return total
    }
    
    /// Get age of the current log file.
    func currentLogFileAge() -> TimeInterval? {
        let logURL = LogManager.shared.currentLogURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let modDate = attrs[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(modDate)
    }
}

// MARK: - ISO8601DateFormatter Extensions

extension ISO8601DateFormatter {
    static func string(from date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTimeZone, .withColonSeparatorInTime, .withDashSeparatorInDate]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}