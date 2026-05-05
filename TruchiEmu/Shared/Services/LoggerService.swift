import Foundation
import os

// C-callable callback for routing libretro core logs into the file logger.
// Registered with LibretroBridge at startup so core-level logs (LibretroDB,
// Identify, Bridge, etc.) are written to TruchiEmu.log.
private let g_coreLogCallback: @convention(c) (UnsafePointer<Int8>?, Int32)
    -> Void = { message, level in
    guard let cStr = message else { return }
    let msg = String(cString: cStr)
    let ts = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone.current)
    let prefix: String
    switch level {
    case 3: prefix = "[Core-ERR]"   // RETRO_LOG_ERROR
    case 2: prefix = "[Core-WRN]"   // RETRO_LOG_WARN
    case 0: prefix = "[Core-INF]"   // RETRO_LOG_INFO
    default: prefix = "[Core-DBG]"  // RETRO_LOG_DEBUG
    }
    // Always write to file (core logs are invaluable for debugging)
    let formatted = "\(ts) \(prefix) \(msg)"
    print(formatted)
    LoggerService.shared.logFileQueue.async {
        LoggerService.shared.writeToFile(formatted + "\n")
    }
}

// MARK: - Log Level

// Log levels for the TruchiEmu logging system.
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

// Centralized logging service for TruchiEmu.
// Routes logs to both the debug console and an optional log file.
// Thread-safe for concurrent access.
final class LoggerService: @unchecked Sendable {
    static let shared = LoggerService()
    
    // MARK: - Configuration
    
    @Published private(set) var currentLevel: LogLevel {
        didSet {
            // Don't save to AppSettings during initialization - it could cause circular dep
            guard isInitialized else { return }
            AppSettings.set("log_level", value: currentLevel.rawValue)
        }
    }
    
    // Flag to prevent AppSettings writes during init
    private var isInitialized = false
    
  // MARK: - File Logging State

  private var logFileHandle: FileHandle?
  private var currentLogURL: URL?
  fileprivate let logFileQueue = DispatchQueue(label: "com.truchiemu.logger", qos: .utility)
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
        // Load saved log level (default to INFO - don't read AppSettings here to avoid circular dependency)
        // The actual saved value will be loaded lazily on first access
        self.currentLevel = .info
        
        // Create OS logger for system console
        self.osLogger = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.truchiemu", category: "TruchiEmu")
        
        // Initialize file logging
        setupFileLogging()
        
        // Register the C callback so libretro core logs (LibretroDB, Identify, Bridge, etc.)
        // are routed through LoggerService and written to the log file.
        RegisterCoreLogCallback(g_coreLogCallback)
        
        // Mark as initialized - now we can safely write to AppSettings
        self.isInitialized = true
        
        // Try to load saved log level after init completes (won't cause circular dep)
        Task { @MainActor in
            let rawLevel = AppSettings.get("log_level", type: String.self) ?? "info"
            await MainActor.run {
                self.currentLevel = LogLevel(rawValue: rawLevel) ?? .info
            }
        }
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
        
        // Use default log URL initially to avoid circular dependency
        // (LogManager.currentLogURL would read AppSettings, which isn't ready yet)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logDir = appSupport.appendingPathComponent("TruchiEmu/Logs")
        let logURL = logDir.appendingPathComponent("TruchiEmu.log")
        
        let ts = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone.current)
        
        // Use os_log for setup messages so they go to system console, and also format for file
        let tsMsg = "\(ts) [SETUP] [Logger] Setting up file logging at: \(logURL.path)"
        print(tsMsg)
        
        do {
            // Ensure directory exists
            let directoryURL = logURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                print("\(ts) [SETUP] [Logger] Creating directory: \(directoryURL.path)")
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            
  // Open file for appending
  if !FileManager.default.fileExists(atPath: logURL.path) {
    print("\(ts) [SETUP] [Logger] Creating log file at: \(logURL.path)")
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
  }

  logFileHandle = try FileHandle(forWritingTo: logURL)
  currentLogURL = logURL  // Cache the URL for thread-safe access
  logFileHandle?.seekToEndOfFile()

  print("\(ts) [SETUP] [Logger] File handle opened successfully, log file ready")
            
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
            print("\(ts) [SETUP] [Logger] Start markers written successfully")
            
        } catch {
            print("\(ts) [SETUP] [ERROR] [Logger] ERROR setting up file logging: \(error.localizedDescription)")
            print("\(ts) [SETUP] [ERROR] [Logger] Log URL: \(logURL.path)")
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
    
    // Log at INFO level: general logs, games running, downloads, file operations, save/load states, zipping, online operations.
    static func info(_ message: String) {
        shared.log(.info, category: "App", message: message)
    }
    
    // Log at INFO level with a specific category.
    static func info(category: String, _ message: String) {
        shared.log(.info, category: category, message: message)
    }
    
    // Log at DEBUG level: more detailed logs for troubleshooting.
    static func debug(_ message: String) {
        shared.log(.debug, category: "App", message: message)
    }
    
    // Log at DEBUG level with a specific category.
    static func debug(category: String, _ message: String) {
        shared.log(.debug, category: category, message: message)
    }
    
    // Log at EXTREME level: every frame, timing data, etc.
    static func extreme(_ message: String) {
        shared.log(.extreme, category: "App", message: message)
    }
    
    // Log at EXTREME level with a specific category.
    static func extreme(category: String, _ message: String) {
        shared.log(.extreme, category: category, message: message)
    }

    // Log at ERROR level (logged as .info to always appear, tagged with [ERROR]).
    static func error(_ message: String) {
        let ts = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone.current)
        let formatted = "\(ts) [ERROR] [App] \(message)"
        print(formatted)
        shared.logFileQueue.async {
            shared.writeToFile(formatted + "\n")
        }
    }

    // Log at ERROR level with a specific category (logged as .info to always appear, tagged with [ERROR]).
    static func error(category: String, _ message: String) {
        let ts = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone.current)
        let formatted = "\(ts) [ERROR] [\(category)] \(message)"
        print(formatted)
        shared.logFileQueue.async {
            shared.writeToFile(formatted + "\n")
        }
    }
    
    // Log at WARNING level.
    static func warning(_ message: String) {
        let ts = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone.current)
        let formatted = "\(ts) [WARN] [App] \(message)"
        print(formatted)
        shared.logFileQueue.async {
            shared.writeToFile(formatted + "\n")
        }
    }
    
    // MARK: - Core Log Bridge (exposed to C)
    
    // Log at WARNING level with category.
    static func warning(category: String, _ message: String) {
        let ts = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone.current)
        let formatted = "\(ts) [WARN] [\(category)] \(message)"
        print(formatted)
        shared.logFileQueue.async {
            shared.writeToFile(formatted + "\n")
        }
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
        
        // Note: os_log removed — print + file logging is sufficient and avoids duplicate output
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
    
  fileprivate func writeToFile(_ text: String) {
    guard let data = text.data(using: .utf8) else {
      return
    }

    // Check file size and trim if needed, then write
    do {
      // Use the current handle (may be rebuilt by rotation)
      guard let handle = logFileHandle else { return }
      try handle.seekToEnd()
      // Check if file needs rotation before writing (may rebuild handle)
      checkAndTrimLogFile(handle: handle)
      // Get fresh handle in case it was replaced during rotation
      guard let freshHandle = logFileHandle else { return }
      freshHandle.write(data)
    } catch {
      // File handle is stale (file was deleted/rotated), reopen it
      _rebuildFileHandle()
      guard let freshHandle = logFileHandle else { return }
      do {
        try freshHandle.seekToEnd()
        freshHandle.write(data)
      } catch {}
    }
  }
    
  // Rebuild the file handle if it becomes stale (e.g., after file deletion).
  private func _rebuildFileHandle() {
    logFileHandle?.closeFile()
    logFileHandle = nil
    guard let logURL = currentLogURL else {
      LoggerService.warning(category: "Logger", "Cannot rebuild handle: URL not cached")
      return
    }
    do {
      if !FileManager.default.fileExists(atPath: logURL.path) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
      }
      logFileHandle = try FileHandle(forWritingTo: logURL)
      try logFileHandle?.seekToEnd()
    } catch {
      // If reopening fails, leave handle as nil; writeToFile will be a no-op
    }
  }
    
    private func checkAndTrimLogFile(handle: FileHandle) {
        // Check file size
        let currentSize: UInt64
        do {
            try handle.seekToEnd()
            currentSize = try handle.offset()
        } catch {
            // File handle is stale
            _rebuildFileHandle()
            return
        }
        
        if currentSize >= maxLogSizeBytes {
            rotateLogFile()
        }
    }
    
  private func rotateLogFile() {
    guard let logURL = currentLogURL else {
      LoggerService.warning(category: "Logger", "Cannot rotate log: URL not cached")
      return
    }
    
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
    
    // Trim a log file to keep only the most recent N lines.
    private func trimFileToRecentEntries(at url: URL, maxLines: Int) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        let recentLines = lines.suffix(maxLines)
        let trimmed = recentLines.joined(separator: "\n")
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - File Management (called from main thread)
    
    // Trim the current log file to remove entries older than N days.
    func trimOldEntries(olderThanDays days: Int) {
        logFileQueue.async { [weak self] in
            self?._trimOldEntriesSync(olderThanDays: days)
        }
    }
    
  private func _trimOldEntriesSync(olderThanDays days: Int) {
    guard let logURL = currentLogURL else {
      LoggerService.warning(category: "Logger", "Cannot trim entries: URL not cached")
      return
    }
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
    
  // Clear all log files (current and rotated).
  func clearAllLogs() {
    logFileQueue.async { [weak self] in
      guard let self = self else { return }
      guard let logURL = self.currentLogURL else {
        LoggerService.warning(category: "Logger", "Cannot clear logs: URL not cached")
        return
      }

      // Close current handle
      self.logFileHandle?.closeFile()
      self.logFileHandle = nil

      // Remove all log files
      try? FileManager.default.removeItem(at: logURL)
      try? FileManager.default.removeItem(at: logURL.appendingPathExtension("1"))
      try? FileManager.default.removeItem(at: logURL.appendingPathExtension("2"))

      // Re-setup logging
      self._setupFileLoggingSync()
    }
  }
    
    // Get the current log file size in bytes.
    func currentLogFileSize() -> Int64 {
        let logURL = LogManager.shared.currentLogURL
        return (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int64) ?? 0
    }
    
    // Get total size of all log files (current + rotated).
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
    
    // Get age of the current log file.
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