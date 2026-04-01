import Foundation
import AppKit
import UserNotifications

/// Tracks which games are currently running to prevent launching the same ROM twice.
@MainActor
class RunningGamesTracker: ObservableObject {
    static let shared = RunningGamesTracker()
    
    /// Set of ROM paths that are currently running
    @Published private(set) var runningROMPaths: Set<String> = []
    
    private init() {}
    
    /// Check if a ROM is currently running
    func isRunning(romPath: String) -> Bool {
        return runningROMPaths.contains(romPath)
    }
    
    /// Register a ROM as running
    func registerRunning(romPath: String) {
        runningROMPaths.insert(romPath)
    }
    
    /// Unregister a ROM (when game is closed)
    func unregisterRunning(romPath: String) {
        runningROMPaths.remove(romPath)
    }
    
    /// Show a notification when attempting to launch an already-running game
    func notifyDuplicateLaunch(romName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Game Already Running"
        content.body = "\"\(romName)\" is already running"
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
