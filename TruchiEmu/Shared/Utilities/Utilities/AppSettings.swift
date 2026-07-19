import Foundation
import SwiftData

// Settings stored in SwiftData - will be deleted when app is uninstalled.
@MainActor
final class AppSettingsCache {
    static let shared = AppSettingsCache()
    
    private var cache: [String: Data] = [:]
    private var isLoaded = false
    
    private init() {
        // Don't load here - we'll load on first access
    }
    
    private func ensureLoaded() {
        guard !isLoaded else { return }
        loadFromSwiftData()
        isLoaded = true
    }
    
    private func loadFromSwiftData() {
        let container = SwiftDataContainer.shared
        let context = container.mainContext
        let descriptor = FetchDescriptor<SettingsEntry>()
        
        guard let entries = try? context.fetch(descriptor) else { return }
        
        for entry in entries {
            cache[entry.key] = entry.dataValue
        }
    }
    
    func getBool(_ key: String, defaultValue: Bool) -> Bool {
        ensureLoaded()
        guard let data = cache[key],
              let value = try? JSONDecoder().decode(Bool.self, from: data) else {
            return defaultValue
        }
        return value
    }
    
    func setBool(_ key: String, value: Bool) {
        ensureLoaded()
        let data = try! JSONEncoder().encode(value)
        cache[key] = data
        saveAsync(key: key, value: data)
    }
    
    func getString(_ key: String, defaultValue: String?) -> String? {
        ensureLoaded()
        guard let data = cache[key],
              let value = try? JSONDecoder().decode(String.self, from: data) else {
            return defaultValue
        }
        return value
    }
    
    func setString(_ key: String, value: String?) {
        let data = try! JSONEncoder().encode(value)
        cache[key] = data
        saveAsync(key: key, value: data)
    }
    
    func getInt(_ key: String, defaultValue: Int) -> Int {
        ensureLoaded()
        guard let data = cache[key],
              let value = try? JSONDecoder().decode(Int.self, from: data) else {
            return defaultValue
        }
        return value
    }
    
    func setInt(_ key: String, value: Int) {
        ensureLoaded()
        let data = try! JSONEncoder().encode(value)
        cache[key] = data
        saveAsync(key: key, value: data)
    }
    
    func getDouble(_ key: String, defaultValue: Double) -> Double {
        ensureLoaded()
        guard let data = cache[key],
              let value = try? JSONDecoder().decode(Double.self, from: data) else {
            return defaultValue
        }
        return value
    }
    
    func setDouble(_ key: String, value: Double) {
        ensureLoaded()
        let data = try! JSONEncoder().encode(value)
        cache[key] = data
        saveAsync(key: key, value: data)
    }
    
    func getData(_ key: String) -> Data? {
        ensureLoaded()
        return cache[key]
    }
    
    func setData(_ key: String, value: Data) {
        cache[key] = value
        saveAsync(key: key, value: value)
    }
    
    func remove(_ key: String) {
        cache.removeValue(forKey: key)
        deleteFromSwiftData(key: key)
    }
    
    func getDate(_ key: String) -> Date? {
        ensureLoaded()
        guard let data = cache[key],
              let value = try? JSONDecoder().decode(Date.self, from: data) else {
            return nil
        }
        return value
    }
    
    func setDate(_ key: String, value: Date) {
        ensureLoaded()
        let data = try! JSONEncoder().encode(value)
        cache[key] = data
        saveAsync(key: key, value: data)
    }
    
    func getCodable<T: Codable>(_ key: String, type: T.Type) -> T? {
        ensureLoaded()
        guard let data = cache[key] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    
    func setCodable<T: Codable>(_ key: String, value: T) {
        ensureLoaded()
        let data = try! JSONEncoder().encode(value)
        cache[key] = data
        saveAsync(key: key, value: data)
    }
    
    private func saveAsync(key: String, value: Data) {
        guard isLoaded else { return }
        Task {
            saveToSwiftData(key: key, value: value)
        }
    }

    func flush() {
        guard isLoaded else { return }
        for (key, value) in cache {
            saveToSwiftData(key: key, value: value)
        }
    }
    
    private func saveToSwiftData(key: String, value: Data) {
        let context = SwiftDataContainer.shared.mainContext
        let predicate = #Predicate<SettingsEntry> { $0.key == key }
        let descriptor = FetchDescriptor<SettingsEntry>(predicate: predicate)
        
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        }
        
        let entry = SettingsEntry(key: key, value: value)
        context.insert(entry)
        try? context.save()
    }
    
    private func deleteFromSwiftData(key: String) {
        guard isLoaded else { return }
        Task {
            let context = SwiftDataContainer.shared.mainContext
            let predicate = #Predicate<SettingsEntry> { $0.key == key }
            let descriptor = FetchDescriptor<SettingsEntry>(predicate: predicate)
            
            if let entry = try? context.fetch(descriptor).first {
                context.delete(entry)
                try? context.save()
            }
        }
    }
}

// MARK: - AppSettings Enum

enum AppSettings {
    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func isVersionMatch(_ key: String) -> Bool {
        getString(key) == appVersion
    }

    static func markVersionCompleted(_ key: String) {
        setString(key, value: appVersion)
    }

    static func getBool(_ key: String, defaultValue: Bool) -> Bool {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.getBool(key, defaultValue: defaultValue)
        }
    }
    
    static func setBool(_ key: String, value: Bool) {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.setBool(key, value: value)
        }
    }
    
    static func getString(_ key: String, defaultValue: String? = nil) -> String? {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.getString(key, defaultValue: defaultValue)
        }
    }
    
    static func setString(_ key: String, value: String?) {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.setString(key, value: value)
        }
    }
    
    static func getInt(_ key: String, defaultValue: Int = 0) -> Int {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.getInt(key, defaultValue: defaultValue)
        }
    }
    
    static func setInt(_ key: String, value: Int) {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.setInt(key, value: value)
        }
    }
    
    static func getDouble(_ key: String, defaultValue: Double = 0.0) -> Double {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.getDouble(key, defaultValue: defaultValue)
        }
    }
    
    static func setDouble(_ key: String, value: Double) {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.setDouble(key, value: value)
        }
    }
    
    static func getData(_ key: String) -> Data? {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.getData(key)
        }
    }
    
    static func setData(_ key: String, value: Data) {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.setData(key, value: value)
        }
    }
    
    static func removeObject(_ key: String) {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.remove(key)
        }
    }
    
    static func remove(_ key: String) {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.remove(key)
        }
    }
    
    static func get<T: Codable>(_ key: String, type: T.Type) -> T? {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.getCodable(key, type: type)
        }
    }
    
    static func set<T: Codable>(_ key: String, value: T) {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.setCodable(key, value: value)
        }
    }
    
    static func setDate(_ key: String, value: Date) {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.setDate(key, value: value)
        }
    }
    
    static func getDate(_ key: String) -> Date? {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.getDate(key)
        }
    }
    
    // MARK: - Save Directory Settings
    
    enum SaveDirectoryKey {
        static let userSaveDirectory = "customSaveDirectoryPath"
        static let userSystemDirectory = "customSystemDirectoryPath"
        static let lastMigrationDate = "saveDirectoryLastMigration"
    }
    
    static func getCustomSaveDirectory() -> URL? {
        guard let path = getString(SaveDirectoryKey.userSaveDirectory) else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    static func setCustomSaveDirectory(_ url: URL?) {
        setString(SaveDirectoryKey.userSaveDirectory, value: url?.path)
        NotificationCenter.default.post(name: .saveDirectorySettingChanged, object: nil)
    }
    
    static func getCustomSystemDirectory() -> URL? {
        guard let path = getString(SaveDirectoryKey.userSystemDirectory) else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    static func setCustomSystemDirectory(_ url: URL?) {
        setString(SaveDirectoryKey.userSystemDirectory, value: url?.path)
        NotificationCenter.default.post(name: .saveDirectorySettingChanged, object: nil)
    }

    static func flush() {
        MainActor.assumeIsolated {
            AppSettingsCache.shared.flush()
        }
    }

    // MARK: - Genesis Controller Type

    enum GenesisControllerType: String, Codable {
        case threeButton = "3button"
        case sixButton = "6button"

        var isSixButton: Bool { self == .sixButton }
    }

    enum GenesisControllerKey {
        static let controllerType = "genesisControllerType"
    }

    static func getGenesisControllerType() -> GenesisControllerType {
        guard let data = getData(GenesisControllerKey.controllerType),
              let type = try? JSONDecoder().decode(GenesisControllerType.self, from: data) else {
            return .threeButton
        }
        return type
    }

    static func setGenesisControllerType(_ type: GenesisControllerType) {
        guard let data = try? JSONEncoder().encode(type) else { return }
        setData(GenesisControllerKey.controllerType, value: data)
    }

    // MARK: - Wii Controller Type

    enum WiiControllerType: String, Codable {
        case auto = "auto"
        case wiimote = "wiimote"
        case wiimoteSideways = "wiimoteSideways"
        case wiimoteClassic = "wiimoteClassic"

        /// libretro device subtype for Dolphin (RETRO_DEVICE_JOYPAD | subtype << 8).
        /// Dolphin has no "Wii U Pro" device; the standard gamepad mapping is
        /// Wiimote + Classic Controller (1025). `.auto` resolves at launch.
        var deviceValue: UInt32? {
            switch self {
            case .auto: return nil
            case .wiimote: return 1
            case .wiimoteSideways: return 513
            case .wiimoteClassic: return 1025
            }
        }
    }

    enum WiiControllerKey {
        static let controllerType = "wiiControllerType"
    }

    static func getWiiControllerType() -> WiiControllerType {
        guard let data = getData(WiiControllerKey.controllerType),
              let type = try? JSONDecoder().decode(WiiControllerType.self, from: data) else {
            return .auto
        }
        return type
    }

    static func setWiiControllerType(_ type: WiiControllerType) {
        guard let data = try? JSONEncoder().encode(type) else { return }
        setData(WiiControllerKey.controllerType, value: data)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let saveDirectorySettingChanged = Notification.Name("SaveDirectorySettingChanged")
}
