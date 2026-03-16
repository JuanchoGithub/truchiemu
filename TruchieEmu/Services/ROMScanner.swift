import Foundation

actor ROMScanner {

    // Cancellation flag
    private var isCancelled = false

    // Call from UI to cancel an ongoing scan
    func cancel() {
        isCancelled = true
    }

    // Reset cancellation before starting a new scan
    private func resetCancellation() {
        isCancelled = false
    }

    func scan(folder: URL, progress: @escaping (Double) -> Void) async -> [ROM] {
        resetCancellation()
        var found: [ROM] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }
        let total = Double(allURLs.count)
        var processed = 0

        // Throttle progress updates (every 50ms)
        var lastProgressUpdate = DispatchTime.now()
        let throttleNanos: UInt64 = 50_000_000 // 50ms

        for url in allURLs {
            if isCancelled { break }

            processed += 1
            let now = DispatchTime.now()
            if now.uptimeNanoseconds - lastProgressUpdate.uptimeNanoseconds >= throttleNanos || processed == Int(total) {
                lastProgressUpdate = now
                progress(Double(processed) / max(total, 1))
            }

            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty else { continue }

            // Skip obviously non-ROM files
            let skip = ["txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3", "mp4", "avi", "mkv", "nfo", "dat", "db", "json"]
            if skip.contains(ext) { continue }

            let system = identifySystem(url: url, extension: ext)
            let name = url.deletingPathExtension().lastPathComponent

            var rom = ROM(
                id: UUID(),
                name: name,
                path: url,
                systemID: system?.id
            )

            // Load local metadata if exists
            if let data = try? Data(contentsOf: rom.infoLocalPath) {
                if let meta = try? JSONDecoder().decode(ROMMetadata.self, from: data) {
                    rom.metadata = meta
                }
            }
            
            // Check for local boxart
            if fm.fileExists(atPath: rom.boxArtLocalPath.path) {
                rom.boxArtPath = rom.boxArtLocalPath
            }

            found.append(rom)
        }

        // Final progress update
        progress(1.0)
        return found
    }

    // MARK: - System Identification

    private func identifySystem(url: URL, extension ext: String) -> SystemInfo? {
        // For ZIP files, peek inside to determine if it's MAME or a known compressed ROM
        if ext == "zip" || ext == "7z" {
            return identifyArchive(url: url)
        }
        return SystemDatabase.system(forExtension: ext)
    }

    private func identifyArchive(url: URL) -> SystemInfo? {
        // Check if zip is in a folder named after a known MAME system
        let parentName = url.deletingLastPathComponent().lastPathComponent.lowercased()
        if parentName.contains("mame") || parentName.contains("arcade") || parentName.contains("fba") {
            return SystemDatabase.system(forID: "mame")
        }

        // Try to peek at zip contents for known inner extensions
        if let innerExt = peekInsideZip(url: url) {
            return SystemDatabase.system(forExtension: innerExt)
        }

        // Default ZIP to MAME (arcade) since that's most common for ZIPs
        return SystemDatabase.system(forID: "mame")
    }

    private func peekInsideZip(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count >= 30 else { return nil }

        // Helpers to read little-endian integers safely without alignment assumptions
        func readLEUInt16(_ start: Int) -> UInt16? {
            guard start + 2 <= data.count else { return nil }
            var value: UInt16 = 0
            for i in 0..<2 { value |= UInt16(data[start + i]) << (8 * i) }
            return value
        }

        func readLEUInt32(_ start: Int) -> UInt32? {
            guard start + 4 <= data.count else { return nil }
            var value: UInt32 = 0
            for i in 0..<4 { value |= UInt32(data[start + i]) << (8 * i) }
            return value
        }

        var offset = 0
        let localHeaderSig: UInt32 = 0x04034b50 // ZIP local file header signature

        while true {
            guard offset + 30 <= data.count else { break }
            guard let sig = readLEUInt32(offset), sig == localHeaderSig else { break }

            // Local file header fields
            guard let compressedSize = readLEUInt32(offset + 18),
                  let fileNameLen = readLEUInt16(offset + 26),
                  let extraLen = readLEUInt16(offset + 28) else { break }

            let nameLen = Int(fileNameLen)
            let extra = Int(extraLen)
            let comp = Int(compressedSize)

            // Validate bounds for filename
            guard offset + 30 + nameLen <= data.count else { break }
            let nameData = data[offset + 30 ..< offset + 30 + nameLen]
            if let name = String(data: nameData, encoding: .utf8) {
                let innerExt = URL(fileURLWithPath: name).pathExtension.lowercased()
                if !innerExt.isEmpty, let system = SystemDatabase.system(forExtension: innerExt) {
                    return system.extensions.first
                }
            }

            // Advance to next header: fixed(30) + name + extra + data
            let next = offset + 30 + nameLen + extra + comp
            guard next > offset else { break } // avoid infinite loops on malformed input
            offset = next
        }

        return nil
    }

    // Scan only specific URLs (for smart rescan)
    func scan(urls: [URL], progress: @escaping (Double) -> Void) async -> [ROM] {
        resetCancellation()

        var found: [ROM] = []
        let total = Double(urls.count)
        var processed = 0
        let fm = FileManager.default

        // Throttle progress updates (every 50ms)
        var lastProgressUpdate = DispatchTime.now()
        let throttleNanos: UInt64 = 50_000_000 // 50ms

        for url in urls {
            if isCancelled { break }

            processed += 1
            let now = DispatchTime.now()
            if now.uptimeNanoseconds - lastProgressUpdate.uptimeNanoseconds >= throttleNanos || processed == Int(total) {
                lastProgressUpdate = now
                progress(Double(processed) / max(total, 1))
            }

            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty else { continue }

            // Skip obviously non-ROM files
            let skip = ["txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3", "mp4", "avi", "mkv", "nfo", "dat", "db", "json"]
            if skip.contains(ext) { continue }

            let system = identifySystem(url: url, extension: ext)
            let name = url.deletingPathExtension().lastPathComponent

            var rom = ROM(
                id: UUID(),
                name: name,
                path: url,
                systemID: system?.id
            )

            // Load local metadata if exists
            if let data = try? Data(contentsOf: rom.infoLocalPath) {
                if let meta = try? JSONDecoder().decode(ROMMetadata.self, from: data) {
                    rom.metadata = meta
                }
            }
            
            // Check for local boxart
            if fm.fileExists(atPath: rom.boxArtLocalPath.path) {
                rom.boxArtPath = rom.boxArtLocalPath
            }

            found.append(rom)
        }

        // Final progress update
        progress(1.0)
        return found
    }
}
