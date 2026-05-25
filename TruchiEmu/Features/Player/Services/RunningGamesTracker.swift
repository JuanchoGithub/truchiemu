import Foundation
import AppKit
import UserNotifications

// Tracks which games are currently running to prevent launching multiple games
// (since there is only one CoreHost), and provides a global signal to pause
// background activities during gameplay.
@MainActor
class RunningGamesTracker: ObservableObject {
    static let shared = RunningGamesTracker()

    @Published private(set) var runningGames: [String: String] = [:]

    var isGameRunning: Bool {
        !runningGames.isEmpty
    }

    var currentRunningGameName: String? {
        runningGames.values.first
    }

    private init() {}

    func isRunning(romPath: String) -> Bool {
        return runningGames[romPath] != nil
    }

    func registerRunning(romPath: String, displayName: String) {
        runningGames[romPath] = displayName
    }

    func unregisterRunning(romPath: String) {
        runningGames.removeValue(forKey: romPath)
    }

    func resetAll() {
        runningGames.removeAll()
    }

    func notifyDuplicateLaunch(romName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Game Already Running"
        content.body = "\"\(romName)\" is already running"
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
