import Foundation

// Simple UserDefaults wrapper for app settings.
enum AppSettings {
    static func getBool(_ key: String, defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setBool(_ key: String, value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func getString(_ key: String, defaultValue: String? = nil) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func setString(_ key: String, value: String?) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func getInt(_ key: String, defaultValue: Int = 0) -> Int {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.integer(forKey: key)
    }

    static func setInt(_ key: String, value: Int) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func getDouble(_ key: String, defaultValue: Double = 0.0) -> Double {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.double(forKey: key)
    }

    static func setDouble(_ key: String, value: Double) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func getData(_ key: String) -> Data? {
        UserDefaults.standard.data(forKey: key)
    }

    static func setData(_ key: String, value: Data) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func removeObject(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func get<T: Codable>(_ key: String, type: T.Type) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func set<T: Codable>(_ key: String, value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func setDate(_ key: String, value: Date) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func getDate(_ key: String) -> Date? {
        UserDefaults.standard.object(forKey: key) as? Date
    }
}
