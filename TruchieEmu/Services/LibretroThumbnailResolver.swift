import Foundation

/// Maps internal system IDs to libretro-thumbnails CDN folder names (https://thumbnails.libretro.com/).
enum LibretroThumbnailResolver {
    static let defaultBaseURL = URL(string: "https://thumbnails.libretro.com")!
    private static let logCategory = "LibretroThumbnails"

    /// Prefer `ROM.thumbnailLookupSystemID` when identification matched a different Libretro set (e.g. GB vs GBC).
    static func effectiveThumbnailSystemID(for rom: ROM) -> String? {
        let result = rom.thumbnailLookupSystemID ?? rom.systemID
        if let thumbID = rom.thumbnailLookupSystemID, thumbID != rom.systemID {
            LoggerService.debug(category: logCategory, "ROM '\(rom.name)' using thumbnailLookupSystemID='\(thumbID)' instead of systemID='\(rom.systemID ?? "nil")'")
        } else {
            LoggerService.debug(category: logCategory, "ROM '\(rom.name)' using systemID='\(result ?? "nil")' for thumbnail lookup")
        }
        return result
    }

    static func libretroFolderName(forSystemID systemID: String) -> String? {
        let map: [String: String] = [
            // Nintendo
            "nes": "Nintendo - Nintendo Entertainment System",
            "snes": "Nintendo - Super Nintendo Entertainment System",
            "n64": "Nintendo - Nintendo 64",
            "gba": "Nintendo - Game Boy Advance",
            "gb": "Nintendo - Game Boy",
            "gbc": "Nintendo - Game Boy Color",
            "nds": "Nintendo - Nintendo DS",
            // Sega
            "genesis": "Sega - Mega Drive - Genesis",
            "sms": "Sega - Master System - Mark III",
            "gamegear": "Sega - Game Gear",
            "32x": "Sega - 32X",
            "saturn": "Sega - Saturn",
            "dreamcast": "Sega - Dreamcast",
            // Sony
            "psx": "Sony - PlayStation",
            "ps2": "Sony - PlayStation 2",
            "psp": "Sony - PlayStation Portable",
            // Arcade
            "mame": "MAME",
            "fba": "FBNeo - Arcade Games",
            // Atari
            "atari2600": "Atari - 2600",
            "atari5200": "Atari - 5200",
            "atari7800": "Atari - 7800",
            "lynx": "Atari - Lynx",
            // SNK
            "ngp": "SNK - Neo Geo Pocket",
            // NEC
            "pce": "NEC - PC Engine - TurboGrafx 16",
            "pcfx": "NEC - PC-FX",
            // Other
            "3do": "The 3DO Company - 3DO",
        ]
        let result = map[systemID.lowercased()]
        if let folder = result {
            LoggerService.debug(category: logCategory, "Mapped systemID '\(systemID)' → folder '\(folder)'")
        } else {
            LoggerService.warning(category: logCategory, "No folder mapping for systemID '\(systemID)' — thumbnails will not be resolved")
        }
        return result
    }

    /// Tier 3: replace characters that libretro treats as filesystem-unsafe (design doc table).
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

    /// Strip tags from a ROM filename stem for display. Delegates to GameNameFormatter.
    static func stripRomFilenameTags(_ filenameStem: String) -> String {
        GameNameFormatter.stripTags(filenameStem)
    }

    /// Fuzzy fallback: remove all `( … )` segments for a second pass on Named_Boxarts.
    /// Delegates to GameNameFormatter for consistency.
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
        LoggerService.extreme(category: logCategory, "Built thumbnail URL: \(url.absoluteString)")
        return url
    }

    /// Ordered `Named_*` folders per user priority (Boxart / Title / Snap).
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

    /// Common suffix variants that the Libretro CDN uses for boxart entries.
    /// These are appended to the base title to match entries like "(Beta)" or "(Rev 1)".
    private static let boxartSuffixVariants = [
        " (Beta)",
        " (Rev 1)",
        " (Rev 2)",
        " (Rev A)",
        " (Rev B)",
        " (v1.0)",
        " (v1.1)",
    ]

    /// All CDN URLs to try for one resolved title (primary + safe + fuzzy + suffix variants).
    /// Strategy: Named_Boxarts uses cleaned titles (no region tags), so we try the fuzzy/stripped
    /// variant first for boxart before falling back to Named_Titles with the full tagged name.
    static func candidateURLs(
        base: URL,
        systemFolder: String,
        gameTitle: String,
        priority: LibretroThumbnailPriority
    ) -> [URL] {
        return candidateURLs(base: base, systemFolder: systemFolder, gameTitle: gameTitle, knownVariants: [], priority: priority)
    }

    /// All CDN URLs to try, including known DAT variant names.
    /// Known variants are tried BEFORE arbitrary suffix guessing to maximize match probability.
    static func candidateURLs(
        base: URL,
        systemFolder: String,
        gameTitle: String,
        knownVariants: [String],
        priority: LibretroThumbnailPriority
    ) -> [URL] {
        let primary = gameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primary.isEmpty else {
            LoggerService.debug(category: logCategory, "candidateURLs: empty primary title after trim, returning no URLs")
            return []
        }

        let safe = libretroFilesystemSafeName(primary)
        let fuzzy = stripParenthesesForFuzzyMatch(primary)

        LoggerService.debug(category: logCategory, "candidateURLs: primary='\(primary)', safe='\(safe)', fuzzy='\(fuzzy)', knownVariants=\(knownVariants.count), priority=\(priority.rawValue)")

        var urls: [URL] = []
        var seen = Set<URL>()

        func appendUnique(_ u: URL) {
            if !seen.contains(u) {
                seen.insert(u)
                urls.append(u)
            }
        }

        let typeFolders = orderedThumbnailTypeFolders(priority: priority)
        LoggerService.debug(category: logCategory, "candidateURLs: typeFolders order = \(typeFolders.joined(separator: ", "))")

        // Determine which folder is "first choice" for the given priority
        let firstChoiceFolder = typeFolders.first ?? "Named_Boxarts"

        // Build title variants for the primary folder
        var titleVariants: [String] = [primary]
        if safe != primary, !safe.isEmpty { titleVariants.append(safe) }

        // Step 1: For Named_Boxarts specifically, try the fuzzy (parenthesis-stripped) title FIRST.
        // The Libretro CDN stores boxart under cleaned names (no region tags), so this has
        // the highest chance of matching when the CRC-resolved title includes (USA, En) etc.
        if firstChoiceFolder == "Named_Boxarts" && fuzzy != primary && !fuzzy.isEmpty {
            LoggerService.debug(category: logCategory, "candidateURLs: Step 1 fuzzy boxart — '\(fuzzy)'")
            appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzy).png"))
            let fuzzySafe = libretroFilesystemSafeName(fuzzy)
            if fuzzySafe != fuzzy {
                LoggerService.debug(category: logCategory, "candidateURLs: Step 1 fuzzy boxart (safe) — '\(fuzzySafe)'")
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzySafe).png"))
            }
        }

        // Step 2: Try known DAT variant names BEFORE arbitrary suffix guessing.
        // These are real entries from the libretro database, so they have the highest
        // probability of matching actual CDN assets.
        if firstChoiceFolder == "Named_Boxarts" && !knownVariants.isEmpty {
            LoggerService.debug(category: logCategory, "candidateURLs: Step 2 trying \(knownVariants.count) known DAT variants for Named_Boxarts")
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

        // Step 3: For Named_Boxarts, try arbitrary suffix variants (Beta, Rev, etc.) as fallback.
        if firstChoiceFolder == "Named_Boxarts" {
            LoggerService.debug(category: logCategory, "candidateURLs: Step 3 trying arbitrary suffix variants for Named_Boxarts")
            for suffix in boxartSuffixVariants {
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(primary)\(suffix).png"))
            }
        }

        // Step 4: Try primary title variants across all type folders in priority order
        LoggerService.debug(category: logCategory, "candidateURLs: Step 4 trying primary variants across \(typeFolders.joined(separator: ", "))")
        for titleVariant in titleVariants {
            for folder in typeFolders {
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: folder, fileName: "\(titleVariant).png"))
            }
        }

        // Step 5: Fallback fuzzy for Named_Boxarts only if not already added in Step 1
        // (handles the case where fuzzy == primary or priority is not boxart)
        if firstChoiceFolder != "Named_Boxarts" && fuzzy != primary && fuzzy != safe && !fuzzy.isEmpty {
            appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzy).png"))
            let fuzzySafe = libretroFilesystemSafeName(fuzzy)
            if fuzzySafe != fuzzy {
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzySafe).png"))
            }
        }

        LoggerService.debug(category: logCategory, "candidateURLs: generated \(urls.count) unique URLs (\(titleVariants.count) title variants × \(typeFolders.count) folders + \(knownVariants.count) known variants + suffixes)")
        return urls
    }

    /// Resolve a display title: CRC/DAT (tier 1), else filename sanitization (tier 2).
    static func resolveGameTitle(
        for rom: ROM,
        useCRC: Bool,
        fallbackFilename: Bool
    ) async -> String? {
        let systemID = rom.systemID ?? ""
        LoggerService.debug(category: logCategory, "resolveGameTitle for '\(rom.name)': systemID='\(systemID)', useCRC=\(useCRC), fallbackFilename=\(fallbackFilename)")

        if useCRC, !systemID.isEmpty, SystemDatabase.system(forID: systemID) != nil {
            LoggerService.debug(category: logCategory, "resolveGameTitle: attempting CRC identification for '\(rom.name)'")
            if let info = await ROMIdentifierService.shared.identifyReturningGameInfo(rom: rom) {
                let n = info.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty {
                    LoggerService.debug(category: logCategory, "resolveGameTitle: CRC match → '\(n)' for '\(rom.name)'")
                    return n
                } else {
                    LoggerService.debug(category: logCategory, "resolveGameTitle: CRC identification returned empty name for '\(rom.name)'")
                }
            } else {
                LoggerService.debug(category: logCategory, "resolveGameTitle: CRC identification failed for '\(rom.name)'")
            }
        } else {
            LoggerService.debug(category: logCategory, "resolveGameTitle: skipping CRC (useCRC=\(useCRC), systemID='\(systemID)')")
        }

        if fallbackFilename {
            let stem = rom.path.deletingPathExtension().lastPathComponent
            let stripped = stripRomFilenameTags(stem)
            if !stripped.isEmpty {
                LoggerService.debug(category: logCategory, "resolveGameTitle: filename fallback → '\(stripped)' for '\(rom.name)'")
                return stripped
            } else {
                LoggerService.debug(category: logCategory, "resolveGameTitle: filename fallback produced empty string for '\(rom.name)'")
            }
        }

        if let meta = rom.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !meta.isEmpty {
            LoggerService.debug(category: logCategory, "resolveGameTitle: metadata title → '\(meta)' for '\(rom.name)'")
            return meta
        }

        let stem = rom.path.deletingPathExtension().lastPathComponent
        let result = stripRomFilenameTags(stem)
        LoggerService.debug(category: logCategory, "resolveGameTitle: final fallback from filename stem '\(stem)' → '\(result)' for '\(rom.name)'")
        return result
    }

    /// Strict file name match, else shortest prefix match among `.png` / `.jpg` in `folder`.
    static func resolveLocalThumbnail(named sanitizedStem: String, in folder: URL) -> URL? {
        let fm = FileManager.default
        LoggerService.debug(category: logCategory, "resolveLocalThumbnail: searching for '\(sanitizedStem)' in folder \(folder.path)")

        guard fm.fileExists(atPath: folder.path) else {
            LoggerService.debug(category: logCategory, "resolveLocalThumbnail: folder does not exist: \(folder.path)")
            return nil
        }

        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            LoggerService.debug(category: logCategory, "resolveLocalThumbnail: failed to read folder contents: \(folder.path)")
            return nil
        }

        let exts = ["png", "PNG", "jpg", "JPG", "jpeg", "JPEG"]
        let candidates = files.filter { exts.contains($0.pathExtension) }
        LoggerService.debug(category: logCategory, "resolveLocalThumbnail: found \(files.count) files, \(candidates.count) are image candidates in \(folder.lastPathComponent)")

        let exactNames = [
            "\(sanitizedStem).png", "\(sanitizedStem).PNG",
            "\(sanitizedStem).jpg", "\(sanitizedStem).JPEG",
        ]
        for e in exactNames {
            if let hit = candidates.first(where: { $0.lastPathComponent == e }) {
                LoggerService.debug(category: logCategory, "resolveLocalThumbnail: exact match found: \(hit.lastPathComponent)")
                return hit
            }
        }

        LoggerService.debug(category: logCategory, "resolveLocalThumbnail: no exact match, trying prefix match for '\(sanitizedStem)'")
        let prefix = sanitizedStem
        let prefixed = candidates.filter { $0.deletingPathExtension().lastPathComponent.hasPrefix(prefix) }
        guard !prefixed.isEmpty else {
            LoggerService.debug(category: logCategory, "resolveLocalThumbnail: no prefix matches found in \(folder.lastPathComponent)")
            return nil
        }

        let best = prefixed.min(by: { $0.lastPathComponent.count < $1.lastPathComponent.count })
        if let best = best {
            LoggerService.debug(category: logCategory, "resolveLocalThumbnail: prefix match found: \(best.lastPathComponent)")
        }
        return best
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

