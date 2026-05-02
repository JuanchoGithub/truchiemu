import Foundation

// MARK: - MAME Genre Service
//
// Applies genre metadata from Progetto-SNAPS to MAME ROMs during import/scan.
// Follows your preference: only set genre if empty (LaunchBox takes priority).
//
@MainActor
final class MAMEGenreService: ObservableObject {
    static let shared = MAMEGenreService()

    private let snapsService = ProgettoSnapsService.shared

    // Known MAME system IDs
    private let mameSystemIDs: Set<String> = ["mame", "arcade", "mame078", "mame2010", "mame2016"]

    // MARK: - Public API

    /// Check if a system ID is MAME.
    func isMAME(_ systemID: String?) -> Bool {
        guard let id = systemID?.lowercased() else { return false }
        return mameSystemIDs.contains(id)
    }

    /// Extract short name from ROM filename (without .zip extension).
    func extractShortName(from filename: String) -> String {
        // Handle .zip files: "sf2.zip" -> "sf2"
        if filename.lowercased().hasSuffix(".zip") {
            let name = String(filename.dropLast(4))
            return name.lowercased()
        }

        // Handle other extensions
        if let dotIndex = filename.lastIndex(of: ".") {
            return String(filename[..<dotIndex]).lowercased()
        }

        return filename.lowercased()
    }

    /// Apply genre metadata to a ROM if it needs it and is a MAME ROM.
    /// Only applies if genre is currently empty (LaunchBox takes priority).
    func applyGenreIfNeeded(
        rom: ROMEntry,
        metadataEntry: ROMMetadataEntry
    ) async {
        // Verify it's a MAME ROM
        guard isMAME(rom.systemID) else { return }

        // Only set genre if empty (LaunchBox priority)
        guard metadataEntry.genre == nil else {
            LoggerService.debug(category: "MAMEGenre", "Skipping \(rom.name) - genre already set")
            return
        }

        // Extract short name for lookup
        let shortName = extractShortName(from: rom.name)

        // Get genre from Progetto-SNAPS
        guard let genre = snapsService.getGenre(for: shortName) else {
            LoggerService.debug(category: "MAMEGenre", "No genre found for \(shortName)")
            return
        }

        // Apply genre
        metadataEntry.genre = genre

        LoggerService.debug(category: "MAMEGenre", "Applied genre '\(genre)' to \(shortName)")
    }

    /// Batch apply genre metadata to multiple ROMs.
    /// Called during library scan/import.
    func applyGenreToAll(
        roms: [ROMEntry],
        metadataEntries: [ROMMetadataEntry],
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async {
        let total = roms.count
        var processed = 0

        for (rom, metadata) in zip(roms, metadataEntries) {
            await applyGenreIfNeeded(rom: rom, metadataEntry: metadata)

            processed += 1
            if processed % 50 == 0 {
                progressHandler?(processed, total)
            }
        }

        progressHandler?(total, total)
    }

    /// Check if the library contains any MAME ROMs.
    func hasMAMEROMs(in library: ROMLibrary) -> Bool {
        library.roms.contains { isMAME($0.systemID) }
    }

    // MARK: - Initialization

    private init() {}
}