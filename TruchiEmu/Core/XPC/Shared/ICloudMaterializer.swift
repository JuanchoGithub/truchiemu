import Foundation

/// Detects and materializes iCloud "dataless" placeholder files.
///
/// When Desktop & Documents sync is on, macOS can evict a file's contents to
/// iCloud while leaving a placeholder on disk. `FileManager.fileExists(atPath:)`
/// still returns `true`, but any read fails until the OS downloads the data.
/// Emulator cores (e.g. Play! reading PS2 memory cards, or any core loading a
/// BIOS/save) then behave as if the file is missing/corrupt.
///
/// Use `ensureMaterialized(at:)` before handing a path to a core so the bytes
/// are guaranteed to be on local disk.
enum ICloudMaterializer {

    /// Returns `true` if the item at `url` is an iCloud placeholder whose
    /// contents are not yet downloaded to local storage.
    static func isDataless(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return false
        }
        guard values.isUbiquitousItem == true else {
            return false
        }
        // .current / .downloaded => bytes are local. .notDownloaded => placeholder.
        return values.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    /// Ensures the item at `url` has its contents available locally, downloading
    /// it from iCloud if it is a dataless placeholder. Blocks up to `timeout`
    /// seconds while the download completes.
    ///
    /// - Returns: `true` if the item exists and is (now) materialized, `false`
    ///   if it does not exist or could not be downloaded within `timeout`.
    @discardableResult
    static func ensureMaterialized(at url: URL, timeout: TimeInterval = 30) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return false }
        guard isDataless(url) else { return true }

        LoggerService.info(category: "iCloud", "Materializing dataless item: \(url.path)")
        do {
            try fm.startDownloadingUbiquitousItem(at: url)
        } catch {
            LoggerService.error(category: "iCloud", "startDownloadingUbiquitousItem failed for \(url.path): \(error.localizedDescription)")
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isDataless(url) {
                LoggerService.info(category: "iCloud", "Materialized: \(url.path)")
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        LoggerService.warning(category: "iCloud", "Timed out materializing: \(url.path)")
        return false
    }

    /// Recursively materializes every dataless placeholder under `directory`.
    /// Directories in iCloud can also contain evicted children (e.g. an entire
    /// PS2 memory-card folder), so this walks the tree and downloads each item.
    ///
    /// - Returns: `true` if the directory exists and all encountered items are
    ///   materialized, `false` if it does not exist or something timed out.
    @discardableResult
    static func ensureDirectoryMaterialized(at directory: URL, timeout: TimeInterval = 30) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        var allOK = true
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return ensureMaterialized(at: directory, timeout: timeout)
        }
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
            if !ensureMaterialized(at: child, timeout: timeout) {
                allOK = false
            }
        }
        return allOK
    }
}
