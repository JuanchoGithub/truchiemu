import Foundation

/// Maps internal system IDs to libretro-thumbnails CDN folder names (https://thumbnails.libretro.com/).
enum LibretroThumbnailResolver {
    static let defaultBaseURL = URL(string: "https://thumbnails.libretro.com")!

    /// Prefer `ROM.thumbnailLookupSystemID` when identification matched a different Libretro set (e.g. GB vs GBC).
    static func effectiveThumbnailSystemID(for rom: ROM) -> String? {
        rom.thumbnailLookupSystemID ?? rom.systemID
    }

    static func libretroFolderName(forSystemID systemID: String) -> String? {
        let map: [String: String] = [
            "nes": "Nintendo - Nintendo Entertainment System",
            "snes": "Nintendo - Super Nintendo Entertainment System",
            "n64": "Nintendo - Nintendo 64",
            "gba": "Nintendo - Game Boy Advance",
            "gb": "Nintendo - Game Boy",
            "gbc": "Nintendo - Game Boy Color",
            "nds": "Nintendo - Nintendo DS",
            "genesis": "Sega - Mega Drive - Genesis",
            "sms": "Sega - Master System - Mark III",
            "gamegear": "Sega - Game Gear",
            "saturn": "Sega - Saturn",
            "dreamcast": "Sega - Dreamcast",
            "psx": "Sony - PlayStation",
            "ps2": "Sony - PlayStation 2",
            "psp": "Sony - PlayStation Portable",
            "mame": "MAME",
            "fba": "FBNeo - Arcade Games",
            "atari2600": "Atari - 2600",
            "atari5200": "Atari - 5200",
            "atari7800": "Atari - 7800",
            "lynx": "Atari - Lynx",
            "ngp": "SNK - Neo Geo Pocket",
            "pce": "NEC - PC Engine - TurboGrafx 16",
            "pcfx": "NEC - PC-FX",
        ]
        return map[systemID.lowercased()]
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

    /// Tier 2: strip `[tags]` and trailing `(Region)` / `(En,Fr)`-style parentheticals from a ROM filename stem.
    static func stripRomFilenameTags(_ filenameStem: String) -> String {
        var s = filenameStem
        while let r = s.range(of: "\\[[^\\]]+\\]", options: .regularExpression) {
            s.removeSubrange(r)
        }
        s = s.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        var prev = ""
        while prev != s {
            prev = s
            if let r = s.range(of: "\\([^\\)]+\\) *$", options: .regularExpression) {
                s.removeSubrange(r)
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fuzzy fallback: remove all `( … )` segments for a second pass on Named_Boxarts.
    static func stripParenthesesForFuzzyMatch(_ name: String) -> String {
        var s = name
        while let r = s.range(of: "\\([^\\)]+\\)", options: .regularExpression) {
            s.removeSubrange(r)
        }
        return s.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func buildThumbnailURL(
        base: URL,
        systemFolder: String,
        typeFolder: String,
        fileName: String
    ) -> URL {
        let name = fileName.hasSuffix(".png") ? fileName : "\(fileName).png"
        return base
            .appendingPathComponent(systemFolder)
            .appendingPathComponent(typeFolder)
            .appendingPathComponent(name)
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

    /// All CDN URLs to try for one resolved title (primary + safe + fuzzy boxart).
    static func candidateURLs(
        base: URL,
        systemFolder: String,
        gameTitle: String,
        priority: LibretroThumbnailPriority
    ) -> [URL] {
        let primary = gameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primary.isEmpty else { return [] }

        let safe = libretroFilesystemSafeName(primary)
        let fuzzy = stripParenthesesForFuzzyMatch(primary)

        var urls: [URL] = []
        var seen = Set<URL>()

        func appendUnique(_ u: URL) {
            if !seen.contains(u) {
                seen.insert(u)
                urls.append(u)
            }
        }

        let typeFolders = orderedThumbnailTypeFolders(priority: priority)
        var titleVariants: [String] = [primary]
        if safe != primary, !safe.isEmpty { titleVariants.append(safe) }
        for titleVariant in titleVariants {
            for folder in typeFolders {
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: folder, fileName: "\(titleVariant).png"))
            }
        }

        if fuzzy != primary && fuzzy != safe && !fuzzy.isEmpty {
            appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzy).png"))
            let fuzzySafe = libretroFilesystemSafeName(fuzzy)
            if fuzzySafe != fuzzy {
                appendUnique(buildThumbnailURL(base: base, systemFolder: systemFolder, typeFolder: "Named_Boxarts", fileName: "\(fuzzySafe).png"))
            }
        }

        return urls
    }

    /// Resolve a display title: CRC/DAT (tier 1), else filename sanitization (tier 2).
    static func resolveGameTitle(
        for rom: ROM,
        useCRC: Bool,
        fallbackFilename: Bool
    ) async -> String? {
        let systemID = rom.systemID ?? ""

        if useCRC, !systemID.isEmpty, SystemDatabase.system(forID: systemID) != nil {
            if let info = await ROMIdentifierService.shared.identifyReturningGameInfo(rom: rom) {
                let n = info.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { return n }
            }
        }

        if fallbackFilename {
            let stem = rom.path.deletingPathExtension().lastPathComponent
            let stripped = stripRomFilenameTags(stem)
            if !stripped.isEmpty { return stripped }
        }

        if let meta = rom.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !meta.isEmpty {
            return meta
        }

        let stem = rom.path.deletingPathExtension().lastPathComponent
        return stripRomFilenameTags(stem)
    }

    /// Strict file name match, else shortest prefix match among `.png` / `.jpg` in `folder`.
    static func resolveLocalThumbnail(named sanitizedStem: String, in folder: URL) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path),
              let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return nil
        }

        let exts = ["png", "PNG", "jpg", "JPG", "jpeg", "JPEG"]
        let candidates = files.filter { exts.contains($0.pathExtension) }

        let exactNames = [
            "\(sanitizedStem).png", "\(sanitizedStem).PNG",
            "\(sanitizedStem).jpg", "\(sanitizedStem).JPEG",
        ]
        for e in exactNames {
            if let hit = candidates.first(where: { $0.lastPathComponent == e }) {
                return hit
            }
        }

        let prefix = sanitizedStem
        let prefixed = candidates.filter { $0.deletingPathExtension().lastPathComponent.hasPrefix(prefix) }
        guard !prefixed.isEmpty else { return nil }
        return prefixed.min(by: { $0.lastPathComponent.count < $1.lastPathComponent.count })
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

