import Foundation

// Console IDs matching rcheevos' rc_consoles.h. These are the identifiers
// used by RetroAchievements to determine the hash algorithm for each system.
private let consoleIDForSystem: [String: UInt32] = {
    // Full mapping from systemID (lowercased) to RC_CONSOLE_* values.
    // Multiple aliases often map to the same console (e.g. "psx" and "ps1").
    let pairs: [(String, UInt32)] = [
        ("nes", 7),
        ("snes", 3),
        ("snes-msu", 3),
        ("sufami", 3),
        ("satellaview", 3),
        ("n64", 2),
        ("gamecube", 16),
        ("wii", 19),
        ("nds", 18),
        ("gb", 4),
        ("gbc", 6),
        ("gba", 5),
        ("virtualboy", 28),
        ("pokemonmini", 24),
        ("fds", 81),
        ("psx", 12),
        ("ps1", 12),
        ("ps2", 21),
        ("psp", 41),
        ("dreamcast", 40),
        ("saturn", 39),
        ("genesis", 1),
        ("megadrive", 1),
        ("sms", 11),
        ("gamegear", 15),
        ("32x", 10),
        ("sega32x", 10),
        ("segacd", 9),
        ("sega_cd", 9),
        ("sg-1000", 33),
        ("mame", 27),
        ("arcade", 27),
        ("mess", 27),
        ("ume", 27),
        ("3do", 43),
        ("atari2600", 25),
        ("atari7800", 51),
        ("jaguar", 17),
        ("jaguarcd", 77),
        ("lynx", 13),
        ("pce", 8),
        ("tg16", 8),
        ("supergrafx", 8),
        ("pcecd", 76),
        ("tgcd", 76),
        ("pcfx", 49),
        ("amstradcpc", 37),
        ("apple2", 38),
        ("apple2gs", 38),
        ("msx", 29),
        ("msx2", 29),
        ("wonderswan", 53),
        ("wonderswancolor", 53),
        ("coleco", 44),
        ("intellivision", 45),
        ("channelf", 57),
        ("channelF", 57),
        ("vectrex", 46),
        ("odyssey2", 23),
        ("ngp", 14),
        ("ngpc", 14),
        ("neocd", 56),
        ("neocdz", 56),
        ("arduboy", 71),
        ("wasm4", 72),
        ("megaduck", 69),
        ("supervision", 63),
    ]
    return Dictionary(uniqueKeysWithValues: pairs)
}()

enum RomHasher {

    /// Maps a TruchiEmu systemID to the RetroAchievements console ID used by
    /// rcheevos. Returns 0 when unknown (rcheevos treats 0 as "don't hash").
    static func raConsoleID(for systemID: String) -> Int {
        Int(consoleIDForSystem[systemID.lowercased()] ?? 0)
    }

    /// Computes the RetroAchievements hash for a ROM at the given path.
    /// Delegates to rcheevos' `rc_hash_generate_from_file` which handles
    /// all disc image formats (CHD, GDI, CUE/BIN, ISO, etc.) and uses the
    /// correct per-system algorithm that matches the RA server.
    static func hashRom(at path: String, systemID: String) -> String? {
        guard let consoleID = consoleIDForSystem[systemID.lowercased()] else { return nil }

        // For disc-based games the path may point at a raw track file
        // (e.g. `XXX (Track 01).bin`) rather than the disc descriptor. rcheevos
        // needs the descriptor (.cue/.gdi/.ccd/.toc/.mds) to compute the
        // RetroAchievements disc hash, so resolve to a sibling descriptor
        // when one exists.
        let resolvedPath = resolveDiscDescriptor(for: path)

        var hashBytes = [CChar](repeating: 0, count: 33)
        let result = rcheevos_hash_generate(resolvedPath, consoleID, &hashBytes, 33)
        guard result != 0 else { return nil }

        return String(cString: hashBytes)
    }

    /// If `path` is a raw disc track (`.bin`/`.iso`/`.img`) and a sibling disc
    /// descriptor of a known type exists, returns that descriptor's path so
    /// rcheevos can compute the correct disc hash. Otherwise returns `path`.
    private static func resolveDiscDescriptor(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        guard ["bin", "iso", "img"].contains(ext) else { return path }

        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let descriptors = ["cue", "gdi", "ccd", "toc", "mds"]

        // Prefer a descriptor that shares the track's filename stem.
        for d in descriptors {
            let candidate = dir.appendingPathComponent("\(stem).\(d)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }

        // Fall back to any descriptor in the same folder.
        if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for file in contents where descriptors.contains(file.pathExtension.lowercased()) {
                return file.path
            }
        }

        return path
    }
}
