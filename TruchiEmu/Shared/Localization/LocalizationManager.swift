// LocalizationManager.swift – JSON based UI translation

import Foundation
import SwiftUI

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var currentLanguage: String = "en"
    private(set) var availableLanguages: [String] = [] // Just the codes, for UI pickers
    private var translationCache: [String: [String: String]] = [:] // Only loaded languages stay here
    private let fallbackLanguage = "en"

    private var translations: [String: [String: String]] { // Computed for compatibility
        translationCache
    }

    private init() {
        availableLanguages = discoverAvailableLanguages()
        loadLanguage(fallbackLanguage) // Always load fallback

        let savedOrDevice = resolveSavedOrDeviceLanguage()
        currentLanguage = savedOrDevice
        loadLanguage(currentLanguage)

        // Observe language change notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange), name: .languageChanged, object: nil)
    }

    // MARK: - Private Helpers

    private func resolveSavedOrDeviceLanguage() -> String {
        // First check if user has a saved language preference
        if let savedLang = AppSettings.get("systemLanguage", type: String.self),
           availableLanguages.contains(savedLang) {
            return savedLang
        }
        // Fallback to device preferred language (first two letters)
        if let deviceLang = Locale.preferredLanguages.first?.prefix(2).lowercased(),
           availableLanguages.contains(String(deviceLang)) {
            return String(deviceLang)
        }
        return fallbackLanguage
    }

    private func discoverAvailableLanguages() -> [String] {
        let bundle = Bundle.main
        let fileManager = FileManager.default
        let languageCodes = Set(["en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh", "ar", "hi"])

        guard let bundlePath = bundle.resourcePath,
              let files = try? fileManager.contentsOfDirectory(atPath: bundlePath) else {
            return [fallbackLanguage]
        }

        var available: [String] = []
        for fileName in files where fileName.hasSuffix(".json") {
            let lang = fileName.replacingOccurrences(of: ".json", with: "")
            if languageCodes.contains(lang) {
                available.append(lang)
            }
        }
        available.sort()
        #if LOG_DEBUG
        LoggerService.debug(category: "Localization", "Available languages: \(available)")
        #endif
        return available.isEmpty ? [fallbackLanguage] : available
    }

    @discardableResult
    private func loadLanguage(_ lang: String) -> Bool {
        guard !translationCache.keys.contains(lang) else { return true }
        guard let bundlePath = Bundle.main.resourcePath else { return false }
        let fileURL = URL(fileURLWithPath: bundlePath).appendingPathComponent("\(lang).json")

        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            LoggerService.error(category: "Localization", "Failed to load translation: \(lang).json")
            return false
        }
        translationCache[lang] = dict
        if lang == currentLanguage || lang == fallbackLanguage {
            #if LOG_DEBUG
            LoggerService.debug(category: "Localization", "Loaded translation: \(lang) with \(dict.count) keys")
            #endif
        }
        return true
    }

    @objc private func handleLanguageChange() {
        if let lang = AppSettings.get("systemLanguage", type: String.self), availableLanguages.contains(lang) {
            currentLanguage = lang
            loadLanguage(lang)
        } else {
            currentLanguage = fallbackLanguage
        }
    }

    // MARK: - Public API

    func setLanguage(_ lang: String) {
        guard availableLanguages.contains(lang) else { return }
        loadLanguage(lang)
        currentLanguage = lang
        AppSettings.set("systemLanguage", value: lang)
        NotificationCenter.default.post(name: .languageChanged, object: nil)
    }

    func localizedString(forKey key: String) -> String {
        let currentLoaded = translationCache[currentLanguage]
        let fallbackLoaded = translationCache[fallbackLanguage]
        return currentLoaded?[key] ?? fallbackLoaded?[key] ?? key
    }

    func localized(_ key: String) -> String {
        localizedString(forKey: key)
    }

    func localized(_ key: String, _ args: CVarArg...) -> String {
        let formatString = localizedString(forKey: key)
        return String(format: formatString, arguments: args)
    }
}

extension Notification.Name {

}

// SwiftUI Text convenience – use Text("settings.title") directly
extension Text {
    init(_ localizationKey: String) {
        // Use the verbatim initializer to avoid recursively calling this extension
        self.init(verbatim: LocalizationManager.shared.localizedString(forKey: localizationKey))
    }
}
