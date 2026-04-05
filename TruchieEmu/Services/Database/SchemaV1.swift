import Foundation
import SQLite3
import os.log

/// Creates the V1 schema — all tables, indexes for the initial release.
enum SchemaV1 {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "SchemaV1")

    static func create(_ db: OpaquePointer) throws {
        let statements: [(String, String)] = [
            ("schema_version", schemaVersionTable),
            ("library_folders", libraryFoldersTable),
            ("file_index", fileIndexTable),
            ("roms", romsTable),
            ("rom_metadata", romMetadataTable),
            ("settings", settingsTable),
            ("installed_cores", installedCoresTable),
            ("available_cores", availableCoresTable),
            ("controller_mappings", controllerMappingsTable),
            ("achievements_config", achievementsConfigTable),
            ("cheats_store", cheatsStoreTable),
            ("categories", categoriesTable),
            ("bezel_preferences", bezelPreferencesTable),
            ("box_art_preferences", boxArtPreferencesTable),
            ("core_options", coreOptionsTable),
            ("shader_presets", shaderPresetsTable),
            ("idx_roms_path", idxRomsPath),
            ("idx_roms_system_id", idxRomsSystemId),
            ("idx_roms_crc32", idxRomsCrc32),
            ("idx_rom_metadata_path_key", idxRomMetadataPathKey),
            ("idx_installed_cores_id", idxInstalledCoresId),
            ("idx_available_cores_id", idxAvailableCoresId),
            ("idx_categories_system_id", idxCategoriesSystemId),
            ("idx_core_options_core_id", idxCoreOptionsCoreId),
        ]

        var created = 0
        for (name, sql) in statements {
            var checkStmt: OpaquePointer?
            let checkSQL = "SELECT name FROM sqlite_master WHERE type IN ('table','index') AND name = '\(name)'"
            let checkRc = sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil)
            var exists = false
            if checkRc == SQLITE_OK, let checkStmt = checkStmt {
                if sqlite3_step(checkStmt) == SQLITE_ROW { exists = true }
                sqlite3_finalize(checkStmt)
            }
            guard !exists else { continue }

            var execStmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(db, sql, -1, &execStmt, nil)
            if rc == SQLITE_OK, let execStmt = execStmt {
                let stepRc = sqlite3_step(execStmt)
                sqlite3_finalize(execStmt)
                if stepRc == SQLITE_DONE {
                    logger.info("Created: \(name)")
                    created += 1
                } else {
                    logger.error("Failed to create \(name): step=\(stepRc)")
                }
            } else {
                logger.error("Failed to prepare CREATE for \(name)")
            }
        }
        logger.info("Schema V1: created \(created) tables/indexes")
    }

    // ─── Table DDL ─────────────────────────────────────────────────────────

    static let schemaVersionTable = """
        CREATE TABLE IF NOT EXISTS schema_version (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            version INTEGER NOT NULL DEFAULT 0,
            applied_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
        )
    """

    static let libraryFoldersTable = """
        CREATE TABLE IF NOT EXISTS library_folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url_path TEXT NOT NULL UNIQUE,
            bookmark_data BLOB NOT NULL,
            added_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            parent_path TEXT,
            is_primary INTEGER NOT NULL DEFAULT 1
        )
    """

    static let fileIndexTable = """
        CREATE TABLE IF NOT EXISTS file_index (
            path TEXT PRIMARY KEY,
            size INTEGER NOT NULL,
            mod_time REAL NOT NULL
        )
    """

    static let romsTable = """
        CREATE TABLE IF NOT EXISTS roms (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            system_id TEXT,
            box_art_path TEXT,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            last_played REAL,
            total_playtime REAL NOT NULL DEFAULT 0,
            times_played INTEGER NOT NULL DEFAULT 0,
            selected_core_id TEXT,
            custom_name TEXT,
            use_custom_core INTEGER NOT NULL DEFAULT 0,
            metadata_json TEXT,
            is_bios INTEGER NOT NULL DEFAULT 0,
            is_hidden INTEGER NOT NULL DEFAULT 0,
            category TEXT NOT NULL DEFAULT 'game',
            crc32 TEXT,
            thumbnail_system_id TEXT,
            screenshot_paths_json TEXT,
            settings_json TEXT,
            is_identified INTEGER NOT NULL DEFAULT 0
        )
    """

    static let romMetadataTable = """
        CREATE TABLE IF NOT EXISTS rom_metadata (
            path_key TEXT PRIMARY KEY,
            crc32 TEXT,
            title TEXT,
            year TEXT,
            developer TEXT,
            publisher TEXT,
            genre TEXT,
            players INTEGER,
            description TEXT,
            rating REAL,
            thumbnail_system_id TEXT,
            box_art_path TEXT,
            title_screen_path TEXT,
            screenshot_paths_json TEXT,
            custom_core_id TEXT
        )
    """

    static let settingsTable = """
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
    """

    static let installedCoresTable = """
        CREATE TABLE IF NOT EXISTS installed_cores (
            core_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            version_tag TEXT,
            install_date INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            system_ids_json TEXT,
            dylib_path TEXT,
            is_active INTEGER NOT NULL DEFAULT 1
        )
    """

    static let availableCoresTable = """
        CREATE TABLE IF NOT EXISTS available_cores (
            core_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            system_ids_json TEXT,
            download_url TEXT,
            last_checked INTEGER DEFAULT 0
        )
    """

    static let controllerMappingsTable = """
        CREATE TABLE IF NOT EXISTS controller_mappings (
            mapping_id TEXT PRIMARY KEY,
            device_type TEXT NOT NULL,
            config_json TEXT NOT NULL
        )
    """

    static let achievementsConfigTable = """
        CREATE TABLE IF NOT EXISTS achievements_config (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            username TEXT,
            token TEXT,
            is_hardcore INTEGER NOT NULL DEFAULT 0,
            is_enabled INTEGER NOT NULL DEFAULT 0
        )
    """

    static let cheatsStoreTable = """
        CREATE TABLE IF NOT EXISTS cheats_store (
            rom_key TEXT PRIMARY KEY,
            cheats_json TEXT NOT NULL
        )
    """

    static let categoriesTable = """
        CREATE TABLE IF NOT EXISTS categories (
            category_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            system_id TEXT,
            color_hex TEXT,
            rom_keys_json TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0
        )
    """

    static let bezelPreferencesTable = """
        CREATE TABLE IF NOT EXISTS bezel_preferences (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            storage_mode TEXT NOT NULL DEFAULT 'libraryRelative',
            custom_folder_path TEXT,
            library_folder_path TEXT,
            initial_setup_complete INTEGER NOT NULL DEFAULT 0,
            last_prompted_library_count INTEGER NOT NULL DEFAULT 0,
            download_log_json TEXT
        )
    """

    static let boxArtPreferencesTable = """
        CREATE TABLE IF NOT EXISTS box_art_preferences (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            credentials_json TEXT,
            use_libretro INTEGER NOT NULL DEFAULT 1,
            use_head_check INTEGER NOT NULL DEFAULT 1,
            fallback_filename TEXT
        )
    """

    static let coreOptionsTable = """
        CREATE TABLE IF NOT EXISTS core_options (
            core_id TEXT NOT NULL,
            option_key TEXT NOT NULL,
            option_value TEXT,
            is_override INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (core_id, option_key)
        )
    """

    static let shaderPresetsTable = """
        CREATE TABLE IF NOT EXISTS shader_presets (
            id TEXT PRIMARY KEY,
            preset_json TEXT NOT NULL,
            window_position_json TEXT
        )
    """

    // ─── Index DDL ─────────────────────────────────────────────────────────

    static let idxRomsPath = "CREATE INDEX IF NOT EXISTS idx_roms_path ON roms(path)"
    static let idxRomsSystemId = "CREATE INDEX IF NOT EXISTS idx_roms_system_id ON roms(system_id)"
    static let idxRomsCrc32 = "CREATE INDEX IF NOT EXISTS idx_roms_crc32 ON roms(crc32)"
    static let idxRomMetadataPathKey = "CREATE INDEX IF NOT EXISTS idx_rom_metadata_path_key ON rom_metadata(path_key)"
    static let idxInstalledCoresId = "CREATE INDEX IF NOT EXISTS idx_installed_cores_id ON installed_cores(core_id)"
    static let idxAvailableCoresId = "CREATE INDEX IF NOT EXISTS idx_available_cores_id ON available_cores(core_id)"
    static let idxCategoriesSystemId = "CREATE INDEX IF NOT EXISTS idx_categories_system_id ON categories(system_id)"
    static let idxCoreOptionsCoreId = "CREATE INDEX IF NOT EXISTS idx_core_options_core_id ON core_options(core_id)"
}
