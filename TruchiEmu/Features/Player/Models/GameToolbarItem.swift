import Foundation

enum GameToolbarGroup: String, CaseIterable, Identifiable {
    case window
    case playback
    case state
    case capture
    case time
    case tools
    case view

    var id: String { rawValue }

    var localizationKey: String {
        "gameToolbar.group.\(rawValue)"
    }
}

enum GameToolbarItemID: String, CaseIterable, Codable, Identifiable {
    case stop
    case pauseResume
    case restart
    case save
    case load
    case undoLoad
    case record
    case rewind
    case fastForward
    case slowMotion
    case cheats
    case training
    case guide
    case shader
    case bezel
    case fullscreen

    var id: String { rawValue }
}

struct GameToolbarItem: Identifiable {
    let id: GameToolbarItemID
    let group: GameToolbarGroup
    let labelKey: String
    let icon: String
    let priority: Int
    let isRequired: Bool

    var isPrimary: Bool {
        switch id {
        case .stop, .pauseResume, .restart, .save, .load:
            return true
        default:
            return false
        }
    }
}

@MainActor
enum GameToolbarModel {
    static let items: [GameToolbarItem] = [
        GameToolbarItem(id: .stop, group: .window, labelKey: "toolbar.stop", icon: "power", priority: 100, isRequired: true),
        GameToolbarItem(id: .pauseResume, group: .playback, labelKey: "toolbar.pause", icon: "pause.fill", priority: 99, isRequired: false),
        GameToolbarItem(id: .restart, group: .playback, labelKey: "toolbar.restart", icon: "arrow.counterclockwise", priority: 80, isRequired: false),
        GameToolbarItem(id: .save, group: .state, labelKey: "toolbar.save", icon: "tray.and.arrow.down.fill", priority: 98, isRequired: false),
        GameToolbarItem(id: .load, group: .state, labelKey: "toolbar.load", icon: "clock.arrow.circlepath", priority: 97, isRequired: false),
        GameToolbarItem(id: .undoLoad, group: .state, labelKey: "toolbar.undoLoad", icon: "arrow.uturn.backward", priority: 6, isRequired: false),
        GameToolbarItem(id: .record, group: .capture, labelKey: "toolbar.record", icon: "record.circle", priority: 69, isRequired: false),
        GameToolbarItem(id: .rewind, group: .time, labelKey: "toolbar.rewind", icon: "backward.fill", priority: 21, isRequired: false),
        GameToolbarItem(id: .fastForward, group: .time, labelKey: "toolbar.fastForward", icon: "hare.fill", priority: 22, isRequired: false),
        GameToolbarItem(id: .slowMotion, group: .time, labelKey: "toolbar.slowMotion", icon: "tortoise.fill", priority: 20, isRequired: false),
        GameToolbarItem(id: .cheats, group: .tools, labelKey: "toolbar.cheats", icon: "wand.and.stars", priority: 40, isRequired: false),
        GameToolbarItem(id: .training, group: .tools, labelKey: "toolbar.fightTraining", icon: "figure.martial.arts", priority: 12, isRequired: false),
        GameToolbarItem(id: .guide, group: .tools, labelKey: "toolbar.gameGuide", icon: "book", priority: 11, isRequired: false),
        GameToolbarItem(id: .shader, group: .tools, labelKey: "toolbar.shader", icon: "sparkles", priority: 30, isRequired: false),
        GameToolbarItem(id: .bezel, group: .tools, labelKey: "toolbar.bezel", icon: "rectangle.on.rectangle", priority: 5, isRequired: false),
        GameToolbarItem(id: .fullscreen, group: .view, labelKey: "toolbar.fullscreen", icon: "arrow.up.left.and.arrow.down.right", priority: 50, isRequired: false)
    ]

    static func availableItems(
        runner: EmulatorRunner?,
        windowController: StandaloneGameWindowController,
        preferences: GameToolbarPreferences
    ) -> [GameToolbarItem] {
        items.filter { item in
            preferences.isEnabled(item.id) && isAvailable(item.id, runner: runner, windowController: windowController)
        }
    }

    static func isAvailable(
        _ id: GameToolbarItemID,
        runner: EmulatorRunner?,
        windowController: StandaloneGameWindowController
    ) -> Bool {
        switch id {
        case .stop, .fullscreen:
            return true
        case .pauseResume, .restart, .save, .load, .undoLoad, .cheats:
            return runner != nil
        case .record:
            return StreamRecordingService.shared.isToolbarFeatureAvailable
        case .rewind:
            return runner != nil && EmulatorRunner.rewindFeatureEnabled()
        case .fastForward:
            return runner != nil && EmulatorRunner.fastForwardFeatureEnabled()
        case .slowMotion:
            return runner != nil && EmulatorRunner.slowMotionFeatureEnabled()
        case .training:
            return windowController.trainingModeViewModel.hasGameData
        case .guide:
            return windowController.gameGuideViewModel.hasGuideData
        case .shader:
            return runner != nil && windowController.currentGameROM != nil
        case .bezel:
            guard runner != nil, let rom = windowController.currentGameROM else { return false }
            let systemID = rom.systemID ?? "default"
            return windowController.library != nil && BezelManager.shared.hasBezelSupport(for: systemID)
        }
    }
}
