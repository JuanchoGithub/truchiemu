import Foundation

/// AppSettings provides a persistent key-value store backed by SQLite.
/// This replaces UserDefaults for application data, ensuring durability especially during CLI launches.
enum AppSettings {
    private static let db = DatabaseManager.shared
    // All logging goes through LoggerService (file + console)

    // MARK: - One-time migration from UserDefaults to SQLite

    static func migrateAllUserDefaults() {
        LoggerService.info(category: "AppSettings", "Starting UserDefaults -> SQLite migration for app settings")

        // Simple key-value settings (primitives)
        let simpleKeys: [String] = [
            "has_completed_onboarding",
            "has_completed_full_setup",
            "logging_enabled",
            "display_default_shader_preset",
            "showBiosFiles",
            "systemLanguage",
            "coreLogLevel",
            "autoLoadCheats",
            "applyCheatsOnLaunch",
            "showCheatNotifications",
            "log_level",
            "selected_save_slot",
            "dosbox_pure_cycles",
            "dosbox_pure_mouse",
            "dosbox_pure_start_menu",
            "auto_load_on_start",
            "auto_save_on_exit",
            "achievements_enabled",
            "cheats_enabled",
            "compress_save_states",
            "thumbnail_use_libretro",
            "thumbnail_use_head_check",
            "thumbnail_fallback_filename",
            "shaderWindowPosition",
            // Core Manager
            "cores_initial_fetch_done_v1",
            // Bezel
            "bezelStorageMode",
            "bezelInitialSetupComplete",
            "bezelLastPromptedLibraryCount",
            // Log / BoxArt / LaunchBox / Display
            "thumbnail_server_url",
            "thumbnail_priority_type",
            "thumbnail_use_crc_matching",
            "launchbox_download_after_scan",
            "launchbox_last_sync",
            "gridColumns",
            "lastLoadedCoreID",
            "custom_log_folder_url",
        ]

        for key in simpleKeys {
            if UserDefaults.standard.object(forKey: key) != nil {
                migrateSimpleSetting(key)
            }
        }

        // Pattern-based settings (preferredCore, boxType)
        migratePatternSettings()

        // Complex data types (stored as base64 in settings table)
        migrateComplexSettings()

        LoggerService.info(category: "AppSettings", "UserDefaults -> SQLite migration complete for app settings")
    }

    private static func migrateComplexSettings() {
        // Migrate complex JSON/Data keys that were stored as opaque data
        // Base64 encoding for Data types
        let dataKeys = [
            "BezelDownloadLog",      // [BezelDownloadLogEntry]
            "game_categories_v1",     // [GameCategory]
            "controller_mappings_v2", // [ControllerMapping]
            "keyboard_mapping_v1",    // [String: RetroButton]
            "cheatLastDownloadDate",  // Date
            "screenscraper_credentials", // ScreenScraperCredentials
        ]
        
        for key in dataKeys {
            guard UserDefaults.standard.object(forKey: key) != nil else { continue }
            if db.getSetting(key) != nil { continue }
            migrateComplexSetting(key)
        }
    }

    // MARK: - Migration Helpers

    private static func migrateSimpleSetting(_ key: String) {
        // Only migrate if SQLite doesn't already have it
        if db.getSetting(key) != nil { return }

        if let str = UserDefaults.standard.string(forKey: key) {
            db.setSetting(key, value: str)
            LoggerService.info(category: "AppSettings", "Migrated string: \(key) = \(str)")
        } else if UserDefaults.standard.object(forKey: key) != nil,
                  let int = (UserDefaults.standard.object(forKey: key) as? NSNumber)?.intValue {
            // Only migrate non-zero integers (UserDefaults defaults to 0 for missing keys)
            db.setSetting(key, value: String(int))
            LoggerService.info(category: "AppSettings", "Migrated int: \(key) = \(int)")
        } else if UserDefaults.standard.object(forKey: key) != nil,
                  let bool = UserDefaults.standard.object(forKey: key) as? Bool {
            db.setBoolSetting(key, value: bool)
            LoggerService.info(category: "AppSettings", "Migrated bool: \(key) = \(bool)")
        } else if let date = UserDefaults.standard.object(forKey: key) as? Date {
            let str = String(date.timeIntervalSince1970)
            db.setSetting(key, value: str)
            LoggerService.info(category: "AppSettings", "Migrated date: \(key)")
        } else if let data = UserDefaults.standard.data(forKey: key) {
            let b64 = data.base64EncodedString()
            db.setSetting(key, value: "_b64:\(b64)")
            LoggerService.info(category: "AppSettings", "Migrated data: \(key)")
        } else if let object = UserDefaults.standard.object(forKey: key) {
            // Try to encode as JSON if it's a property list type
            if let data = try? JSONSerialization.data(withJSONObject: object) {
                let b64 = data.base64EncodedString()
                db.setSetting(key, value: "_b64:\(b64)")
                LoggerService.info(category: "AppSettings", "Migrated plist object: \(key)")
            } else {
                LoggerService.warning(category: "AppSettings", "Cannot migrate key: \(key), type: \(type(of: object))")
                return
            }
        } else {
            return
        }

        // Remove after migration
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func migrateComplexSetting(_ key: String) {
        if db.getSetting(key) != nil { return }
        
        if let data = UserDefaults.standard.data(forKey: key) {
            let b64 = data.base64EncodedString()
            db.setSetting(key, value: "_b64:\(b64)")
            UserDefaults.standard.removeObject(forKey: key)
            LoggerService.info(category: "AppSettings", "Migrated complex data: \(key)")
        } else if let date = UserDefaults.standard.object(forKey: key) as? Date {
            let str = String(date.timeIntervalSince1970)
            db.setSetting(key, value: str)
            UserDefaults.standard.removeObject(forKey: key)
            LoggerService.info(category: "AppSettings", "Migrated date: \(key)")
        } else if let str = UserDefaults.standard.string(forKey: key) {
            db.setSetting(key, value: str)
            UserDefaults.standard.removeObject(forKey: key)
            LoggerService.info(category: "AppSettings", "Migrated string: \(key)")
        } else if let int = (UserDefaults.standard.object(forKey: key) as? NSNumber)?.intValue {
            db.setSetting(key, value: String(int))
            UserDefaults.standard.removeObject(forKey: key)
            LoggerService.info(category: "AppSettings", "Migrated int: \(key) = \(int)")
        } else if let bool = UserDefaults.standard.object(forKey: key) as? Bool {
            db.setBoolSetting(key, value: bool)
            UserDefaults.standard.removeObject(forKey: key)
            LoggerService.info(category: "AppSettings", "Migrated bool: \(key) = \(bool)")
        }
    }

    private static func migratePatternSettings() {
        // Migrate preferredCore_{systemID} settings
        let allUserDefaults = UserDefaults.standard.dictionaryRepresentation()
        for (key, _) in allUserDefaults {
            if key.hasPrefix("preferredCore_") {
                if db.getSetting(key) == nil {
                    if let value = UserDefaults.standard.string(forKey: key) {
                        db.setSetting(key, value: value)
                    }
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            if key.hasPrefix("boxType_") {
                if db.getSetting(key) == nil {
                    if let value = UserDefaults.standard.string(forKey: key) {
                        db.setSetting(key, value: value)
                    }
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
    }

    // MARK: - Setting Accessors

    static func get(_ key: String) -> String? {
        db.getSetting(key)
    }

    static func set(_ key: String, value: String) {
        db.setSetting(key, value: value)
    }

    static func getBool(_ key: String, defaultValue: Bool) -> Bool {
        db.getBoolSetting(key, defaultValue: defaultValue)
    }

    static func setBool(_ key: String, value: Bool) {
        db.setBoolSetting(key, value: value)
    }

    static func getInt(_ key: String, defaultValue: Int = 0) -> Int {
        db.getSetting(key).flatMap { Int($0) } ?? defaultValue
    }

    static func setInt(_ key: String, value: Int) {
        db.setSetting(key, value: String(value))
    }

    static func getDouble(_ key: String, defaultValue: Double = 0) -> Double {
        db.getSetting(key).flatMap { Double($0) } ?? defaultValue
    }

    static func setDouble(_ key: String, value: Double) {
        db.setSetting(key, value: String(value))
    }

    /// Get stored data that was saved as base64-prefixed string.
    static func getData(_ key: String) -> Data? {
        guard let value = db.getSetting(key) else { return nil }
        if value.hasPrefix("_b64:") {
            let b64 = String(value.dropFirst(5))
            return Data(base64Encoded: b64)
        }
        return nil
    }

    /// Store arbitrary data as base64-prefixed string.
    static func setData(_ key: String, value: Data) {
        db.setSetting(key, value: "_b64:\(value.base64EncodedString())")
    }

    /// Get a Date stored as a Unix timestamp string.
    static func getDate(_ key: String) -> Date? {
        guard let value = db.getSetting(key) else { return nil }
        if let interval = Double(value) {
            return Date(timeIntervalSince1970: interval)
        }
        return nil
    }

    /// Store a Date as a Unix timestamp string.
    static func setDate(_ key: String, value: Date) {
        db.setSetting(key, value: String(value.timeIntervalSince1970))
    }

    /// Remove a key from the settings database.
    static func removeObject(forKey key: String) {
        db.removeSetting(key)
    }
}
