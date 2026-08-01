import Cocoa
import SwiftUI
import Combine

// MARK: - Playtime Tracking
//
// Replaces the previous 1-second Timer.scheduledTimer. That timer paced the
// main RunLoop at 1 Hz and triggered a Task { @MainActor in ... } hop on every
// tick, which competed with MetalCoordinator.draw(in:) for main-thread time
// and produced a visible ~1-second frame stutter during gameplay.
//
// The new scheme is event-driven:
//   - Start a wall-clock segment when play begins (startPlaytimeTracking).
//   - On pause/resume transitions observed via runner.$isPaused, fold the
//     elapsed interval since playStart into accumulatedPlaytime and reset
//     playStart (nil when paused, Date() when resumed).
//   - On window close (stopPlaytimeTracking), fold the final segment.
// accumulatedPlaytime is read once on close by recordPlaySession; downstream
// callers see no behavioral change other than sub-second accuracy improvement.

extension StandaloneGameWindowController {

    // Start tracking playtime. Sets the active play segment to now and
    // subscribes to runner.isPaused so pause/resume folds intervals.
    func startPlaytimeTracking() {
        guard let runner = runner else { return }
        // Reset accumulator and start the first playing segment.
        accumulatedPlaytime = 0
        playStart = Date()
        // Observe isPaused transitions on the main queue. Each transition
        // folds the elapsed interval since playStart into accumulatedPlaytime.
        pauseCancellable = runner.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPaused in
                guard let self = self else { return }
                self.foldPlaytimeSegment(pausing: isPaused)
            }
    }

    // Stop tracking playtime. Folds the final playing segment (if any) and
    // tears down the Combine subscription. accumulatedPlaytime is left
    // populated for the close handler's recordPlaySession call.
    func stopPlaytimeTracking() {
        // Fold the in-flight segment if we were actively playing when stop
        // was called (e.g. window close while unpaused).
        foldPlaytimeSegment(pausing: true)
        pauseCancellable?.cancel()
        pauseCancellable = nil
    }

    // Fold the elapsed wall-clock interval since playStart into
    // accumulatedPlaytime. If pausing == true, clear playStart (the segment
    // ends). If pausing == false, restart playStart at now (the next segment
    // begins). Calling this with pausing == true when already paused is a
    // safe no-op (playStart is already nil).
    private func foldPlaytimeSegment(pausing: Bool) {
        if let start = playStart {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 0 {
                accumulatedPlaytime += elapsed
            }
            playStart = nil
        }
        if !pausing {
            // Resumed playing: start a fresh segment.
            playStart = Date()
        }
    }
}
