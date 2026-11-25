import Foundation

/// Broad hardware family of a system, used to rank recommendations.
///
/// The classification lives in code and not in `SystemDatabase.json` for the same
/// reason as the `diskBasedIDs` set in `SystemDatabase._loadSystems()`: the
/// bundled JSON is data, and this mapping is behaviour that ships with the app.
enum SystemType: String {
    case console
    case handheld
    case computer
    case arcade

    /// Systems that appear in no set default to `.console`.
    static func type(forSystemID id: String) -> SystemType {
        if handheldIDs.contains(id) { return .handheld }
        if arcadeIDs.contains(id) { return .arcade }
        if computerIDs.contains(id) { return .computer }
        return .console
    }

    private static let handheldIDs: Set<String> = [
        "gb", "gbc", "gba", "nds", "3ds",
        "gamegear", "lynx", "ngp", "ngpc", "wonderswan", "wonderswancolor",
        "virtual_boy", "pokemon_mini", "tamagotchi", "supervision", "segapico",
        "p2000t", "mega_duck", "J2ME", "arduboy", "ti_83", "chip_8",
        "psp", "psvita",
    ]

    private static let arcadeIDs: Set<String> = [
        "mame", "fba", "neogeo", "dice", "mess", "hbmame",
        "daphne", "laserdisc", "arcadia", "syobonaction", "jumpnbump",
        "bomberman", "redbook", "gong",
    ]

    private static let computerIDs: Set<String> = [
        "dos", "scummvm", "amiga", "commodore_amiga", "mac68k", "atari_st", "apple_ii",
        "commodore_64", "commodore_c128", "commodore_c64", "commodore_c64_supercpu",
        "commodore_c64dtv", "commodore_cbm2", "commodore_cbm5x0", "commodore_pet",
        "commodore_plus4", "commodore_vic20",
        "zx_spectrum", "zx81", "msx", "sharp_x1", "sharp_x68000",
        "pc_88", "pc_98", "pcxt", "bbcmicro", "cpc", "ep128",
        "tic80", "pico8", "uzebox", "uxn", "lowresnx", "wasm4",
        "craft", "chailove", "2048", "puzzlescript", "bgdi",
        "nxengine", "openlara", "wolfenstein3d", "doom", "doom_3",
        "quake_1", "quake_2", "quake_3", "xrick", "dinothawr", "vircon32",
        "zmachine", "onscripter", "onsyuri", "doukutsu-rs", "sdlpal",
        "rvvm", "uw8", "cruzes", "anarch", "superbroswar", "vaporspec",
        "music", "game_music",
    ]
}

extension SystemInfo {
    var type: SystemType { SystemType.type(forSystemID: id) }
}
