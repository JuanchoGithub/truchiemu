import Foundation
import AppKit
import UserNotifications

/// Tracks which games are currently running to prevent launching the same ROM twice,
/// and provides a global signal to pause background activities during gameplay.
@MainActor
class RunningGamesTracker: ObservableObject {
    static let shared = RunningGamesTracker()
    
    /// Set of ROM paths that are currently running
    @Published private(set) var runningROMPaths: Set<String> = []
    
    /// Whether any game is currently running. Background activities like
    /// ROM scanning and metadata downloads should pause while this is true.
    var isGameRunning: Bool {
        !runningROMPaths.isEmpty
    }
    
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
    
    /// Clear all running games (useful for CLI launches)
    func resetAll() {
        runningROMPaths.removeAll()
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
