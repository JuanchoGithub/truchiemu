import Foundation

struct GameToolbarPresentation {
    let icon: String
    let label: String
    let badge: String?
    let disabled: Bool
    let active: Bool
}

@MainActor
enum GameToolbarPresentationResolver {
    static func resolve(
        item: GameToolbarItem,
        runner: EmulatorRunner?,
        windowController: StandaloneGameWindowController
    ) -> GameToolbarPresentation {
        let loc = LocalizationManager.shared
        let recording = StreamRecordingService.shared
        var icon = item.icon
        var label = loc.localized(item.labelKey)
        var badge: String?

        switch item.id {
        case .stop:
            if windowController.isGamepadToolbarMode && windowController.isStopConfirmArmed {
                icon = "checkmark.circle.fill"
                label = loc.localized("toolbar.confirmStop")
            }
        case .pauseResume:
            let isPaused = runner?.isPaused == true
            icon = isPaused ? "play.fill" : "pause.fill"
            label = isPaused ? loc.localized("toolbar.resume") : loc.localized("toolbar.pause")
        case .save:
            if !windowController.saveStatesDisabled {
                let slot = runner?.currentSlot ?? 0
                badge = slot == -1 ? "A" : "\(max(0, slot))"
            }
        case .fastForward:
            let speed = runner?.speedMultiplier ?? 1
            label = formatSpeed(nextFastForwardSpeed(after: speed))
        case .slowMotion:
            let speed = runner?.speedMultiplier ?? 1
            label = formatSpeed(nextSlowMotionSpeed(after: speed))
        case .record:
            if case .connecting = recording.streamStatus {
                icon = "antenna.radiowaves.left.and.right"
                label = loc.localized("toolbar.connecting")
            } else if recording.streamError != nil {
                icon = "exclamationmark.triangle.fill"
                label = loc.localized("toolbar.streamError")
            } else if recording.isUserRecording {
                icon = "stop.circle.fill"
                label = loc.localized("toolbar.stopRecording")
            } else {
                icon = "record.circle"
                label = loc.localized("toolbar.record")
            }
        case .fullscreen:
            let fullscreen = windowController.isFullscreen
            icon = fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            label = fullscreen ? loc.localized("toolbar.exitFullscreen") : loc.localized("toolbar.fullscreen")
        default:
            break
        }

        return GameToolbarPresentation(
            icon: icon,
            label: label,
            badge: badge,
            disabled: !windowController.isToolbarItemEnabled(item.id),
            active: windowController.isToolbarItemActive(item.id)
        )
    }

    private static func nextFastForwardSpeed(after speed: Float) -> Float {
        let speeds: [Float] = [2.0, 4.0, 8.0]
        let index = speeds.firstIndex { $0 == speed } ?? -1
        let next = (index + 1) % (speeds.count + 1)
        return next < speeds.count ? speeds[next] : 1.0
    }

    private static func nextSlowMotionSpeed(after speed: Float) -> Float {
        let speeds: [Float] = [0.5, 0.25]
        let index = speeds.firstIndex { $0 == speed } ?? -1
        let next = (index + 1) % (speeds.count + 1)
        return next < speeds.count ? speeds[next] : 1.0
    }

    private static func formatSpeed(_ speed: Float) -> String {
        String(format: "%gx", Double(speed))
    }
}
