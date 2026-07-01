import Foundation

@MainActor enum SettingsResetter {

    static func resetHotkeys() {
        HotkeyConfigManager.shared.resetToDefaults()
    }

    static func resetSaveDirectories() {
        AppSettings.remove(AppSettings.SaveDirectoryKey.userSaveDirectory)
        AppSettings.remove(AppSettings.SaveDirectoryKey.userSystemDirectory)
    }

    static func resetSelectedTab() {
        AppSettings.remove("settings_selectedTab")
    }

    static func resetAll() {
        AppSettings.remove(AppSettings.SaveDirectoryKey.userSaveDirectory)
        AppSettings.remove(AppSettings.SaveDirectoryKey.userSystemDirectory)
        AppSettings.remove("settings_selectedTab")
        HotkeyEMuResetDeep()
        AppSettings.flush()
    }

    private static func HotkeyEMuResetDeep() {
        HotkeyConfigManager.shared.resetToDefaults()
    }
}
