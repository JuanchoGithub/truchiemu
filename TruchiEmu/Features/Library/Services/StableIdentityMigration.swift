import Foundation

// One-shot migration to stable game identity. Versioned: each version runs
// once ever, on the first launch after the update that introduced it.
//
// v1: relinked legacy "<displayName>__<uuid8>" files to stable keys,
//     persisted the stableKey column, wrote the first metadata backup.
// v2: cross-system relink. Catches files stranded by a system change
//     (gb ROM with saves under gbc/, late identification under default/)
//     which v1 only matched within the same system directory.
// v3: backfill fallback keys. Games whose files still live under their
//     same-UUID legacy key (never re-added, so the UUID never changed)
//     or under a pre-hash stem key get stable copies now.
// v4: fixed name normalization in match tiers 8/9 (file keys use
//     underscores, display names use spaces). Re-runs the match so
//     extension-named saves (GoldenEye.z64, Donkey Kong.nes, psx cues)
//     link to their games.
//
// Later launches skip via the version flag. Reads already merge legacy
// keys, so games work even before this runs.
@MainActor
enum StableIdentityMigration {
    private static let versionKey = "stableIdentity.migrationVersion"
    private static let currentVersion = 4

    static func runIfNeeded(library: ROMLibrary) {
        guard AppSettings.getInt(versionKey, defaultValue: 0) < currentVersion else { return }
        // Claim first: never run twice, even if a step below throws.
        AppSettings.setInt(versionKey, value: currentVersion)
        guard !library.roms.isEmpty else { return }

        let report = SaveStateReconciler.shared.relink(
            roms: library.roms.map { $0.stableRomRef }
        )
        // Persists stableKey on all rows and writes the backup file.
        // XML is unchanged by this migration, so skip rewriting it.
        library.saveROMsToDatabase(updateXML: false)

        LoggerService.info(
            category: "StableIdentityMigration",
            "v\(currentVersion): relinked \(report.filesCopied) file(s) for " +
            "\(report.gamesFixed) game(s), skipped \(report.skipped)."
        )
    }
}
