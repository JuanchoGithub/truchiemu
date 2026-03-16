import Foundation

struct SystemInfo: Identifiable, Codable, Hashable {
    var id: String           // e.g. "nes", "snes", "mame", "gba"
    var name: String         // e.g. "Nintendo Entertainment System"
    var manufacturer: String
    var extensions: [String] // without dot, e.g. ["nes", "fds"]
    var defaultCoreID: String?
    var iconName: String     // SF Symbol or bundled asset
    var year: String?
    var sortOrder: Int

    static let all: [SystemInfo] = SystemDatabase.systems
}

// MARK: - Known system list (seeded locally, refreshed from core-info repo)
enum SystemDatabase {
    static let systems: [SystemInfo] = [
        SystemInfo(id: "nes",          name: "Nintendo Entertainment System",   manufacturer: "Nintendo",   extensions: ["nes", "fds", "unf", "unif"], defaultCoreID: "nestopia_libretro",           iconName: "gamecontroller",       year: "1983", sortOrder: 1),
        SystemInfo(id: "snes",         name: "Super Nintendo",                  manufacturer: "Nintendo",   extensions: ["snes", "smc", "sfc", "fig", "bs"],  defaultCoreID: "snes9x_libretro",      iconName: "gamecontroller",       year: "1990", sortOrder: 2),
        SystemInfo(id: "n64",          name: "Nintendo 64",                     manufacturer: "Nintendo",   extensions: ["n64", "v64", "z64", "ndd"],  defaultCoreID: "mupen64plus_next_libretro",   iconName: "gamecontroller",       year: "1996", sortOrder: 3),
        SystemInfo(id: "gba",          name: "Game Boy Advance",                manufacturer: "Nintendo",   extensions: ["gba"],                        defaultCoreID: "mgba_libretro",              iconName: "iphone",               year: "2001", sortOrder: 4),
        SystemInfo(id: "gb",           name: "Game Boy",                        manufacturer: "Nintendo",   extensions: ["gb"],                         defaultCoreID: "mgba_libretro",              iconName: "iphone",               year: "1989", sortOrder: 5),
        SystemInfo(id: "gbc",          name: "Game Boy Color",                  manufacturer: "Nintendo",   extensions: ["gbc"],                        defaultCoreID: "mgba_libretro",              iconName: "iphone",               year: "1998", sortOrder: 6),
        SystemInfo(id: "nds",          name: "Nintendo DS",                     manufacturer: "Nintendo",   extensions: ["nds", "dsi"],                 defaultCoreID: "desmume_libretro",           iconName: "ipad",                 year: "2004", sortOrder: 7),
        SystemInfo(id: "genesis",      name: "Sega Genesis / Mega Drive",       manufacturer: "Sega",       extensions: ["md", "gen", "bin", "smd"],    defaultCoreID: "genesis_plus_gx_libretro",   iconName: "gamecontroller.fill",  year: "1988", sortOrder: 10),
        SystemInfo(id: "sms",          name: "Sega Master System",              manufacturer: "Sega",       extensions: ["sms"],                        defaultCoreID: "genesis_plus_gx_libretro",   iconName: "gamecontroller.fill",  year: "1985", sortOrder: 11),
        SystemInfo(id: "gamegear",     name: "Sega Game Gear",                  manufacturer: "Sega",       extensions: ["gg"],                         defaultCoreID: "genesis_plus_gx_libretro",   iconName: "iphone",               year: "1990", sortOrder: 12),
        SystemInfo(id: "saturn",       name: "Sega Saturn",                     manufacturer: "Sega",       extensions: ["cue", "toc", "m3u"],          defaultCoreID: "mednafen_saturn_libretro",   iconName: "opticaldisc",          year: "1994", sortOrder: 13),
        SystemInfo(id: "dreamcast",    name: "Sega Dreamcast",                  manufacturer: "Sega",       extensions: ["cdi", "gdi", "chd"],          defaultCoreID: "flycast_libretro",           iconName: "opticaldisc",          year: "1998", sortOrder: 14),
        SystemInfo(id: "psx",          name: "PlayStation",                     manufacturer: "Sony",       extensions: ["cue", "toc", "m3u", "pbp"],   defaultCoreID: "mednafen_psx_libretro",      iconName: "opticaldisc",          year: "1994", sortOrder: 20),
        SystemInfo(id: "ps2",          name: "PlayStation 2",                   manufacturer: "Sony",       extensions: ["iso", "chd"],                 defaultCoreID: "pcsx2_libretro",             iconName: "opticaldisc",          year: "2000", sortOrder: 21),
        SystemInfo(id: "psp",          name: "PlayStation Portable",            manufacturer: "Sony",       extensions: ["iso", "cso", "pbp"],          defaultCoreID: "ppsspp_libretro",            iconName: "ipad.landscape",       year: "2004", sortOrder: 22),
        SystemInfo(id: "mame",         name: "Arcade (MAME)",                   manufacturer: "Various",    extensions: ["zip", "7z"],                  defaultCoreID: "mame2003_plus_libretro",     iconName: "arcade.stick",         year: nil,    sortOrder: 30),
        SystemInfo(id: "fba",          name: "Arcade (FinalBurn Neo)",          manufacturer: "Various",    extensions: ["zip", "7z"],                  defaultCoreID: "fbneo_libretro",             iconName: "arcade.stick",         year: nil,    sortOrder: 31),
        SystemInfo(id: "atari2600",    name: "Atari 2600",                      manufacturer: "Atari",      extensions: ["a26", "bin"],                 defaultCoreID: "stella_libretro",            iconName: "gamecontroller",       year: "1977", sortOrder: 40),
        SystemInfo(id: "atari5200",    name: "Atari 5200",                      manufacturer: "Atari",      extensions: ["a52", "bin"],                 defaultCoreID: "a5200_libretro",             iconName: "gamecontroller",       year: "1982", sortOrder: 41),
        SystemInfo(id: "atari7800",    name: "Atari 7800",                      manufacturer: "Atari",      extensions: ["a78", "bin"],                 defaultCoreID: "prosystem_libretro",         iconName: "gamecontroller",       year: "1986", sortOrder: 42),
        SystemInfo(id: "lynx",         name: "Atari Lynx",                      manufacturer: "Atari",      extensions: ["lnx"],                        defaultCoreID: "handy_libretro",             iconName: "iphone.landscape",     year: "1989", sortOrder: 43),
        SystemInfo(id: "ngp",          name: "Neo Geo Pocket",                  manufacturer: "SNK",        extensions: ["ngp", "ngc"],                 defaultCoreID: "mednafen_ngp_libretro",      iconName: "iphone",               year: "1998", sortOrder: 50),
        SystemInfo(id: "pce",          name: "PC Engine / TurboGrafx-16",       manufacturer: "NEC",        extensions: ["pce", "cue"],                 defaultCoreID: "mednafen_pce_libretro",      iconName: "gamecontroller",       year: "1987", sortOrder: 60),
        SystemInfo(id: "pcfx",         name: "PC-FX",                           manufacturer: "NEC",        extensions: ["cue", "toc"],                 defaultCoreID: "mednafen_pcfx_libretro",     iconName: "opticaldisc",          year: "1994", sortOrder: 61),
    ]

    static func system(forExtension ext: String) -> SystemInfo? {
        let lower = ext.lowercased()
        return systems.first { $0.extensions.contains(lower) }
    }

    static func system(forID id: String) -> SystemInfo? {
        systems.first { $0.id == id }
    }
}
