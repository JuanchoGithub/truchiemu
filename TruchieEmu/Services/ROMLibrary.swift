import Foundation
import Combine

@MainActor
class ROMLibrary: ObservableObject {
    @Published var roms: [ROM] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    @Published var hasCompletedOnboarding: Bool
    @Published var romFolderURL: URL?

    // File signature index for smart rescan
    private struct FileSignature: Codable, Hashable { let size: Int64; let modTime: TimeInterval }
    private let indexKey = "rom_file_index_v1"
    private var fileIndex: [String: FileSignature] = [:] // path -> signature

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let romsKey = "saved_roms"
    private let onboardingKey = "has_completed_onboarding"
    private let folderKey = "rom_folder_bookmark"

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
        loadROMsFromDisk()
        restoreROMFolderAccess()
        loadFileIndex()
    }

    func completeOnboarding(folderURL: URL) {
        self.romFolderURL = folderURL
        saveSecurityScopedBookmark(for: folderURL)
        hasCompletedOnboarding = true
        defaults.set(true, forKey: onboardingKey)
        Task { await scanROMs(in: folderURL) }
    }

    func scanROMs(in folder: URL) async {
        isScanning = true
        scanProgress = 0
        let scanner = ROMScanner()
        let found = await scanner.scan(folder: folder) { progress in
            Task { @MainActor in self.scanProgress = progress }
        }
        // Merge: keep existing metadata, add new
        var existing = Dictionary(uniqueKeysWithValues: roms.map { ($0.path.path, $0) })
        for rom in found where existing[rom.path.path] == nil {
            existing[rom.path.path] = rom
        }
        roms = existing.values.sorted { $0.displayName < $1.displayName }
        isScanning = false
        saveROMsToDisk()
        Task { await BoxArtService.shared.batchDownloadBoxArtGoogle(for: self.roms, library: self) }
    }

    func updateROM(_ rom: ROM) {
        if let idx = roms.firstIndex(where: { $0.id == rom.id }) {
            roms[idx] = rom
            
            // Per user request: save rom info to <romname_info>.json in rom folder
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let meta = rom.metadata,
               let data = try? encoder.encode(meta) {
                try? data.write(to: rom.infoLocalPath)
            }
            
            saveROMsToDisk()
        }
    }

    func markPlayed(_ rom: ROM) {
        var updated = rom
        updated.lastPlayed = Date()
        updateROM(updated)
    }

    // MARK: - Persistence
    private func saveROMsToDisk() {
        if let data = try? encoder.encode(roms) {
            defaults.set(data, forKey: romsKey)
        }
    }

    private func loadROMsFromDisk() {
        guard let data = defaults.data(forKey: romsKey),
              let saved = try? decoder.decode([ROM].self, from: data) else { return }
        roms = saved
    }

    private func saveSecurityScopedBookmark(for url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) else { return }
        defaults.set(bookmark, forKey: folderKey)
    }

    private func restoreROMFolderAccess() {
        guard let bookmark = defaults.data(forKey: folderKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: bookmark,
                               options: .withSecurityScope,
                               relativeTo: nil,
                               bookmarkDataIsStale: &stale) {
            _ = url.startAccessingSecurityScopedResource()
            romFolderURL = url
        }
    }

    private func loadFileIndex() {
        if let data = defaults.data(forKey: indexKey),
           let idx = try? JSONDecoder().decode([String: FileSignature].self, from: data) {
            fileIndex = idx
        }
    }

    private func saveFileIndex() {
        if let data = try? JSONEncoder().encode(fileIndex) {
            defaults.set(data, forKey: indexKey)
        }
    }

    func rescanLibrary(at url: URL) async {
        isScanning = true
        scanProgress = 0

        // Enumerate current files
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                                             options: [.skipsHiddenFiles]) else { isScanning = false; return }

        var candidates: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]), vals.isRegularFile == true {
                candidates.append(fileURL)
            }
        }

        // Build new index and detect changes
        var newIndex: [String: FileSignature] = [:]
        var changed: [URL] = []
        for u in candidates {
            let path = u.path
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let mod = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let sig = FileSignature(size: size, modTime: mod)
            newIndex[path] = sig
            if fileIndex[path] != sig { changed.append(u) }
        }

        // Remove deleted
        let currentPaths = Set(candidates.map { $0.path })
        let deletedPaths = Set(roms.map { $0.path.path }).subtracting(currentPaths)
        if !deletedPaths.isEmpty {
            roms.removeAll { deletedPaths.contains($0.path.path) }
        }

        // Scan only changed/new files
        let scanner = ROMScanner()
        let imported = await scanner.scan(urls: changed) { p in
            Task { @MainActor in self.scanProgress = p }
        }

        // Merge
        var byPath = Dictionary(uniqueKeysWithValues: roms.map { ($0.path.path, $0) })
        for r in imported { byPath[r.path.path] = r }
        roms = byPath.values.sorted { $0.displayName < $1.displayName }

        // Save index and roms
        fileIndex = newIndex
        saveFileIndex()
        saveROMsToDisk()

        isScanning = false
        
        Task { await BoxArtService.shared.batchDownloadBoxArtGoogle(for: self.roms, library: self) }
    }
}
