import Foundation

// Lightweight identity snapshot so the reconciler stays decoupled from ROM.
struct StableRomRef {
    let systemID: String
    let displayName: String
    let primaryToken: String
    let stemToken: String
    let legacyToken: String
    // Lowercased parent folder of the ROM file. Tie-breaks cross-system
    // matches (a gb ROM living in a gbc/ folder owns gbc/ save files).
    var folderName: String = ""
    // Lowercased ROM filename stem (inner archive path when present).
    // Proves same-file identity when the display title drifted through
    // enrichment ("007 - GoldenEye" on disk vs "GoldenEye 007" shown).
    var fileStem: String = ""
    // All lowercased ROM path components. A component equal to the save
    // directory name proves the same file (ROMs usually live in genre
    // subfolders, so the immediate parent alone is not enough).
    var pathComponents: [String] = []
    // Lowercased ROM file extension. Disambiguates "1942.zip" (mame zip)
    // from "1942" (nes ROM) when only the legacy display name remains.
    var fileExtension: String = ""
}

// Finds save-state files left behind under a pre-migration key
// ("<displayName>__<uuid8>" from before stable identity, or from a
// database loss and re-add) and copies them to the current stable key.
// Copies, never moves: the source files stay as a backup.
@MainActor
final class SaveStateReconciler {
    static let shared = SaveStateReconciler()

    struct OrphanGroup {
        let systemID: String
        let prefix: String
        let files: [String]

        // Human-readable game name: legacy "<name>__<8hex>" shows as <name>.
        var displayName: String {
            SaveStateReconciler.displayName(forPrefix: prefix)
        }
    }

    // Human-readable game name for a raw file prefix. Pure function.
    nonisolated static func displayName(forPrefix prefix: String) -> String {
        if StableGameIdentity.isLegacyKey(prefix),
           let range = prefix.range(of: "__", options: .backwards) {
            return String(prefix[..<range.lowerBound])
        }
        return prefix
    }

    struct Report {
        var systemsScanned = 0
        var orphansFound = 0
        var filesCopied = 0
        var gamesFixed = 0
        var skipped = 0
        var fixedGames: [String] = []
    }

    private let saveStates = SaveStateManager()
    private let lastAutoRunKey = "saveStateReconciler.lastAutoRun"

    // List orphan groups without touching files. Used by the repair UI preview.
    func scan(roms: [StableRomRef]) -> [OrphanGroup] {
        var groups: [OrphanGroup] = []
        let bySystem = Dictionary(grouping: roms) { $0.systemID }
        for systemID in saveStates.systemsWithSaves() {
            let refs = bySystem[systemID] ?? []
            guard let files = listFiles(inSystem: systemID) else { continue }
            groups += orphanGroups(files: files, refs: refs).map {
                OrphanGroup(systemID: systemID, prefix: $0.key, files: $0.value)
            }
        }
        return groups.sorted { $0.systemID < $1.systemID }
    }

    // Orphan groups no game claims: neither same- nor cross-system match.
    // Legacy sources of already-rescued games are NOT listed here (their
    // stable copies exist; the sources stay as backup). What remains is
    // files a relink cannot rescue, usually because the ROM is gone from
    // the library. Used by the repair UI report.
    func unlinked(roms: [StableRomRef]) -> [OrphanGroup] {
        var result: [OrphanGroup] = []
        let bySystem = Dictionary(grouping: roms) { $0.systemID }
        for systemID in saveStates.systemsWithSaves() {
            let refs = bySystem[systemID] ?? []
            guard let files = listFiles(inSystem: systemID) else { continue }
            for (prefix, groupFiles) in orphanGroups(files: files, refs: refs) {
                if bestMatch(prefix: prefix, dir: systemID, roms: roms) != nil { continue }
                result.append(OrphanGroup(systemID: systemID, prefix: prefix, files: groupFiles))
            }
        }
        return result.sorted {
            $0.systemID == $1.systemID ? $0.prefix < $1.prefix : $0.systemID < $1.systemID
        }
    }

    // Copy orphan files to each matched game's stable key. Safe to re-run:
    // existing destinations are skipped, sources are kept.
    // Pass 0 backfills fallback keys to the primary key: games whose files
    // still live under their same-UUID legacy key (never re-added, so the
    // UUID never changed) or under a pre-hash stem key get stable copies
    // now, before any re-add can strand them.
    // Pass 1 matches orphans within the same system directory. Pass 2
    // matches across systems for files stranded by a system change (gb ROM,
    // gbc/ folder) or by late identification (saves under default/, ROM now
    // identified). Pass-2 copies land in the game's CURRENT system
    // directory, where reads look for them.
    @discardableResult
    func relink(roms: [StableRomRef]) -> Report {
        var report = Report()
        let bySystem = Dictionary(grouping: roms) { $0.systemID }
        for systemID in saveStates.systemsWithSaves() {
            report.systemsScanned += 1
            guard let dirFiles = listFiles(inSystem: systemID) else { continue }
            let refs = bySystem[systemID] ?? []
            for ref in refs {
                for key in [ref.stemToken, ref.legacyToken] where key != ref.primaryToken {
                    let prefix = saveStates.safeGameStateName(key)
                    let files = dirFiles.filter { $0.hasPrefix(prefix + "__") }
                    guard !files.isEmpty else { continue }
                    let copied = copyGroup(
                        prefix: prefix, files: files,
                        systemID: systemID, destSystemID: ref.systemID,
                        ref: ref, report: &report
                    )
                    if copied > 0 {
                        report.gamesFixed += 1
                        report.fixedGames.append(ref.displayName)
                        LoggerService.info(
                            category: "SaveStateReconciler",
                            "Backfilled \(copied) file(s) for '\(ref.displayName)' to stable key."
                        )
                    }
                }
            }
            let groups = orphanGroups(files: dirFiles, refs: refs)
            report.orphansFound += groups.count
            for (prefix, files) in groups {
                if let ref = bestMatch(prefix: prefix, dir: systemID, roms: refs) {
                    let copied = copyGroup(
                        prefix: prefix, files: files,
                        systemID: systemID, destSystemID: ref.systemID,
                        ref: ref, report: &report
                    )
                    if copied > 0 {
                        report.gamesFixed += 1
                        report.fixedGames.append(ref.displayName)
                    }
                    continue
                }
                guard let ref = bestMatch(prefix: prefix, dir: systemID, roms: roms) else {
                    report.skipped += 1
                    continue
                }
                LoggerService.info(
                    category: "SaveStateReconciler",
                    "Cross-system link: '\(prefix)' in \(systemID)/ -> " +
                    "'\(ref.displayName)' in \(ref.systemID)/."
                )
                let copied = copyGroup(
                    prefix: prefix, files: files,
                    systemID: systemID, destSystemID: ref.systemID,
                    ref: ref, report: &report
                )
                if copied > 0 {
                    report.gamesFixed += 1
                    report.fixedGames.append(ref.displayName)
                }
            }
        }
        return report
    }

    // Auto-run entry point. Throttled to once per day. Skipped while a game
    // runs so scans never steal IO from gameplay.
    func autoRelinkIfNeeded(roms: [StableRomRef]) {
        guard !RunningGamesTracker.shared.isGameRunning else { return }
        let last = AppSettings.getDouble(lastAutoRunKey, defaultValue: 0)
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        AppSettings.setDouble(lastAutoRunKey, value: Date().timeIntervalSince1970)
        let report = relink(roms: roms)
        if report.filesCopied > 0 {
            LoggerService.info(
                category: "SaveStateReconciler",
                "Auto-relinked \(report.filesCopied) file(s) for \(report.gamesFixed) game(s)."
            )
        }
    }

    // MARK: - Private

    // Prefixes (safe file-name stems) owned by current ROMs in a system.
    private func knownPrefixes(refs: [StableRomRef]) -> Set<String> {
        var known = Set<String>()
        for ref in refs {
            known.insert(saveStates.safeGameStateName(ref.primaryToken))
            known.insert(saveStates.safeGameStateName(ref.stemToken))
            known.insert(saveStates.safeGameStateName(ref.legacyToken))
        }
        return known
    }

    // Full file listing of a system directory, or nil when unreadable.
    private func listFiles(inSystem systemID: String) -> [String]? {
        let sysDir = saveStates.systemDirectory(systemID: systemID)
        return try? FileManager.default.contentsOfDirectory(atPath: sysDir.path)
    }

    // Group files whose prefix no current ROM owns.
    private func orphanGroups(files: [String], refs: [StableRomRef]) -> [String: [String]] {
        let known = knownPrefixes(refs: refs)
        var groups: [String: [String]] = [:]
        for file in files {
            // Only state files and their companions (.png, .meta.json).
            guard file.contains("__autosave") || file.contains("__slot_") else { continue }
            let prefix = statePrefix(of: file)
            guard !prefix.isEmpty, !known.contains(prefix) else { continue }
            groups[prefix, default: []].append(file)
        }
        return groups
    }

    // Strip slot/version/thumbnail/meta suffixes to get the game prefix.
    private func statePrefix(of file: String) -> String {
        var name = file
        if name.hasSuffix(".meta.json") {
            name = String(name.dropLast(".meta.json".count))
        } else if name.hasSuffix(".png") {
            name = String(name.dropLast(".png".count))
        }
        let patterns = ["__autosave__v", "__slot_", "__autosave"]
        for pattern in patterns {
            if let range = name.range(of: pattern) {
                return String(name[..<range.lowerBound])
            }
        }
        return ""
    }

    // Best owner for an orphan prefix among the given candidates. Scored:
    // exact display/stem (10), same name plus agreeing file extension (9),
    // region-stripped display (8), filename-stem guess (7, only when the
    // extension agrees). Below 7 never links. Cross-system links additionally
    // need a same-file signal: the ROM lives in a folder named like the save
    // directory (gb ROM in a gbc/ folder), or the extension agrees. This keeps
    // same-named games on other systems (mame Battletoads vs gamegear saves)
    // from claiming each other's files. Ties keep the first candidate.
    private func bestMatch(prefix: String, dir: String, roms: [StableRomRef]) -> StableRomRef? {
        var bestRef: StableRomRef?
        var bestScore = 0
        for ref in roms {
            guard let score = matchScore(prefix: prefix, dir: dir, ref: ref),
                  score > bestScore else { continue }
            bestScore = score
            bestRef = ref
        }
        return bestRef
    }

    private func matchScore(prefix: String, dir: String, ref: StableRomRef) -> Int? {
        let sameSystem = (ref.systemID == dir)
        let folderSignal = ref.pathComponents.contains(dir.lowercased())
        let safeDisplay = saveStates.safeGameStateName(ref.displayName)
        let legacyBase = baseOfLegacy(prefix)
        let legacyExt = legacyExtension(of: prefix)
        let legacyName = normalizedName(stripExtension(legacyBase))
        let normDisplay = normalizedName(ref.displayName)
        let normFileStem = normalizedName(ref.fileStem)

        var tier: Int?
        if prefix == saveStates.safeGameStateName(ref.legacyToken)
            || (StableGameIdentity.isLegacyKey(prefix) && prefix.hasPrefix(safeDisplay + "__"))
            || prefix == safeDisplay
            || prefix == saveStates.safeGameStateName(ref.stemToken) {
            tier = 10
        } else if let ext = legacyExt,
                  ref.fileExtension == ext,
                  !legacyName.isEmpty,
                  (legacyName == normDisplay && !regionStripped(ref.displayName).isEmpty)
                      || (legacyName == normFileStem && !regionStripped(ref.fileStem).isEmpty) {
            // Same name plus agreeing file extension: display title or ROM
            // filename ("GoldenEye.z64" on disk vs "GoldenEye 007" shown).
            tier = 9
        } else if (normalizedName(legacyBase) == normDisplay && !regionStripped(ref.displayName).isEmpty)
                    || (normalizedName(legacyBase) == normFileStem && !regionStripped(ref.fileStem).isEmpty) {
            tier = 8
        } else if stemBase(of: ref.stemToken) == stripExtension(legacyBase).lowercased(),
                  !stemBase(of: ref.stemToken).isEmpty {
            tier = (legacyExt != nil && ref.fileExtension == legacyExt) ? 7 : 4
        }
        guard let strong = tier, strong >= 7 else { return nil }
        if !sameSystem && !folderSignal {
            let extAgrees = legacyExt != nil && ref.fileExtension == legacyExt
            guard (strong == 9 || strong == 7) && extAgrees else { return nil }
        }
        var score = strong
        if sameSystem { score += 2 }
        if folderSignal { score += 3 }
        return score
    }

    private func copyGroup(
        prefix: String,
        files: [String],
        systemID: String,
        destSystemID: String,
        ref: StableRomRef,
        report: inout Report
    ) -> Int {
        let sysDir = saveStates.systemDirectory(systemID: systemID)
        let destDir = saveStates.systemDirectory(systemID: destSystemID)
        let destPrefix = saveStates.safeGameStateName(ref.primaryToken)
        var copied = 0
        for file in files {
            let src = sysDir.appendingPathComponent(file)
            let destName = destPrefix + String(file.dropFirst(prefix.count))
            let dest = destDir.appendingPathComponent(destName)
            if FileManager.default.fileExists(atPath: dest.path) {
                report.skipped += 1
                continue
            }
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                copied += 1
                report.filesCopied += 1
            } catch {
                report.skipped += 1
                LoggerService.warning(
                    category: "SaveStateReconciler",
                    "Copy failed \(file): \(error.localizedDescription)"
                )
            }
        }
        return copied
    }
    // "Mario__a1b2c3d4" -> "Mario". Non-legacy prefixes pass through.
    private func baseOfLegacy(_ prefix: String) -> String {
        guard StableGameIdentity.isLegacyKey(prefix),
              let range = prefix.range(of: "__", options: .backwards) else {
            return prefix
        }
        return String(prefix[..<range.lowerBound])
    }

    // Lowercased file extension of a legacy base ("1942.zip" -> "zip").
    // Empty when there is none.
    private func legacyExtension(of prefix: String) -> String? {
        let base = baseOfLegacy(prefix)
        guard let dot = base.range(of: ".", options: .backwards) else { return nil }
        let ext = String(base[dot.upperBound...]).lowercased()
        return ext.isEmpty ? nil : ext
    }

    private func stripExtension(_ base: String) -> String {
        guard let dot = base.range(of: ".", options: .backwards) else { return base }
        return String(base[..<dot.lowerBound])
    }

    // Stem token without its "stem_" marker, for filename comparison.
    private func stemBase(of stemToken: String) -> String {
        stemToken.hasPrefix("stem_") ? String(stemToken.dropFirst(5)) : stemToken
    }

    // Region-stripped, lowercased, separator-normalized: multi-word names
    // compare equal across file keys ("Tetris_DX") and display names
    // ("Tetris DX"). safe() alone keeps case; regionStripped alone keeps
    // spaces. Both sides go through the same pipeline.
    private func normalizedName(_ name: String) -> String {
        saveStates.safeGameStateName(regionStripped(name))
    }

    // Removes "(...)" and "[...]" region/tag groups: "Mario Tennis (USA)"
    // and "Mario Tennis" compare equal. Case-insensitive.
    private func regionStripped(_ name: String) -> String {
        var out = name
        while let open = out.firstIndex(of: "("),
              let close = out[open...].firstIndex(of: ")"),
              open < close {
            out.removeSubrange(open...close)
        }
        while let open = out.firstIndex(of: "["),
              let close = out[open...].firstIndex(of: "]"),
              open < close {
            out.removeSubrange(open...close)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
