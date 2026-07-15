import Foundation

// Maps internal system IDs to libretro-thumbnails CDN folder names (https://thumbnails.libretro.com/).
enum LibretroThumbnailResolver {
    static let defaultBaseURL = URL(string: "https://thumbnails.libretro.com")!
    private static let logCategory = "LibretroThumbnails"

    // In-memory cache: systemID → list of CDN folder names that actually exist.
    // Populated once per system by probing the GitHub repos, then persisted to AppSettings.
    private static var resolvedWorkingFolders: [String: [String]] = [:]
    private static let workingFoldersPrefix = "thumbnail_working_folders_"

    // Prefer `ROM.thumbnailLookupSystemID` when identification matched a different Libretro set (e.g. GB vs GBC).
    static func effectiveThumbnailSystemID(for rom: ROM) -> String? {
        let result = rom.thumbnailLookupSystemID ?? rom.systemID
        if let thumbID = rom.thumbnailLookupSystemID, thumbID != rom.systemID {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "ROM '\(rom.name)' using thumbnailLookupSystemID='\(thumbID)' instead of systemID='\(rom.systemID ?? "nil")'")
            #endif
        } else {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "ROM '\(rom.name)' using systemID='\(result ?? "nil")' for thumbnail lookup")
            #endif
        }
        return result
    }

    // Returns all database folder names for a systemID (NOT just .first).
    static func libretroFolderNames(forSystemID systemID: String) -> [String] {
        guard let system = SystemDatabase.system(forID: systemID) else {
            LoggerService.warning(category: logCategory, "No system found for systemID '\(systemID)' — thumbnails will not be resolved")
            return []
        }
        guard let entries = system.database, !entries.isEmpty else {
            LoggerService.warning(category: logCategory, "No database entry for systemID '\(systemID)' — thumbnails will not be resolved")
            return []
        }
        return entries
    }

    // Probes all database folder names for a system against the GitHub thumbnail repos.
    // Returns only the folders whose repos actually exist, and caches the result.
    // On subsequent calls for the same systemID, returns the cached list immediately.
    @MainActor
    static func workingFolders(forSystemID systemID: String) async -> [String] {
        if let cached = resolvedWorkingFolders[systemID] {
            return cached
        }

        // Try loading from AppSettings persistence
        let settingsKey = "\(workingFoldersPrefix)\(systemID)"
        if let data = AppSettings.getData(settingsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data),
           !decoded.isEmpty {
            resolvedWorkingFolders[systemID] = decoded
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "Loaded \(decoded.count) working folders from persistence for '\(systemID)': \(decoded)")
            #endif
            return decoded
        }

        // Probe all database entries against GitHub
        let candidates = libretroFolderNames(forSystemID: systemID)
        guard !candidates.isEmpty else { return [] }

        LoggerService.info(category: logCategory, "Probing \(candidates.count) database folders for systemID '\(systemID)': \(candidates)")

        var working: [String] = []
        for folder in candidates {
            let repoName = githubRepoName(for: folder)
            let exists = await LibretroThumbnailManifestService.shared.repoExists(repoName: repoName)
            if exists {
                working.append(folder)
                LoggerService.info(category: logCategory, "Folder '\(folder)' exists for '\(systemID)' — added to working set")
            } else {
                LoggerService.info(category: logCategory, "Folder '\(folder)' does NOT exist for '\(systemID)' — skipped")
            }
        }

        if working.isEmpty {
            // Fallback: if no repo was found, use all candidates to avoid completely blocking thumbnails
            // (e.g. if GitHub API is down, we don't want to permanently block all lookups)
            LoggerService.warning(category: logCategory, "No working folders found for '\(systemID)' — falling back to all database entries")
            working = candidates
        }

        resolvedWorkingFolders[systemID] = working

        // Persist to AppSettings
        if let encoded = try? JSONEncoder().encode(working) {
            AppSettings.setData(settingsKey, value: encoded)
        }

        LoggerService.info(category: logCategory, "Cached \(working.count) working folders for '\(systemID)': \(working)")
        return working
    }

    // Clears the in-memory and persisted working folder cache for a system (or all if nil).
    @MainActor
    static func clearWorkingFoldersCache(systemID: String? = nil) {
        if let systemID = systemID {
            resolvedWorkingFolders.removeValue(forKey: systemID)
            AppSettings.remove("\(workingFoldersPrefix)\(systemID)")
        } else {
            resolvedWorkingFolders.removeAll()
            for system in SystemDatabase.systems {
                AppSettings.remove("\(workingFoldersPrefix)\(system.id)")
            }
        }
    }

    // Returns a list of all known Libretro thumbnail repository names (formatted for GitHub).
    static func allKnownSystemRepos() -> [String] {
        let allFolders = SystemDatabase.systems.flatMap { $0.database ?? [] }.filter { !$0.isEmpty }
        return Array(Set(allFolders)).map { githubRepoName(for: $0) }.sorted()
    }

    // Converts a Libretro folder name (e.g. "Nintendo - Nintendo Entertainment System")
    // to a GitHub repository name (e.g. "Nintendo_-_Nintendo_Entertainment_System").
    static func githubRepoName(for folderName: String) -> String {
        return folderName.replacingOccurrences(of: " ", with: "_")
    }

    // Tier 3: replace characters that libretro treats as filesystem-unsafe (design doc table).
    static func libretroFilesystemSafeName(_ s: String) -> String {
        var result = ""
        for ch in s {
            switch ch {
            case "&", "*", ":", "?", "\"", "<", ">", "|", "/", "\\":
                result.append("_")
            default:
                result.append(ch)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Strip tags from a ROM filename stem for display. Delegates to GameNameFormatter.
    static func stripRomFilenameTags(_ filenameStem: String) -> String {
        GameNameFormatter.stripTags(filenameStem)
    }

    // Fuzzy fallback: remove all `( … )` segments for a second pass on Named_Boxarts.
    // Delegates to GameNameFormatter for consistency.
    static func stripParenthesesForFuzzyMatch(_ name: String) -> String {
        GameNameFormatter.removeParentheses(name)
    }

    static func buildThumbnailURL(
        base: URL,
        systemFolder: String,
        typeFolder: String,
        fileName: String
    ) -> URL {
        let name = fileName.hasSuffix(".png") ? fileName : "\(fileName).png"
        let url = base
            .appendingPathComponent(systemFolder)
            .appendingPathComponent(typeFolder)
            .appendingPathComponent(name)
        #if LOG_EXTREME
        LoggerService.extreme(category: logCategory, "Built thumbnail URL: \(url.absoluteString)")
        #endif
        return url
    }

    // Ordered `Named_*` folders per user priority (Boxart / Title / Snap).
    static func orderedThumbnailTypeFolders(priority: LibretroThumbnailPriority) -> [String] {
        switch priority {
        case .boxart:
            return ["Named_Boxarts", "Named_Titles", "Named_Snaps"]
        case .title:
            return ["Named_Titles", "Named_Boxarts", "Named_Snaps"]
        case .snap:
            return ["Named_Snaps", "Named_Boxarts", "Named_Titles"]
        }
    }

    // Common suffix variants that the Libretro CDN uses for boxart entries.
    // These are appended to the base title to match entries like "(Beta)" or "(Rev 1)".
    private static let boxartSuffixVariants = [
        " (Beta)",
        " (Rev 1)",
        " (Rev 2)",
        " (Rev A)",
        " (Rev B)",
        " (v1.0)",
        " (v1.1)",
        // Common region variants (for number variants like "Ecco the Dolphin II")
        " (USA)",
        " (Europe)",
        " (Japan)",
        " (World)",
    ]

    // All CDN URLs to try for one resolved title (primary + safe + fuzzy + suffix variants).
    // Strategy: Named_Boxarts uses cleaned titles (no region tags), so we try the fuzzy/stripped
    // variant first for boxart before falling back to Named_Titles with the full tagged name.
    static func candidateURLs(
        base: URL,
        systemFolder: String,
        gameTitle: String,
        priority: LibretroThumbnailPriority,
        regionSuffix: String? = nil
    ) -> [URL] {
        return candidateURLs(base: base, systemFolder: systemFolder, gameTitle: gameTitle, knownVariants: [], priority: priority, regionSuffix: regionSuffix)
    }

    // Generate Roman numeral and text number variants of a title for boxart matching.
    // E.g. "Ecco the Dolphin 2" → "Ecco the Dolphin II", "Ecco the Dolphin Two"
    // E.g. "Double Dragon 3" → "Double Dragon III", "Double Dragon Three"
    // Visible for testing.
    static func numberVariants(of title: String) -> [String] {
        ROMIdentifierService.romanNumeralVariants(of: title)
    }

    // All CDN URLs to try, including known DAT variant names.
    // Known variants are tried BEFORE arbitrary suffix guessing to maximize match probability.
    // When regionSuffix is provided (e.g., "(Spain)"), it is tried FIRST in the suffix variants
    // so the preferred region's boxart is prioritized over generic fallbacks.
    static func candidateURLs(
        base: URL,
        systemFolder: String,
        gameTitle: String,
        knownVariants: [String],
        priority: LibretroThumbnailPriority,
        regionSuffix: String? = nil
    ) -> [URL] {
        let primary = gameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primary.isEmpty else {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "candidateURLs: empty primary title after trim, returning no URLs")
            #endif
            return []
        }

        let safe = libretroFilesystemSafeName(primary)
        let fuzzy = stripParenthesesForFuzzyMatch(primary)
        let numberVariants = Self.numberVariants(of: primary)

        #if LOG_DEBUG
        LoggerService.debug(category: logCategory, "candidateURLs: primary='\(primary)', safe='\(safe)', fuzzy='\(fuzzy)', numberVariants=\(numberVariants.count), knownVariants=\(knownVariants.count), priority=\(priority.rawValue)")
        #endif

        var urls: [URL] = []
        var seen = Set<URL>()

        func appendUnique(_ u: URL) {
            if !seen.contains(u) {
                seen.insert(u)
                urls.append(u)
            }
        }

        let typeFolders = orderedThumbnailTypeFolders(priority: priority)
        #if LOG_DEBUG
        LoggerService.debug(category: logCategory, "candidateURLs: typeFolders order = \(typeFolders.joined(separator: ", "))")
        #endif

        // Determine which folder is "first choice" for the given priority
        let firstChoiceFolder = typeFolders.first ?? "Named_Boxarts"

        // Build title variants for the primary folder
        var titleVariants: [String] = [primary]
        if safe != primary, !safe.isEmpty { titleVariants.append(safe) }
        // Add number variants (II, Two, etc.) for titles with Arabic numerals
        for variant in numberVariants {
            if variant != primary && !titleVariants.contains(variant) {
                titleVariants.append(variant)
            }
        }
        // Add number variants of the fuzzy (parenthesis-stripped) title too
        let fuzzyNumberVariants = Self.numberVariants(of: fuzzy)
        for variant in fuzzyNumberVariants {
            if variant != fuzzy && !titleVariants.contains(variant) {
                titleVariants.append(variant)
            }
        }
        // Also try with trailing number stripped (first-in-series case, e.g. "Ecco the Dolphin 1" → "Ecco the Dolphin")
        for pat in [" 1$", " (?i:i)(?-i)$", " (?i:one)(?-i)$"] {
            let stripped = primary.replacingOccurrences(of: pat, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped != primary && !stripped.isEmpty && !titleVariants.contains(stripped) {
                titleVariants.append(stripped)
            }
        }

        #if LOG_DEBUG
        LoggerService.debug(category: logCategory, "candidateURLs: \(titleVariants.count) title variants to try")
        #endif

        // Step 0: When regionSuffix is provided, try the region-suffixed title FIRST,
        // before any undifferentiated fallback. This ensures the user's preferred region
        // boxart is prioritized (e.g. "(Japan)" over the generic "Title.png").
        if firstChoiceFolder == "Named_Boxarts", let regionSuffix = regionSuffix, !regionSuffix.isEmpty {
            let suffixed = " \(regionSuffix)"
            // Use the fuzzy (parenthesis-stripped) title as the base so we don't double-tag
            if fuzzy != primary && !fuzzy.isEmpty {
                #if LOG_DEBUG
                LoggerService.debug(category: logCategory, "candidateURLs: Step 0 region-suffixed fuzzy — '\(fuzzy)\(suffixed)'")
                #endif
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzy)\(suffixed).png"))
                let fuzzySafe = libretroFilesystemSafeName(fuzzy)
                if fuzzySafe != fuzzy {
                    appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzySafe)\(suffixed).png"))
                }
            }
            // Also try with the safe variant of primary if fuzzy didn't vary
            if fuzzy == primary || fuzzy.isEmpty {
                let safeBase = safe != primary ? safe : primary
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(safeBase)\(suffixed).png"))
            }
        }

        // Step 1: For Named_Boxarts specifically, try the fuzzy (parenthesis-stripped) title.
        // The Libretro CDN stores boxart under cleaned names (no region tags), so this has
        // the highest chance of matching when the CRC-resolved title includes (USA, En) etc.
        if firstChoiceFolder == "Named_Boxarts" && fuzzy != primary && !fuzzy.isEmpty {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "candidateURLs: Step 1 fuzzy boxart — '\(fuzzy)'")
            #endif
            appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzy).png"))
            let fuzzySafe = libretroFilesystemSafeName(fuzzy)
            if fuzzySafe != fuzzy {
                #if LOG_DEBUG
                LoggerService.debug(category: logCategory, "candidateURLs: Step 1 fuzzy boxart (safe) — '\(fuzzySafe)'")
                #endif
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzySafe).png"))
            }
        }

        // Step 2: Try number variants (II, III, Two, etc.) for Named_Boxarts
        if firstChoiceFolder == "Named_Boxarts" && !numberVariants.isEmpty {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "candidateURLs: Step 2 trying \(numberVariants.count) number variants for Named_Boxarts")
            #endif
            for variant in numberVariants {
                #if LOG_DEBUG
                LoggerService.debug(category: logCategory, "candidateURLs: Step 2 number variant — '\(variant)'")
                #endif
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(variant).png"))
            }
        }

        // Step 3: Try known DAT variant names BEFORE arbitrary suffix guessing.
        // These are real entries from the libretro database, so they have the highest
        // probability of matching actual CDN assets.
        if firstChoiceFolder == "Named_Boxarts" && !knownVariants.isEmpty {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "candidateURLs: Step 3 trying \(knownVariants.count) known DAT variants for Named_Boxarts")
            #endif
            for variantName in knownVariants {
                if variantName != primary {
                    appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(variantName).png"))
                    let variantSafe = libretroFilesystemSafeName(variantName)
                    if variantSafe != variantName {
                        appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(variantSafe).png"))
                    }
                }
            }
        }

        // Step 4: For Named_Boxarts, try arbitrary suffix variants (Beta, Rev, region, etc.) as fallback.
        // The user's preferred region suffix (if any) is tried FIRST, before generic fallbacks.
        // Also try suffixes on number variants (e.g. "Ecco the Dolphin II (Japan).png")
        // IMPORTANT: Use the fuzzy (cleaned) title as the base, NOT primary — primary may already
        // contain region tags (e.g. "(USA)"), which would produce double-tagged names.
        if firstChoiceFolder == "Named_Boxarts" {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "candidateURLs: Step 4 trying arbitrary suffix variants for Named_Boxarts")
            #endif
            let baseForSuffix = (fuzzy != primary && !fuzzy.isEmpty) ? fuzzy : primary
            // Build suffix list with user's preferred region first
            var orderedSuffixes = boxartSuffixVariants
            if let regionSuffix = regionSuffix, !regionSuffix.isEmpty {
                let prefixed = " \(regionSuffix)"
                if let idx = orderedSuffixes.firstIndex(of: prefixed) {
                    orderedSuffixes.remove(at: idx)
                }
                orderedSuffixes.insert(prefixed, at: 0)
            }
            for suffix in orderedSuffixes {
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(baseForSuffix)\(suffix).png"))
                // Try suffixes on number variants too (e.g. "Ecco the Dolphin II (Japan).png")
                for variant in numberVariants {
                    appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(variant)\(suffix).png"))
                }
            }
        }

        // Step 5: Try primary title variants (including number variants) across all type folders in priority order
        #if LOG_DEBUG
        LoggerService.debug(category: logCategory, "candidateURLs: Step 5 trying \(titleVariants.count) variants across \(typeFolders.joined(separator: ", "))")
        #endif
        for titleVariant in titleVariants {
            for folder in typeFolders {
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: folder, fileName: "\(titleVariant).png"))
            }
        }

        // Step 6: Fallback fuzzy for Named_Boxarts only if not already added in Step 1
        // (handles the case where fuzzy == primary or priority is not boxart)
        if firstChoiceFolder != "Named_Boxarts" && fuzzy != primary && fuzzy != safe && !fuzzy.isEmpty {
            appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzy).png"))
            let fuzzySafe = libretroFilesystemSafeName(fuzzy)
            if fuzzySafe != fuzzy {
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzySafe).png"))
            }
        }

        #if LOG_DEBUG
        LoggerService.debug(category: logCategory, "candidateURLs: generated \(urls.count) unique URLs")
        #endif
        return urls
    }

    // Resolve a display title: CRC/DAT (tier 1), else filename sanitization (tier 2).
    static func resolveGameTitle(
        for rom: ROM,
        useCRC: Bool,
        fallbackFilename: Bool
    ) async -> String? {
        let systemID = rom.systemID ?? ""
        #if LOG_DEBUG
        LoggerService.debug(category: logCategory, "resolveGameTitle for '\(rom.name)': systemID='\(systemID)', useCRC=\(useCRC), fallbackFilename=\(fallbackFilename)")
        #endif

        if useCRC, !systemID.isEmpty, SystemDatabase.system(forID: systemID) != nil {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "resolveGameTitle: attempting CRC identification for '\(rom.name)'")
            #endif
            if let info = await ROMIdentifierService.shared.identifyReturningGameInfo(rom: rom) {
                let n = info.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty {
                    return n
                } else {
                }
            } else {
            }
        } else {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "resolveGameTitle: skipping CRC (useCRC=\(useCRC), systemID='\(systemID)')")
            #endif
        }

        if fallbackFilename {
            let stem = rom.path.deletingPathExtension().lastPathComponent
            let stripped = stripRomFilenameTags(stem)
            if !stripped.isEmpty {
                return stripped
            } else {
                #if LOG_DEBUG
                LoggerService.debug(category: logCategory, "resolveGameTitle: filename fallback produced empty string for '\(rom.name)'")
                #endif
            }
        }

        if let meta = rom.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !meta.isEmpty {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "resolveGameTitle: metadata title → '\(meta)' for '\(rom.name)'")
            #endif
            return meta
        }

        let stem = rom.path.deletingPathExtension().lastPathComponent
        let result = stripRomFilenameTags(stem)
        #if LOG_DEBUG
        LoggerService.debug(category: logCategory, "resolveGameTitle: final fallback from filename stem '\(stem)' → '\(result)' for '\(rom.name)'")
        #endif
        return result
    }

    // Strict file name match, else shortest prefix match among `.png` / `.jpg` in `folder`.
    static func resolveLocalThumbnail(named sanitizedStem: String, in folder: URL) -> URL? {
        let fm = FileManager.default
        #if LOG_DEBUG
        LoggerService.debug(category: logCategory, "resolveLocalThumbnail: searching for '\(sanitizedStem)' in folder \(folder.path)")
        #endif

        guard fm.fileExists(atPath: folder.path) else {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "resolveLocalThumbnail: folder does not exist: \(folder.path)")
            #endif
            return nil
        }

        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "resolveLocalThumbnail: failed to read folder contents: \(folder.path)")
            #endif
            return nil
        }

        let exts = ["png", "PNG", "jpg", "JPG", "jpeg", "JPEG"]
        let candidates = files.filter { exts.contains($0.pathExtension) }
        #if LOG_DEBUG
        LoggerService.debug(category: logCategory, "resolveLocalThumbnail: found \(files.count) files, \(candidates.count) are image candidates in \(folder.lastPathComponent)")
        #endif

        let exactNames = [
            "\(sanitizedStem).png", "\(sanitizedStem).PNG",
            "\(sanitizedStem).jpg", "\(sanitizedStem).JPEG",
        ]
        for e in exactNames {
            if let hit = candidates.first(where: { $0.lastPathComponent == e }) {
                #if LOG_DEBUG
                LoggerService.debug(category: logCategory, "resolveLocalThumbnail: exact match found: \(hit.lastPathComponent)")
                #endif
                return hit
            }
        }

        #if LOG_DEBUG
        LoggerService.debug(category: logCategory, "resolveLocalThumbnail: no exact match, trying prefix match for '\(sanitizedStem)'")
        #endif
        let prefix = sanitizedStem
        let prefixed = candidates.filter { $0.deletingPathExtension().lastPathComponent.hasPrefix(prefix) }
        guard !prefixed.isEmpty else {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "resolveLocalThumbnail: no prefix matches found in \(folder.lastPathComponent)")
            #endif
            return nil
        }

        let best = prefixed.min(by: { $0.lastPathComponent.count < $1.lastPathComponent.count })
        if let best = best {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "resolveLocalThumbnail: prefix match found: \(best.lastPathComponent)")
            #endif
        }
        return best
    }

    // Extract the region tag (e.g., "(USA)", "(Spain)") from a boxart URL's filename.
    // Searches for the LAST parenthesized group that looks like a region tag.
    static func regionTag(from url: URL) -> String? {
        let filename = url.deletingPathExtension().lastPathComponent
        // Find all parenthesized groups, pick the last one that matches known region patterns
        guard let matches = try? NSRegularExpression(pattern: "\\(([^()]+)\\)")
            .matches(in: filename, range: NSRange(location: 0, length: filename.utf16.count)),
              !matches.isEmpty else { return nil }
        // Try from the end — the last tagged group is most likely the region or revision
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: filename) else { continue }
            let tag = String(filename[range])
            // Skip known non-region tags (Beta, Rev, v1.0, etc.) unless they're the only tag
            let nonRegion = ["Beta", "Rev 1", "Rev 2", "Rev A", "Rev B", "v1.0", "v1.1", "Proto", "Demo", "Sample", "Kiosk", "Virtual Console"]
            if nonRegion.contains(where: { tag.hasPrefix($0) || tag == $0 }) { continue }
            return "(\(tag))"
        }
        // Fallback: return the last parenthesized group regardless
        if let last = matches.last, let range = Range(last.range(at: 1), in: filename) {
            return "(\(String(filename[range])))"
        }
        return nil
    }

    // Score a filename for region preference. Higher = better match.
    // Returns the 0-based index in regionPreference for the first tag found, or
    // regionPreference.count if no region matches.
    static func regionScore(for filename: String, preference: [String]) -> Int {
        for (idx, tag) in preference.enumerated() {
            if filename.contains(tag) { return idx }
        }
        return preference.count // worst score
    }

    // Convenience variant that restricts matching to a single Named_* type folder
    // (e.g. "Named_Titles" or "Named_Snaps"). Used when downloading title
    // screens / in-game screenshots exclusively (we do NOT want box-art fallback).
    static func bestMatchingURLs(
        forType typeFolder: String,
        gameTitle: String,
        systemFolders: [String],
        base: URL,
        regionPreference: [String]
    ) async -> [(folder: String, url: URL, regionTag: String?)] {
        let fuzzy = stripParenthesesForFuzzyMatch(gameTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fuzzy.isEmpty else { return [] }
        let prefixNoPeriod = fuzzy.hasSuffix(".") ? String(fuzzy.dropLast()).trimmingCharacters(in: .whitespaces) : fuzzy
        let prefixes = Set([fuzzy, prefixNoPeriod, libretroFilesystemSafeName(fuzzy), libretroFilesystemSafeName(prefixNoPeriod)]).filter { !$0.isEmpty }

        var results: [(folder: String, url: URL, regionTag: String?, score: Int)] = []

        for folder in systemFolders {
            let repoName = githubRepoName(for: folder)
            let fileSet: Set<String>
            do {
                fileSet = try await LibretroThumbnailManifestService.shared.getManifestFileSet(for: repoName)
            } catch {
                LoggerService.warning(category: logCategory, "Manifest fetch failed for \(repoName): \(error.localizedDescription). Skipping manifest-based match.")
                continue
            }

            let typePrefix = "\(typeFolder)/"
            let candidates = fileSet.filter { path in
                guard path.hasPrefix(typePrefix) else { return false }
                let name = path.dropFirst(typePrefix.count)
                return prefixes.contains(where: { name.hasPrefix($0) })
            }.sorted()

            for path in candidates {
                let fileName = String(path.dropFirst(typePrefix.count))
                let score = regionScore(for: fileName, preference: regionPreference)
                let fileURL = buildThumbnailURL(base: base, systemFolder: folder, typeFolder: typeFolder, fileName: fileName)
                let regionTag = self.regionTag(from: fileURL)
                results.append((folder, fileURL, regionTag, score))
            }
        }

        results.sort { a, b in
            if a.score != b.score { return a.score < b.score }
            return a.url.lastPathComponent.count < b.url.lastPathComponent.count
        }

        return results.map { ($0.folder, $0.url, $0.regionTag) }
    }

    // Uses the thumbnail manifest to find all matching URLs for a game title.
    // Searches Named_Boxarts entries matching the fuzzy title prefix, ranks them
    // by region preference, and returns sorted list of (folder, url, regionTag).
    // Returns empty if manifest is unavailable (caller should fallback to candidateURLs).
    static func bestMatchingURLs(
        for gameTitle: String,
        systemFolders: [String],
        base: URL,
        priority: LibretroThumbnailPriority,
        regionPreference: [String]
    ) async -> [(folder: String, url: URL, regionTag: String?)] {
        // Build normalized prefix: fuzzy (parenthesis-stripped), also try without trailing period
        let fuzzy = stripParenthesesForFuzzyMatch(gameTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fuzzy.isEmpty else { return [] }
        let prefixNoPeriod = fuzzy.hasSuffix(".") ? String(fuzzy.dropLast()).trimmingCharacters(in: .whitespaces) : fuzzy
        let prefixes = Set([fuzzy, prefixNoPeriod, libretroFilesystemSafeName(fuzzy), libretroFilesystemSafeName(prefixNoPeriod)]).filter { !$0.isEmpty }

        var results: [(folder: String, url: URL, regionTag: String?, score: Int)] = []

        for folder in systemFolders {
            let repoName = githubRepoName(for: folder)
            let fileSet: Set<String>
            do {
                fileSet = try await LibretroThumbnailManifestService.shared.getManifestFileSet(for: repoName)
            } catch {
                LoggerService.warning(category: logCategory, "Manifest fetch failed for \(repoName): \(error.localizedDescription). Skipping manifest-based match.")
                continue
            }

            let orderedTypes = orderedThumbnailTypeFolders(priority: priority)
            for typeFolder in orderedTypes {
                let typePrefix = "\(typeFolder)/"
                let candidates = fileSet.filter { path in
                    guard path.hasPrefix(typePrefix) else { return false }
                    let name = path.dropFirst(typePrefix.count)
                    return prefixes.contains(where: { name.hasPrefix($0) })
                }.sorted()

                for path in candidates {
                    let fileName = String(path.dropFirst(typePrefix.count))
                    let score = regionScore(for: fileName, preference: regionPreference)
                    let fileURL = buildThumbnailURL(base: base, systemFolder: folder, typeFolder: typeFolder, fileName: fileName)
                    let regionTag = self.regionTag(from: fileURL)
                    results.append((folder, fileURL, regionTag, score))
                }
            }
        }

        // Sort: best region score first (lower index = better), then shorter filenames
        results.sort { a, b in
            if a.score != b.score { return a.score < b.score }
            return a.url.lastPathComponent.count < b.url.lastPathComponent.count
        }

        return results.map { ($0.folder, $0.url, $0.regionTag) }
    }
}

enum LibretroThumbnailPriority: String, CaseIterable, Identifiable {
    case boxart
    case title
    case snap

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .boxart: return "Box art first"
        case .title: return "Title screen first"
        case .snap: return "Screenshot first"
        }
    }
}

