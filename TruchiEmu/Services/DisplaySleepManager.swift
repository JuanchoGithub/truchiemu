import Foundation

// Prevents macOS from putting the display or the system to sleep while a game
// is running. Gameplay driven only by a controller produces no keyboard/mouse
// activity, so the idle timer would otherwise turn the screens off mid-game.
@MainActor
final class DisplaySleepManager: ObservableObject {
    static let shared = DisplaySleepManager()

    private var activityToken: NSObjectProtocol?

    private init() {}

    func start() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
            reason: "TruchiEmu game playing"
        )
    }

    func stop() {
        guard let token = activityToken else { return }
        ProcessInfo.processInfo.endActivity(token)
        activityToken = nil
    }
}