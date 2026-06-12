import Foundation

enum CacheTTL: String, CaseIterable, Codable {
    case oneDay = "1d"
    case threeDays = "3d"
    case oneWeek = "1w"
    case twoWeeks = "2w"
    case oneMonth = "1m"
    case never = "never"

    var timeInterval: TimeInterval? {
        switch self {
        case .oneDay: return 86400
        case .threeDays: return 259200
        case .oneWeek: return 604800
        case .twoWeeks: return 1209600
        case .oneMonth: return 2592000
        case .never: return nil
        }
    }

    var displayName: String {
        switch self {
        case .oneDay: return "1 Day"
        case .threeDays: return "3 Days"
        case .oneWeek: return "1 Week"
        case .twoWeeks: return "2 Weeks"
        case .oneMonth: return "1 Month"
        case .never: return "Never"
        }
    }

    static var `default`: CacheTTL { .oneWeek }
}

@MainActor
final class ArchiveExtractor: ObservableObject {
    static let shared = ArchiveExtractor()

    private let fileManager = FileManager.default
    private let metadataFilename = ".metadata.json"

    private var baseDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchiEmu/ExtractedROMs")
    }

    private init() {
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    nonisolated static let archiveExtensions: Set<String> = ["zip", "7z", "rar"]

    nonisolated static func isArchive(url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static let archiveAwareCorePatterns: Set<String> = [
        "mame", "fbneo", "dosbox", "flycast"
    ]

    nonisolated static let archiveAwareSystemIDs: Set<String> = [
        "mame", "fba", "hbmame", "mess", "dice", "daphne",
        "dos", "dreamcast", "neogeo", "scummvm", "xrick"
    ]

    nonisolated static func isArchiveAwareCore(_ coreID: String) -> Bool {
        let lower = coreID.lowercased()
        return archiveAwareCorePatterns.contains { lower.contains($0) }
    }

    nonisolated static func isArchiveAwareSystem(_ systemID: String?) -> Bool {
        guard let systemID else { return false }
        return archiveAwareSystemIDs.contains(systemID)
    }

    struct TemporaryExtraction {
        let files: [URL]
        let tempDirectory: URL
    }

    func extractTemporary(url archiveURL: URL, systemID: String?) throws -> TemporaryExtraction {
        let ext = archiveURL.pathExtension.lowercased()
        guard Self.archiveExtensions.contains(ext) else {
            throw ArchiveError.notAnArchive
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TruchiEmu_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let success: Bool
        let fileCount: Int

        if ext == "zip" {
            let result = extractWithUnzip(archivePath: archiveURL.path, destPath: tempDir.path)
            if result {
                success = true
                fileCount = countExtractedFiles(in: tempDir)
            } else {
                let libResult = extractWithLibarchive(archivePath: archiveURL.path, destPath: tempDir.path)
                success = libResult.success != 0
                fileCount = Int(libResult.fileCount)
                if libResult.errorMessage != nil { free(libResult.errorMessage) }
            }
        } else {
            let libResult = extractWithLibarchive(archivePath: archiveURL.path, destPath: tempDir.path)
            success = libResult.success != 0
            fileCount = Int(libResult.fileCount)
            if !success, let errMsg = libResult.errorMessage {
                let msg = String(cString: errMsg, encoding: .utf8) ?? "Unknown error"
                try? fileManager.removeItem(at: tempDir)
                throw ArchiveError.extractionFailed(msg)
            }
            if libResult.errorMessage != nil { free(libResult.errorMessage) }
        }

        if !success {
            try? fileManager.removeItem(at: tempDir)
            throw ArchiveError.extractionFailed("All extraction methods failed for \(archiveURL.lastPathComponent)")
        }

        if fileCount == 0 {
            try? fileManager.removeItem(at: tempDir)
            throw ArchiveError.emptyArchive
        }

        let files = collectROMFiles(in: tempDir)
        LoggerService.debug(category: "ArchiveExtractor", "Temp extraction: \(archiveURL.lastPathComponent) (\(fileCount) files)")
        return TemporaryExtraction(files: files, tempDirectory: tempDir)
    }

    func extract(url archiveURL: URL, systemID: String?) throws -> [URL] {
        let ext = archiveURL.pathExtension.lowercased()
        guard Self.archiveExtensions.contains(ext) else {
            throw ArchiveError.notAnArchive
        }

        let cacheDir = cacheDirectory(for: archiveURL)

        if let cached = validateCache(at: cacheDir, sourceURL: archiveURL) {
            touchAccessDate(at: cacheDir)
            LoggerService.debug(category: "ArchiveExtractor", "Cache hit for \(archiveURL.lastPathComponent)")
            return cached
        }

        try? fileManager.removeItem(at: cacheDir)
        try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let success: Bool
        let fileCount: Int

        if ext == "zip" {
            let result = extractWithUnzip(archivePath: archiveURL.path, destPath: cacheDir.path)
            if result {
                success = true
                fileCount = countExtractedFiles(in: cacheDir)
            } else {
                let libResult = extractWithLibarchive(archivePath: archiveURL.path, destPath: cacheDir.path)
                success = libResult.success != 0
                fileCount = Int(libResult.fileCount)
                if !success, let errMsg = libResult.errorMessage {
                    let msg = String(cString: errMsg, encoding: .utf8) ?? "Unknown error"
                    LoggerService.info(category: "ArchiveExtractor", "libarchive fallback also failed: \(msg)")
                }
                if libResult.errorMessage != nil { free(libResult.errorMessage) }
            }
        } else {
            let libResult = extractWithLibarchive(archivePath: archiveURL.path, destPath: cacheDir.path)
            success = libResult.success != 0
            fileCount = Int(libResult.fileCount)
            if !success, let errMsg = libResult.errorMessage {
                let msg = String(cString: errMsg, encoding: .utf8) ?? "Unknown error"
                throw ArchiveError.extractionFailed(msg)
            }
            if libResult.errorMessage != nil { free(libResult.errorMessage) }
        }

        if !success {
            try? fileManager.removeItem(at: cacheDir)
            throw ArchiveError.extractionFailed("All extraction methods failed for \(archiveURL.lastPathComponent)")
        }

        if fileCount == 0 {
            try? fileManager.removeItem(at: cacheDir)
            throw ArchiveError.emptyArchive
        }

        writeMetadata(to: cacheDir, sourceURL: archiveURL)
        LoggerService.info(category: "ArchiveExtractor", "Extracted \(archiveURL.lastPathComponent) (\(fileCount) files)")

        return collectROMFiles(in: cacheDir)
    }

    func listContents(url archiveURL: URL) -> [String]? {
        let ext = archiveURL.pathExtension.lowercased()
        guard Self.archiveExtensions.contains(ext) else { return nil }

        if ext == "zip" {
            if let native = peekZipNative(url: archiveURL) {
                return native
            }
        }

        return listWithLibarchive(archivePath: archiveURL.path)
    }

    func cleanExpiredCache() {
        let ttlString = AppSettings.getString("extractedRomCacheTTL", defaultValue: CacheTTL.default.rawValue) ?? CacheTTL.default.rawValue
        let ttl = CacheTTL(rawValue: ttlString) ?? .default
        guard let maxAge = ttl.timeInterval else { return }

        guard let contents = try? fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }

        let now = Date()
        let runningPaths = Set(RunningGamesTracker.shared.runningGames.keys)

        for dir in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            if runningPaths.contains(where: { $0.contains(dir.lastPathComponent) }) { continue }

            let metadataFile = dir.appendingPathComponent(metadataFilename)
            var accessDate: Date?
            if let data = try? Data(contentsOf: metadataFile),
               let meta = try? JSONDecoder().decode(CacheMetadata.self, from: data) {
                accessDate = meta.lastAccessed
            }

            if accessDate == nil {
                accessDate = (try? fileManager.attributesOfItem(atPath: dir.path))?[.modificationDate] as? Date
            }

            guard let accessDate else { continue }

            if now.timeIntervalSince(accessDate) > maxAge {
                try? fileManager.removeItem(at: dir)
                LoggerService.debug(category: "ArchiveExtractor", "Expired cache removed: \(dir.lastPathComponent)")
            }
        }
    }

    func cleanAllCache() {
        try? fileManager.removeItem(at: baseDirectory)
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    func cacheSize() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return 0 }
        var total: Int64 = 0
        for dir in contents {
            total += directorySize(at: dir)
        }
        return total
    }

    func removeCacheFor(archiveURL: URL) {
        let dir = cacheDirectory(for: archiveURL)
        try? fileManager.removeItem(at: dir)
    }

    private func cacheDirectory(for archiveURL: URL) -> URL {
        let hash = sha256(archiveURL.path)
        return baseDirectory.appendingPathComponent(hash)
    }

    private func validateCache(at cacheDir: URL, sourceURL: URL) -> [URL]? {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: cacheDir.path, isDirectory: &isDir), isDir.boolValue else { return nil }

        let metadataFile = cacheDir.appendingPathComponent(metadataFilename)
        guard let data = try? Data(contentsOf: metadataFile),
              let meta = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
            return nil
        }

        let currentModDate = (try? fileManager.attributesOfItem(atPath: sourceURL.path))?[.modificationDate] as? Date
        if let cached = meta.sourceModDate, let current = currentModDate {
            if abs(cached.timeIntervalSince(current)) > 1.0 { return nil }
        }

        let files = collectROMFiles(in: cacheDir)
        return files.isEmpty ? nil : files
    }

    private func writeMetadata(to cacheDir: URL, sourceURL: URL) {
        let modDate = (try? fileManager.attributesOfItem(atPath: sourceURL.path))?[.modificationDate] as? Date
        let meta = CacheMetadata(
            created: Date(),
            lastAccessed: Date(),
            sourcePath: sourceURL.path,
            sourceModDate: modDate,
            originalExtension: sourceURL.pathExtension.lowercased()
        )
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: cacheDir.appendingPathComponent(metadataFilename))
        }
    }

    private func touchAccessDate(at cacheDir: URL) {
        let metadataFile = cacheDir.appendingPathComponent(metadataFilename)
        guard let data = try? Data(contentsOf: metadataFile),
              var meta = try? JSONDecoder().decode(CacheMetadata.self, from: data) else { return }
        meta.lastAccessed = Date()
        if let updated = try? JSONEncoder().encode(meta) {
            try? updated.write(to: metadataFile)
        }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: cacheDir.path)
    }

    private func collectROMFiles(in directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let filename = url.lastPathComponent
            if filename == metadataFilename { continue }
            if filename.hasPrefix(".") { continue }
            var isRegular: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isRegular), !isRegular.boolValue {
                files.append(url)
            }
        }
        return files
    }

    private func countExtractedFiles(in directory: URL) -> Int {
        collectROMFiles(in: directory).count
    }

    private func directorySize(at url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
        for case let fileURL as URL in enumerator {
            if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               attrs.isRegularFile == true,
               let size = attrs.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func extractWithUnzip(archivePath: String, destPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", archivePath, "-d", destPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            LoggerService.info(category: "ArchiveExtractor", "/usr/bin/unzip failed: \(error)")
            return false
        }
    }

    private func extractWithLibarchive(archivePath: String, destPath: String) -> ArchiveExtractResult {
        archive_extract_to_dir(archivePath, destPath)
    }

    private func listWithLibarchive(archivePath: String) -> [String]? {
        var list = archive_list_files(archivePath)
        guard list.count > 0, let entries = list.entries else {
            archive_file_list_free(&list)
            return nil
        }

        var names: [String] = []
        for i in 0..<Int(list.count) {
            if let cStr = entries[i], let name = String(cString: cStr, encoding: .utf8) {
                if !name.hasSuffix("/") {
                    names.append(name)
                }
            }
        }
        archive_file_list_free(&list)
        return names.isEmpty ? nil : names
    }

    private func peekZipNative(url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: 0)

        let eocdSearchSize: UInt64 = 65536
        let readStart = fileSize > eocdSearchSize ? fileSize - eocdSearchSize : 0
        let readLen = Int(fileSize - readStart)

        try? handle.seek(toOffset: readStart)
        guard let tailData = try? handle.read(upToCount: readLen), tailData.count >= 22 else { return nil }

        let eocdSig: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        guard let eocdRange = tailData.range(of: Data(eocdSig), options: .backwards) else { return nil }
        let eocdOffset = eocdRange.lowerBound

        guard eocdOffset + 22 <= tailData.count else { return nil }

        func readLE16(_ data: Data, at offset: Int) -> UInt16 {
            guard offset + 2 <= data.count else { return 0 }
            return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        }
        func readLE32(_ data: Data, at offset: Int) -> UInt32 {
            guard offset + 4 <= data.count else { return 0 }
            return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
        }

        let cdSize = readLE32(tailData, at: eocdOffset + 12)
        let cdOffset = readLE32(tailData, at: eocdOffset + 16)
        let numEntries = readLE16(tailData, at: eocdOffset + 10)

        guard cdSize > 0, cdOffset < fileSize, numEntries > 0 else { return nil }

        try? handle.seek(toOffset: UInt64(cdOffset))
        let readSize = min(Int(cdSize), 1_048_576)
        guard let cdData = try? handle.read(upToCount: readSize) else { return nil }

        var filenames: [String] = []
        var offset = 0
        let cdSig: UInt32 = 0x02014b50
        let maxEntries = 200

        while filenames.count < maxEntries {
            guard offset + 46 <= cdData.count else { break }
            let sig = readLE32(cdData, at: offset)
            guard sig == cdSig else { break }
            let nameLen = Int(readLE16(cdData, at: offset + 28))
            let extraLen = Int(readLE16(cdData, at: offset + 30))
            let commentLen = Int(readLE16(cdData, at: offset + 32))
            guard offset + 46 + nameLen <= cdData.count else { break }
            let nameData = cdData[offset + 46 ..< offset + 46 + nameLen]
            if let name = String(data: nameData, encoding: .utf8), !name.hasSuffix("/") {
                filenames.append(name)
            }
            offset += 46 + nameLen + extraLen + commentLen
        }

        return filenames.isEmpty ? nil : filenames
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

private let CC_SHA256_DIGEST_LENGTH = 32
private typealias CC_LONG = UInt32
@_silgen_name("CC_SHA256") private func CC_SHA256(_ data: UnsafeRawPointer?, _ len: CC_LONG, _ out: UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8>?

struct CacheMetadata: Codable {
    let created: Date
    var lastAccessed: Date
    let sourcePath: String
    let sourceModDate: Date?
    let originalExtension: String
}

enum ArchiveError: LocalizedError {
    case notAnArchive
    case emptyArchive
    case extractionFailed(String)
    case passwordProtected

    var errorDescription: String? {
        switch self {
        case .notAnArchive: return "File is not a supported archive format"
        case .emptyArchive: return "Archive contains no files"
        case .extractionFailed(let reason): return "Extraction failed: \(reason)"
        case .passwordProtected: return "Archive is password-protected"
        }
    }
}
