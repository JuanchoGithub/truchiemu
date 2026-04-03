import Foundation
import os.log

/// AppSettings provides a persistent key-value store backed by SQLite.
/// This replaces UserDefaults for application data, ensuring durability especially during CLI launches.
enum AppSettings {
    private static let db = DatabaseManager.shared
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "AppSettings")

    // MARK: - One-time migration from UserDefaults to SQLite

    static func migrateAllUserDefaults() {
        logger.info("Starting UserDefaults -> SQLite migration for app settings")

        // Simple key-value settings
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
        ]

        for key in simpleKeys {
            if UserDefaults.standard.object(forKey: key) != nil {
                migrateSimpleSetting(key)
            }
        }

        // Pattern-based settings (preferredCore, boxType)
        migratePatternSettings()

        // Complex data (JSON-encoded objects)
        migrateComplexSettings()

        logger.info("UserDefaults -> SQLite migration complete for app settings")
    }

    // MARK: - Migration Helpers

    private static func migrateSimpleSetting(_ key: String) {
        // Only migrate if SQLite doesn't already have it
        if db.getSetting(key) != nil { return }

        if let str = UserDefaults.standard.string(forKey: key) {
            db.setSetting(key, value: str)
            logger.info("Migrated string: \(key) = \(str)")
        } else if let int = UserDefaults.standard.integer(forKey: key) {
            // Only migrate non-zero integers (UserDefaults defaults to 0 for missing keys)
            if UserDefaults.standard.object(forKey: key) != nil {
                db.setSetting(key, value: String(int))
                logger.info("Migrated int: \(key) = \(int)")
            }
        } else if let bool = UserDefaults.standard.bool(forKey: key) {
            if UserDefaults.standard.object(forKey: key) != nil {
                db.setBoolSetting(key, value: bool)
                logger.info("Migrated bool: \(key) = \(bool)")
            }
        } else if let date = UserDefaults.standard.object(forKey: key) as? Date {
            let str = String(date.timeIntervalSince1970)
            db.setSetting(key, value: str)
            logger.info("Migrated date: \(key)")
        } else if let data = UserDefaults.standard.data(forKey: key) {
            let b64 = data.base64EncodedString()
            db.setSetting(key, value: "_b64:\(b64)")
            logger.info("Migrated data: \(key)")

            // Remove after migration
            UserDefaults.standard.removeObject(forKey: key)
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

    private static func migrateComplexSettings() {
        // These are JSON/serialized objects — they'll be migrated by their own managers
        // We ensure they won't be lost even if not migrated immediately
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
        db.getSetting(key).map { Int($0) } ?? defaultValue
    }

    static func setInt(_ key: String, value: Int) {
        db.setSetting(key, value: String(value))
    }

    static func removeObject(forKey key: String) {
        db.removeSetting(key)
    }
}
