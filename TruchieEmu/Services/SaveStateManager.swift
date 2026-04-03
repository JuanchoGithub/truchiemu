import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers
import Compression

// MARK: - Slot Info

/// Represents a single save state slot's metadata
struct SlotInfo: Identifiable, Equatable {
    let id: Int  // slot number (0-9, -1 for auto)
    let exists: Bool
    let fileSize: Int64?
    let modificationDate: Date?
    
    /// Computed: display slot name (or "Auto" for slot -1)
    var displayName: String {
        if id == -1 { return "Auto" }
        return "Slot \(id)"
    }
}

// MARK: - Save State Manager

/// Centralized manager for save state file I/O and directory management.
/// 
/// Directory structure:
/// ```
/// ~/Library/Application Support/TruchieEmu/saves/states/<SystemID>/
///     GameName.state          (slot 0)
///     GameName.state1         (slot 1)
///     GameName.state2         (slot 2)
///     GameName.state1.png     (thumbnail for slot 1)
/// ```
/// 
/// Marked `@unchecked Sendable` because all file operations are thread-safe (FileManager handles them).
class SaveStateManager: ObservableObject, @unchecked Sendable {
    
    // MARK: - Published State
    
    /// Base directory for all save states
    let savesDirectory: URL
    
    // MARK: - Initialization
    
    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.savesDirectory = appSupport
            .appendingPathComponent("TruchieEmu")
            .appendingPathComponent("saves")
            .appendingPathComponent("states")
        
        ensureDirectoriesExist()
    }
    
    // MARK: - Directory Management
    
    /// Ensures the base save states directory exists
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
    
    /// Returns the system-specific subdirectory, creating it if needed
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
    
    /// Returns the full URL for a save state file
    /// - Parameters:
    ///   - gameName: The display name of the game (used for filename)
    ///   - systemID: The system identifier (used for subdirectory)
    ///   - slot: Slot number (0-9 for user slots, -1 for auto-save)
    /// - Returns: URL to the .state file
    func statePath(gameName: String, systemID: String, slot: Int) -> URL {
        let sysDir = systemDirectory(systemID: systemID)
        let safeName = safeGameStateName(gameName)
        
        let fileName: String
        if slot == -1 {
            // Auto-save: just ".state" extension (no number)
            fileName = "\(safeName).state"
        } else if slot == 0 {
            // Slot 0: same as auto for convenience (no number)
            fileName = "\(safeName).state"
        } else if slot >= 1 && slot <= 9 {
            // Slots 1-9: ".state1" through ".state9"
            fileName = "\(safeName).state\(slot)"
        } else {
            // Fallback for any other slot number
            fileName = "\(safeName).state\(slot)"
        }
        
        return sysDir.appendingPathComponent(fileName)
    }
    
    /// Returns the full URL for a save state thumbnail
    /// - Parameters:
    ///   - gameName: The display name of the game
    ///   - systemID: The system identifier
    ///   - slot: Slot number
    /// - Returns: URL to the .png thumbnail file
    func thumbnailPath(gameName: String, systemID: String, slot: Int) -> URL {
        let stateURL = statePath(gameName: gameName, systemID: systemID, slot: slot)
        return stateURL.appendingPathExtension("png")
    }
    
    // MARK: - Slot Information
    
    /// Returns info for a specific slot
    func slotInfo(gameName: String, systemID: String, slot: Int) -> SlotInfo {
        let path = statePath(gameName: gameName, systemID: systemID, slot: slot)
        let fm = FileManager.default
        
        guard let attrs = try? fm.attributesOfItem(atPath: path.path) else {
            return SlotInfo(id: slot, exists: false, fileSize: nil, modificationDate: nil)
        }
        
        return SlotInfo(
            id: slot,
            exists: true,
            fileSize: attrs[.size] as? Int64,
            modificationDate: attrs[.modificationDate] as? Date
        )
    }
    
    /// Returns info for all user slots (0-9) plus auto slot (-1)
    func allSlotInfo(gameName: String, systemID: String) -> [SlotInfo] {
        // Slots -1 (auto), 0-9
        return (-1...9).map { slot in
            slotInfo(gameName: gameName, systemID: systemID, slot: slot)
        }
    }
    
    /// Returns only user slots with existing save files, useful for cleanup
    func existingSlots(gameName: String, systemID: String) -> [SlotInfo] {
        allSlotInfo(gameName: gameName, systemID: systemID).filter { $0.exists }
    }
    
    // MARK: - File Operations
    
    /// Checks if a save state exists for the given slot
    func hasState(gameName: String, systemID: String, slot: Int) -> Bool {
        let path = statePath(gameName: gameName, systemID: systemID, slot: slot)
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    /// Deletes a save state file for a specific slot
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
    }
    
    /// Deletes all save states for a specific game
    func deleteAllStates(gameName: String, systemID: String) throws {
        let sysDir = systemDirectory(systemID: systemID)
        let safeName = safeGameStateName(gameName)
        
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(atPath: sysDir.path)
        
        for item in contents {
            if item.hasPrefix("\(safeName).state") {
                let fileURL = sysDir.appendingPathComponent(item)
                try fm.removeItem(at: fileURL)
            }
        }
    }
    
    /// Returns total size of all save states on disk (in bytes)
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
    
    /// Save a thumbnail image for a save state slot
    /// - Parameters:
    ///   - image: The NSImage to save as thumbnail
    ///   - gameName: The display name of the game
    ///   - systemID: The system identifier
    ///   - slot: Slot number
    func saveThumbnail(_ image: NSImage, gameName: String, systemID: String, slot: Int) {
        let thumbURL = thumbnailPath(gameName: gameName, systemID: systemID, slot: slot)
        LoggerService.debug(category: "SaveStateManager", "Saving thumbnail: gameName='\(gameName)', systemID='\(systemID)', slot=\(slot), path: \(thumbURL.path)")
        
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
            LoggerService.debug(category: "SaveStateManager", "ERROR: Thumbnail file was not created")
            return
        }
    }
    
    /// Load a thumbnail image for a save state slot
    /// - Parameters:
    ///   - gameName: The display name of the game
    ///   - systemID: The system identifier
    ///   - slot: Slot number
    /// - Returns: The loaded NSImage, or nil if not found
    func loadThumbnail(gameName: String, systemID: String, slot: Int) -> NSImage? {
        let thumbURL = thumbnailPath(gameName: gameName, systemID: systemID, slot: slot)
        LoggerService.debug(category: "SaveStateManager", "Loading thumbnail: gameName='\(gameName)', systemID='\(systemID)', slot=\(slot)")
        
        // Also check what other files exist in the directory
        if !FileManager.default.fileExists(atPath: thumbURL.path) {
            let dir = thumbURL.deletingLastPathComponent()
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                LoggerService.debug(category: "SaveStateManager", "Thumbnail not found, directory contents: \(contents)")
            }
        }
        
        guard FileManager.default.fileExists(atPath: thumbURL.path) else { return nil }
        return NSImage(contentsOf: thumbURL)
    }
    
    /// Delete a thumbnail for a save state slot
    func deleteThumbnail(gameName: String, systemID: String, slot: Int) throws {
        let thumbURL = thumbnailPath(gameName: gameName, systemID: systemID, slot: slot)
        if FileManager.default.fileExists(atPath: thumbURL.path) {
            try FileManager.default.removeItem(at: thumbURL)
        }
    }
    
    // MARK: - Helpers
    
    /// Sanitize game name to be filesystem-safe
    private func safeGameStateName(_ name: String) -> String {
        // Remove dangerous characters and use a consistent format
        let sanitized = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "..", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "unknown" : sanitized
    }
    
    /// Sanitize a path component
    private func safePathComponent(_ s: String) -> String {
        return safeGameStateName(s)
    }
    
    // MARK: - Compression Utilities
    
    /// Compressed save state format:
    /// - Bytes 0-3: Magic header "TCS2" (TruChie State v2)
    /// - Bytes 4-7: Original uncompressed size (UInt32, little-endian)
    /// - Bytes 8+:  LZ4 compressed data
    private static let compressedMagicHeader: [UInt8] = [0x54, 0x43, 0x53, 0x32] // "TCS2"
    
    /// Compress state data using LZ4 compression
    /// - Parameter data: Raw state data
    /// - Returns: Compressed data with magic header prefix, or raw data if compression fails
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
    
    /// Decompress state data
    /// - Parameter data: Compressed or raw state data
    /// - Returns: Decompressed data, or nil on failure
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
    /// Format bytes as a human-readable string (e.g., "15.2 MB")
    var formattedByteSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}

// MARK: - SlotInfo date formatting helper

extension SlotInfo {
    /// Formatted modification date string for UI display
    var formattedDate: String? {
        guard let date = modificationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}