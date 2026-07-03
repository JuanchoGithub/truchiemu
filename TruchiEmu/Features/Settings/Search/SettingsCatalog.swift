import Foundation

struct SettingsCatalogEntry {
    let page: SettingsView.Page
    let sectionID: String
    let sectionTitle: String
    let optionTitles: [String]
    let descriptionFragments: [String]
    let keywords: [String]

    init(
        page: SettingsView.Page,
        sectionID: String,
        sectionTitle: String,
        optionTitles: [String] = [],
        descriptionFragments: [String] = [],
        keywords: [String] = []
    ) {
        self.page = page
        self.sectionID = sectionID
        self.sectionTitle = sectionTitle
        self.optionTitles = optionTitles
        self.descriptionFragments = descriptionFragments
        self.keywords = keywords
    }
}

enum SettingsCatalog {
    static func entries() -> [SettingsCatalogEntry] {
        [
            SettingsCatalogEntry(
                page: .general, sectionID: "language",
                sectionTitle: "Language",
                optionTitles: ["English", "Spanish", "Portuguese"],
                keywords: ["language", "localization", "translation"]
            ),
            SettingsCatalogEntry(
                page: .general, sectionID: "theme",
                sectionTitle: "Theme",
                optionTitles: ["Accent color", "Light", "Dark", "Automatic"],
                keywords: ["theme", "accent", "color", "appearance", "mode", "light", "dark", "gaming", "tinted", "surfaces", "toolbar", "preset"]
            ),
            SettingsCatalogEntry(
                page: .general, sectionID: "application",
                sectionTitle: "Application",
                optionTitles: ["Check updates automatically", "Enable system notifications"],
                keywords: ["application", "version", "build", "notifications", "updates"]
            ),

            SettingsCatalogEntry(
                page: .saves, sectionID: "saveDirectories",
                sectionTitle: "Save Directories",
                optionTitles: ["Save Files (SRAM)", "Save States", "System / BIOS"],
                keywords: ["storage", "path", "folder", "directory", "disk", "size", "stats", "sram", "location", "migration"]
            ),
            SettingsCatalogEntry(
                page: .saves, sectionID: "saveStates",
                sectionTitle: "Save States",
                optionTitles: ["Auto-save on game exit", "Auto-load on game start", "Compress save states"],
                keywords: ["auto", "save", "exit", "load", "compress", "states", "lz4"]
            ),
            SettingsCatalogEntry(
                page: .saves, sectionID: "progressiveSaves",
                sectionTitle: "Progressive Saves",
                optionTitles: ["Auto slot count"],
                keywords: ["progressive", "saves", "auto", "slot", "rotation", "version", "count"]
            ),
            SettingsCatalogEntry(
                page: .saves, sectionID: "saveManager",
                sectionTitle: "Save Manager",
                optionTitles: ["Open Save Manager"],
                keywords: ["save", "manager", "browse", "delete", "manage", "review"]
            ),

            SettingsCatalogEntry(
                page: .library, sectionID: "displayOptions",
                sectionTitle: "Display Options",
                optionTitles: ["Show BIOS files", "Show hidden MAME files", "Merge GB/GBC", "Merge MAME/FBA"],
                keywords: ["display", "options", "bios", "files", "hidden", "mame", "sidebar", "merge", "gbc", "gb", "fbneo"]
            ),
            SettingsCatalogEntry(
                page: .library, sectionID: "region",
                sectionTitle: "Region",
                keywords: ["region", "box", "art", "cover", "usa", "japan", "europe", "world", "language", "core", "emulation"]
            ),
            SettingsCatalogEntry(
                page: .library, sectionID: "libraryFolders",
                sectionTitle: "Library Folders",
                optionTitles: ["Add Folder", "Rebuild library"],
                keywords: ["library", "folders", "roms", "games", "scan", "rescan", "primary", "subfolders", "refresh", "rebuild"]
            ),
            SettingsCatalogEntry(
                page: .library, sectionID: "hideRules",
                sectionTitle: "Hide Rules",
                keywords: ["hidden", "games", "category", "sidebar", "visibility"]
            ),
            SettingsCatalogEntry(
                page: .library, sectionID: "cache",
                sectionTitle: "Cache",
                keywords: ["extracted", "rom", "cache", "archive", "zip", "7z", "rar", "storage", "cleanup", "ttl"]
            ),
            SettingsCatalogEntry(
                page: .library, sectionID: "maintenance",
                sectionTitle: "Maintenance",
                keywords: ["maintenance", "rescan", "scan", "refresh", "full", "library", "total", "games", "folder", "setup", "wizard"]
            ),

            SettingsCatalogEntry(
                page: .perSystem, sectionID: "systemList",
                sectionTitle: "Per-System List",
                optionTitles: ["Nintendo", "Sony", "Sega", "Arcade", "Game Boy", "Game Boy Advance", "SNES", "NES", "N64", "Genesis", "PlayStation"],
                keywords: ["system", "per-system", "nes", "snes", "n64", "genesis", "gba", "ps1"]
            ),
            SettingsCatalogEntry(
                page: .perSystem, sectionID: "tabBoxes",
                sectionTitle: "Per-System Tabs",
                optionTitles: ["Bezels", "Box Art", "Cheats", "Controls", "Core", "Hardcore", "Shader"],
                keywords: ["per-system", "bezels", "box", "cheats", "controls", "core", "hardcore", "shader", "style"]
            ),

            SettingsCatalogEntry(
                page: .cheats, sectionID: "librarySummary",
                sectionTitle: "Cheat Library Summary",
                optionTitles: ["Cheat files", "Storage", "Custom"],
                keywords: ["cheat", "library", "summary", "files", "storage", "custom", "last", "updated"]
            ),
            SettingsCatalogEntry(
                page: .cheats, sectionID: "behavior",
                sectionTitle: "Apply Cheats on Launch Behavior",
                optionTitles: ["Apply cheats on launch", "Show cheat notifications"],
                keywords: ["apply", "launch", "notifications", "behavior"]
            ),
            SettingsCatalogEntry(
                page: .cheats, sectionID: "onlineDatabase",
                sectionTitle: "Online Database",
                optionTitles: ["Download all cheats", "Update system", "Download specific system"],
                keywords: ["online", "database", "download", "network", "update"]
            ),
            SettingsCatalogEntry(
                page: .cheats, sectionID: "actions",
                sectionTitle: "Actions",
                optionTitles: ["Show in Finder", "Clear downloaded cheats"],
                keywords: ["actions", "show", "finder", "clear", "downloaded", "cheats"]
            ),

            SettingsCatalogEntry(
                page: .controllers, sectionID: "controllers",
                sectionTitle: "Controllers",
                optionTitles: ["Player 1", "Player 2", "Player 3", "Player 4"],
                keywords: ["controllers", "gamepad", "keyboard", "mapping", "player", "buttons", "input"]
            ),

            SettingsCatalogEntry(
                page: .analogMouse, sectionID: "analogMouse",
                sectionTitle: "Analog Mouse",
                optionTitles: ["Sensitivity", "Deadzone"],
                keywords: ["analog", "mouse", "stick", "controller", "sensitivity", "deadzone", "pointer", "cursor", "dos", "scummvm"]
            ),

            SettingsCatalogEntry(
                page: .boxArt, sectionID: "libretroCDN",
                sectionTitle: "Libretro Thumbnails",
                keywords: ["libretro", "thumbnail", "cdn", "url", "source"]
            ),
            SettingsCatalogEntry(
                page: .boxArt, sectionID: "launchbox",
                sectionTitle: "LaunchBox",
                keywords: ["launchbox", "gamesdb", "download", "scan", "fallback"]
            ),
            SettingsCatalogEntry(
                page: .boxArt, sectionID: "screenscraper",
                sectionTitle: "ScreenScraper",
                optionTitles: ["Username", "Password"],
                keywords: ["screenscraper", "credentials", "free", "account"]
            ),
            SettingsCatalogEntry(
                page: .boxArt, sectionID: "priority",
                sectionTitle: "Priority",
                keywords: ["priority", "crc", "matching", "filename", "fallback", "http", "head", "check"]
            ),
            SettingsCatalogEntry(
                page: .boxArt, sectionID: "performance",
                sectionTitle: "Performance",
                keywords: ["performance", "indexing", "manifest", "refresh", "repository", "library", "404"]
            ),

            SettingsCatalogEntry(
                page: .bezels, sectionID: "storage",
                sectionTitle: "Bezel Storage",
                keywords: ["storage", "path", "folder", "directory"]
            ),
            SettingsCatalogEntry(
                page: .bezels, sectionID: "downloads",
                sectionTitle: "Bezel Downloads",
                keywords: ["download", "bezels", "project", "update"]
            ),
            SettingsCatalogEntry(
                page: .bezels, sectionID: "statistics",
                sectionTitle: "Bezel Statistics",
                keywords: ["statistics", "files", "space", "supported"]
            ),
            SettingsCatalogEntry(
                page: .bezels, sectionID: "dangerZone",
                sectionTitle: "Bezel Danger Zone",
                keywords: ["delete", "remove", "clear", "bezels"]
            ),

            SettingsCatalogEntry(
                page: .retroAchievements, sectionID: "enable",
                sectionTitle: "RetroAchievements",
                optionTitles: ["Enable RetroAchievements"],
                keywords: ["retroachievements", "enable", "disable"]
            ),
            SettingsCatalogEntry(
                page: .retroAchievements, sectionID: "account",
                sectionTitle: "Account",
                optionTitles: ["Username", "API key", "Login", "Logout"],
                keywords: ["account", "username", "login", "logout", "api", "key"]
            ),
            SettingsCatalogEntry(
                page: .retroAchievements, sectionID: "hardcore",
                sectionTitle: "Hardcore Mode",
                optionTitles: ["Enable hardcore globally", "Default hardcore by system"],
                keywords: ["hardcore", "mode"]
            ),
            SettingsCatalogEntry(
                page: .retroAchievements, sectionID: "display",
                sectionTitle: "Display",
                optionTitles: ["Grid view", "List view"],
                keywords: ["display", "view", "grid", "list", "achievements"]
            ),
            SettingsCatalogEntry(
                page: .retroAchievements, sectionID: "richPresence",
                sectionTitle: "Rich Presence",
                keywords: ["rich", "presence", "game", "active"]
            ),
            SettingsCatalogEntry(
                page: .retroAchievements, sectionID: "refresh",
                sectionTitle: "Refresh / Cache",
                keywords: ["refresh", "cache", "systems", "games", "data"]
            ),
            SettingsCatalogEntry(
                page: .retroAchievements, sectionID: "about",
                sectionTitle: "About",
                keywords: ["about", "info", "retro", "achievements"]
            ),

            SettingsCatalogEntry(
                page: .perSystem, sectionID: "systems",
                sectionTitle: "Systems",
                optionTitles: ["Nintendo", "Sony", "Sega", "Arcade", "Game Boy", "Game Boy Advance", "SNES", "NES", "N64", "Genesis", "PlayStation"],
                keywords: ["system", "systems", "nes", "snes", "n64", "genesis", "gba", "ps1"]
            ),
            SettingsCatalogEntry(
                page: .perSystem, sectionID: "coreList",
                sectionTitle: "Core List",
                keywords: ["cores", "core", "list", "download", "update"]
            ),

            SettingsCatalogEntry(
                page: .logging, sectionID: "levels",
                sectionTitle: "Log Levels",
                optionTitles: ["None", "Info", "Debug", "Extreme"],
                keywords: ["logging", "log", "debug", "console", "output", "level", "verbosity", "info", "extreme"]
            ),
            SettingsCatalogEntry(
                page: .logging, sectionID: "files",
                sectionTitle: "Log Files",
                keywords: ["logging", "file", "folder", "location", "path", "size", "archive"]
            ),
            SettingsCatalogEntry(
                page: .logging, sectionID: "maintenance",
                sectionTitle: "Log Maintenance",
                optionTitles: ["Clear logs", "Trim logs"],
                keywords: ["logging", "maintenance", "clear", "trim", "delete", "archive", "rotation", "size"]
            ),

            SettingsCatalogEntry(
                page: .moveList, sectionID: "overview",
                sectionTitle: "Move List Overview",
                optionTitles: ["Browse games"],
                keywords: ["move", "list", "moves", "fighting", "combo", "frame", "data", "timing", "input"]
            ),

            SettingsCatalogEntry(
                page: .streaming, sectionID: "enable",
                sectionTitle: "Streaming",
                optionTitles: ["Enable streaming"],
                keywords: ["streaming", "recording", "twitch", "youtube", "stream", "key", "credentials"]
            ),
            SettingsCatalogEntry(
                page: .streaming, sectionID: "recordWithShaders",
                sectionTitle: "Record with Shaders",
                optionTitles: ["Record with shaders applied"],
                keywords: ["record", "shaders", "applied", "gpu"]
            ),
            SettingsCatalogEntry(
                page: .streaming, sectionID: "twitch",
                sectionTitle: "Twitch",
                optionTitles: ["Twitch stream key", "Twitch stream URL", "Verify Twitch"],
                keywords: ["twitch", "stream", "key", "url", "verify"]
            ),
            SettingsCatalogEntry(
                page: .streaming, sectionID: "youtube",
                sectionTitle: "YouTube",
                optionTitles: ["YouTube stream key", "YouTube stream URL", "Verify YouTube"],
                keywords: ["youtube", "stream", "key", "url", "verify"]
            ),
            SettingsCatalogEntry(
                page: .streaming, sectionID: "custom",
                sectionTitle: "Custom Stream",
                optionTitles: ["Custom stream name", "Custom stream key", "Custom stream URL", "Verify custom"],
                keywords: ["custom", "stream", "key", "url", "server", "name"]
            ),
            SettingsCatalogEntry(
                page: .streaming, sectionID: "output",
                sectionTitle: "Output Path",
                optionTitles: ["Output folder", "Browse"],
                keywords: ["save", "recording", "output", "path", "file", "location"]
            ),
            SettingsCatalogEntry(
                page: .streaming, sectionID: "quality",
                sectionTitle: "Quality",
                optionTitles: ["Low", "Medium", "High", "Lossless", "H.264", "HEVC", "ProRes 422", "ProRes 4444", "Bitrate", "Frame rate"],
                keywords: ["quality", "low", "medium", "high", "lossless", "bitrate", "codec", "frame", "rate", "resolution", "video", "audio"]
            ),
            SettingsCatalogEntry(
                page: .streaming, sectionID: "screenshots",
                sectionTitle: "Screenshots",
                optionTitles: ["Include native frame"],
                keywords: ["screenshot", "capture", "native", "include", "frame"]
            ),
            SettingsCatalogEntry(
                page: .streaming, sectionID: "shareButton",
                sectionTitle: "Share Button",
                optionTitles: ["Single press", "Long press"],
                keywords: ["share", "button", "single", "long", "press", "behavior", "screenshot", "recording", "stream"]
            ),
            SettingsCatalogEntry(
                page: .streaming, sectionID: "saveLastMoments",
                sectionTitle: "Save Last Moments",
                optionTitles: ["Enable game clip buffer", "Clip duration", "30 seconds", "60 seconds", "2 minutes", "5 minutes", "10 minutes", "15 minutes", "Custom"],
                keywords: ["save", "last", "moments", "clip", "buffer", "retro", "game", "rolling", "duration"]
            ),
            SettingsCatalogEntry(
                page: .streaming, sectionID: "recordingBadge",
                sectionTitle: "Recording Overlay",
                optionTitles: ["Show REC badge", "Top Left", "Top Right", "Bottom Left", "Bottom Right", "Top Center", "Bottom Center"],
                keywords: ["recording", "badge", "overlay", "rec", "indicator", "live", "position"]
            ),

            SettingsCatalogEntry(
                page: .hotkeys, sectionID: "general",
                sectionTitle: "General Shortcuts",
                optionTitles: [
                    "Quick Save",
                    "Quick Load",
                    "Undo Load",
                    "Next Slot",
                    "Previous Slot",
                    "Toggle Input Capture"
                ],
                keywords: ["hotkeys", "keyboard", "shortcuts", "save", "load", "slot", "undo", "training", "input", "capture", "quick"]
            ),
            SettingsCatalogEntry(
                page: .hotkeys, sectionID: "slots",
                sectionTitle: "Slot Shortcuts",
                optionTitles: ["Slot 0", "Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5", "Slot 6", "Slot 7", "Slot 8", "Slot 9"],
                keywords: ["slots", "slot", "0-9", "shortcut"]
            ),
            SettingsCatalogEntry(
                page: .hotkeys, sectionID: "training",
                sectionTitle: "Training Mode",
                optionTitles: [
                    "Toggle Training Mode",
                    "Training Instant Reset",
                    "Toggle Tape Recording",
                    "Start Tape Playback"
                ],
                keywords: ["training", "mode", "reset", "recording", "playback", "tape"]
            ),
            SettingsCatalogEntry(
                page: .hotkeys, sectionID: "screenshots",
                sectionTitle: "Screenshots",
                optionTitles: ["Screenshot"],
                keywords: ["screenshot", "capture", "photo", "picture", "save", "share", "button"]
            ),
            SettingsCatalogEntry(
                page: .hotkeys, sectionID: "reset",
                sectionTitle: "Reset to Defaults",
                optionTitles: ["Reset All Hotkeys"],
                keywords: ["reset", "defaults", "restore"]
            ),

            SettingsCatalogEntry(
                page: .reset, sectionID: "all",
                sectionTitle: "Reset Settings",
                optionTitles: ["Reset Hotkeys", "Reset Save Directories", "Reset Startup Tab", "Restore All Defaults"],
                keywords: ["reset", "restore", "defaults", "factory", "clear", "wipe"]
            ),

            SettingsCatalogEntry(
                page: .help, sectionID: "faq",
                sectionTitle: "FAQ",
                keywords: ["faq", "questions", "frequent", "help", "how"]
            ),
            SettingsCatalogEntry(
                page: .help, sectionID: "resources",
                sectionTitle: "Resources",
                optionTitles: ["Documentation", "GitHub"],
                keywords: ["resources", "links", "documentation", "troubleshooting", "github"]
            ),

            SettingsCatalogEntry(
                page: .genre, sectionID: "overview",
                sectionTitle: "Genre Overview",
                keywords: ["overview", "total", "merged", "custom", "hidden"]
            ),
            SettingsCatalogEntry(
                page: .genre, sectionID: "genres",
                sectionTitle: "Genres",
                keywords: ["genres", "genre", "tag", "categories", "merge", "rename"]
            ),
        ]
    }

    @MainActor
    static func bootstrap(into index: SettingsIndex = .shared) {
        for entry in entries() {
            index.registerIfNeeded(
                page: entry.page,
                sectionID: entry.sectionID,
                keywords: entry.keywords.joined(separator: " "),
                sectionTitle: entry.sectionTitle,
                optionTitles: entry.optionTitles,
                descriptionFragments: entry.descriptionFragments
            )
        }
    }
}
