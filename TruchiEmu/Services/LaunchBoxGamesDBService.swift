import Foundation
import AppKit
import SwiftData

// Maps internal system IDs to LaunchBox GamesDB display platform names.
enum LaunchBoxPlatformMapper {
    static func launchBoxPlatformName(for systemID: String) -> String? {
        guard let system = SystemDatabase.system(forID: systemID) else { return nil }
        let systemName = system.name
        let manufacturer = system.manufacturer
        if !systemName.lowercased().contains(manufacturer.lowercased()) {
            return "\(manufacturer) \(systemName)"
        }
        return systemName
    }
}

@MainActor
class LaunchBoxGamesDBService: ObservableObject {
    static let shared = LaunchBoxGamesDBService()

    private let keyUseLaunchBox = "launchbox_use_for_boxart"
    private let keyDownloadBoxartAfterScan = "launchbox_download_after_scan"

    @Published var isSyncing: Bool = false
    @Published var syncProgress: Double = 0
    @Published var syncStatus: String = ""

    var isEnabled: Bool {
        get { AppSettings.getBool(keyUseLaunchBox, defaultValue: false) }
        set { AppSettings.setBool(keyUseLaunchBox, value: newValue) }
    }

    var downloadAfterScan: Bool {
        get { AppSettings.getBool(keyDownloadBoxartAfterScan, defaultValue: true) }
        set { AppSettings.setBool(keyDownloadBoxartAfterScan, value: newValue) }
    }

    private init() {}

    func setEnabled(_ enabled: Bool) {
        AppSettings.setBool(keyUseLaunchBox, value: enabled)
    }

    var lastSyncDate: Date? {
        let interval = AppSettings.getDouble("launchbox_last_sync", defaultValue: 0)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    func recordSyncDate() {
        AppSettings.setDouble("launchbox_last_sync", value: Date().timeIntervalSince1970)
    }

    // Delegate to LaunchBoxMetadataService

    func fetchAndApplyMetadata(for rom: ROM, library: ROMLibrary) async -> Bool {
        await LaunchBoxMetadataService.shared.fetchAndApplyMetadata(for: rom, library: library)
    }
}
