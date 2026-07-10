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

    /// Computes the RetroAchievements hash for a ROM at the given path.
    /// Delegates to rcheevos' `rc_hash_generate_from_file` which handles
    /// all disc image formats (CHD, GDI, CUE/BIN, ISO, etc.) and uses the
    /// correct per-system algorithm that matches the RA server.
    static func hashRom(at path: String, systemID: String) -> String? {
        guard let consoleID = consoleIDForSystem[systemID.lowercased()] else { return nil }

        var hashBytes = [CChar](repeating: 0, count: 33)
        let result = rcheevos_hash_generate(path, consoleID, &hashBytes, 33)
        guard result != 0 else { return nil }

        return String(cString: hashBytes)
    }
}
