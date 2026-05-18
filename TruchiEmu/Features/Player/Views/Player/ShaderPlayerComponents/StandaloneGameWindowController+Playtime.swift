import Cocoa
import SwiftUI

// MARK: - Playtime Tracking

extension StandaloneGameWindowController {

    // Start tracking playtime with a timer that accumulates seconds only when the game is running and not paused
    func startPlaytimeTracking() {
        playtimeTimer?.invalidate()
        playtimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, let runner = self.runner else {
                timer.invalidate()
                return
            }
            // Only accumulate time when the game is running and not paused.
            // Timer.scheduledTimer fires on the main thread, so isPaused can be read directly
            // without DispatchQueue.main.sync (which would deadlock here).
            if runner.isRunning {
                Task { @MainActor in
                    if !runner.isPaused {
                        self.accumulatedPlaytime += 1.0
                    }
                }
            }
        }
    }

    // Stop playtime tracking
    func stopPlaytimeTracking() {
        playtimeTimer?.invalidate()
        playtimeTimer = nil
    }
}
