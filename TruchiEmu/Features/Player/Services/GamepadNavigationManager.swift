import Foundation
import GameController
import Combine
import SwiftUI
import AppKit

enum GamepadNavZone: Int, CaseIterable {
    case sidebar = 0
    case content = 1
    case gameToolbar = 2

    var isLibraryZone: Bool {
        switch self {
        case .sidebar, .content: return true
        case .gameToolbar: return false
        }
    }
}

@MainActor
final class GamepadNavigationManager: ObservableObject {
    static let shared = GamepadNavigationManager()

    @Published var activeZone: GamepadNavZone = .sidebar
    @Published var sidebarIndex: Int = 0
    @Published var contentIndex: Int = 0
    @Published var gameToolbarIndex: Int = 0
    @Published var isGamepadActive: Bool = false

    /// True while the gamepad toolbar overlay is open. The runner checks this
    /// to ignore controller input so presses aren't double-handled by the game
    /// while the user is navigating the toolbar from the couch.
    @MainActor var isGamepadToolbarActive: Bool = false
    @Published var scrollAnchorIndex: Int = 0

    var suppressLeftStickInToolbar: Bool = false

    var sidebarItemCount: Int = 0
    var contentItemCount: Int = 0
    var gameToolbarItemCount: Int = 0
    var columnCount: Int = 4

    var savedSidebarIndex: Int = 0
    var savedContentIndex: Int = 0
    var savedGameToolbarIndex: Int = 0

    private var pollTimer: Timer?
    private var lastLoggedButtons: Set<GamepadNavButton> = []
    private var lastRepeatTime: [GamepadNavButton: Double] = [:]
    private var pressedButtons: Set<GamepadNavButton> = []
    private var lastPressTime: [GamepadNavButton: Double] = [:]
    private static let deadZone: Float = 0.5
    private static let repeatDelay: Double = 0.12
    private static let pollInterval: Double = 1.0 / 30.0
    /// Max time between the two constituent button presses for a combo (L3+R3,
    /// Start+Select) to count as a simultaneous press. Polling runs at 30 Hz, so
    /// two buttons pressed a few ms apart would otherwise land in different
    /// frames and never register as a combo.
    private static let comboWindow: Double = 0.18

    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeAppActivation()
    }

    deinit {
        pollTimer?.invalidate()
    }

    private func observeAppActivation() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.startPolling()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.stopPolling()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if NSApp.isActive {
                    self?.startPolling()
                }
            }
            .store(in: &cancellables)
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.poll()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        pressedButtons = []
        lastRepeatTime = [:]
        lastPressTime = [:]
        isGamepadActive = false
    }

    func focusZone(_ zone: GamepadNavZone) {
        saveCurrentZoneIndex()
        activeZone = zone
        switch zone {
        case .sidebar:
            sidebarIndex = min(savedSidebarIndex, max(0, sidebarItemCount - 1))
        case .content:
            contentIndex = min(savedContentIndex, max(0, contentItemCount - 1))
        case .gameToolbar:
            gameToolbarIndex = min(savedGameToolbarIndex, max(0, gameToolbarItemCount - 1))
        }
    }

    func focusNextZone() {
        saveCurrentZoneIndex()
        switch activeZone {
        case .sidebar:
            if contentItemCount > 0 {
                activeZone = .content
                contentIndex = min(savedContentIndex, max(0, contentItemCount - 1))
            }
        case .content:
            if gameToolbarItemCount > 0 {
                activeZone = .gameToolbar
                gameToolbarIndex = min(savedGameToolbarIndex, max(0, gameToolbarItemCount - 1))
            }
        case .gameToolbar:
            if sidebarItemCount > 0 {
                activeZone = .sidebar
                sidebarIndex = min(savedSidebarIndex, max(0, sidebarItemCount - 1))
            }
        }
    }

    func focusPrevZone() {
        saveCurrentZoneIndex()
        switch activeZone {
        case .sidebar:
            if gameToolbarItemCount > 0 {
                activeZone = .gameToolbar
                gameToolbarIndex = min(savedGameToolbarIndex, max(0, gameToolbarItemCount - 1))
            } else if contentItemCount > 0 {
                activeZone = .content
                contentIndex = min(savedContentIndex, max(0, contentItemCount - 1))
            }
        case .content:
            if sidebarItemCount > 0 {
                activeZone = .sidebar
                sidebarIndex = min(savedSidebarIndex, max(0, sidebarItemCount - 1))
            }
        case .gameToolbar:
            if contentItemCount > 0 {
                activeZone = .content
                contentIndex = min(savedContentIndex, max(0, contentItemCount - 1))
            }
        }
    }

    func saveCurrentZoneIndex() {
        switch activeZone {
        case .sidebar: savedSidebarIndex = sidebarIndex
        case .content: savedContentIndex = contentIndex
        case .gameToolbar: savedGameToolbarIndex = gameToolbarIndex
        }
    }

    var currentZoneIndex: Int {
        get {
            switch activeZone {
            case .sidebar: return sidebarIndex
            case .content: return contentIndex
            case .gameToolbar: return gameToolbarIndex
            }
        }
        set {
            switch activeZone {
            case .sidebar: sidebarIndex = newValue
            case .content: contentIndex = newValue
            case .gameToolbar: gameToolbarIndex = newValue
            }
        }
    }

    var currentZoneItemCount: Int {
        switch activeZone {
        case .sidebar: return sidebarItemCount
        case .content: return contentItemCount
        case .gameToolbar: return gameToolbarItemCount
        }
    }

    func clampCurrentIndex() {
        let count = currentZoneItemCount
        guard count > 0 else { return }
        if currentZoneIndex >= count { currentZoneIndex = count - 1 }
        if currentZoneIndex < 0 { currentZoneIndex = 0 }
    }

    private func poll() {
        guard NSApp.isActive else { return }
        guard GamepadNavConfigManager.shared.isEnabled else {
            if isGamepadActive { isGamepadActive = false }
            return
        }

        let controllers = ControllerService.shared.connectedControllers
        let gamepad = controllers.first(where: { !$0.isKeyboard })?.gcController?.extendedGamepad

        // Controllers SDL handles as raw joysticks (unrecognized gamepads) are
        // never exposed as GCController instances, so poll SDL's nav snapshot too.
        let sdlButtons = SDLInputManager.shared.pollNavButtons()

        guard gamepad != nil || !sdlButtons.isEmpty else {
            if isGamepadActive { isGamepadActive = false }
            return
        }

        if !isGamepadActive { isGamepadActive = true }
        _ = GamepadNavCoordinator.shared

        let now = CACurrentMediaTime()
        let config = GamepadNavConfigManager.shared.config

        var newlyPressed = Set<GamepadNavButton>()

        if let gamepad {
            readDigitalButtons(gamepad, into: &newlyPressed)
        } else {
            newlyPressed.formUnion(sdlButtons)
        }
        let topContext = GamepadNavContextStack.shared.topActive()
        if topContext is GamepadGameToolbarContext && suppressLeftStickInToolbar {
            var nonLeftStick = Set<GamepadNavButton>()
            if let gamepad {
                readAnalogInputs(gamepad, into: &nonLeftStick, now: now, filterLeftStick: true)
            }
            newlyPressed.formUnion(nonLeftStick)
        } else if let gamepad {
            readAnalogInputs(gamepad, into: &newlyPressed, now: now)
        }

        // Record when each individual button was first pressed so combos can be
        // detected even when the two buttons land in separate poll frames.
        for button in newlyPressed where lastPressTime[button] == nil {
            lastPressTime[button] = now
        }

        // Combo detection: the companion button may have been pressed up to
        // `comboWindow` seconds ago (i.e. in a neighbouring poll frame).
        func comboFormed(_ a: GamepadNavButton, _ b: GamepadNavButton, _ combo: GamepadNavButton) {
            guard (newlyPressed.contains(a) && newlyPressed.contains(b))
                    || (newlyPressed.contains(a) && recentPress(b))
                    || (newlyPressed.contains(b) && recentPress(a)) else { return }
            newlyPressed.insert(combo)
            newlyPressed.remove(a)
            newlyPressed.remove(b)
            lastPressTime[a] = nil
            lastPressTime[b] = nil
        }

        comboFormed(.l3, .r3, .l3PlusR3)
        comboFormed(.start, .select, .startPlusSelect)

        let justPressed = newlyPressed.subtracting(pressedButtons)
        let justReleased = pressedButtons.subtracting(newlyPressed)

        if justPressed != lastLoggedButtons && !justPressed.isEmpty {
            LoggerService.info(category: "GamepadNav", "Pressed: \(justPressed), zone=\(activeZone)")
            lastLoggedButtons = justPressed
        }

        for button in justReleased {
            lastRepeatTime.removeValue(forKey: button)
            lastPressTime.removeValue(forKey: button)
        }

        processActions(config: config, justPressed: justPressed, newlyPressed: newlyPressed, now: now)

        pressedButtons = newlyPressed
    }

    private let stickToNavAction: [GamepadNavButton: GamepadNavAction] = [
        .leftStickUp: .navigateUp, .leftStickDown: .navigateDown,
        .leftStickLeft: .navigateLeft, .leftStickRight: .navigateRight
    ]

    private func processActions(config: [GamepadNavAction: GamepadNavConfig], justPressed: Set<GamepadNavButton>, newlyPressed: Set<GamepadNavButton>, now: Double) {
        for action in GamepadNavAction.allCases {
            guard let cfg = config[action], !cfg.binding.isUnset, let mappedButton = cfg.binding.button else { continue }

            var shouldFire = false

            if !mappedButton.isAnalog {
                // D-pad directions auto-repeat while held so the toolbar focus
                // keeps moving (matching the analog-stick behaviour).
                if [.dpadUp, .dpadDown, .dpadLeft, .dpadRight].contains(mappedButton) {
                    if justPressed.contains(mappedButton) {
                        shouldFire = true
                        lastRepeatTime[mappedButton] = now
                    } else if newlyPressed.contains(mappedButton) {
                        if let lastTime = lastRepeatTime[mappedButton], now >= lastTime + Self.repeatDelay {
                            shouldFire = true
                            lastRepeatTime[mappedButton] = now
                        }
                    }
                } else {
                    shouldFire = justPressed.contains(mappedButton)
                }
            } else {
                if justPressed.contains(mappedButton) {
                    shouldFire = true
                    lastRepeatTime[mappedButton] = now
                } else if newlyPressed.contains(mappedButton) {
                    if let lastTime = lastRepeatTime[mappedButton], now >= lastTime + Self.repeatDelay {
                        shouldFire = true
                        lastRepeatTime[mappedButton] = now
                    }
                }
            }

            if shouldFire {
                LoggerService.info(category: "GamepadNav", "Firing \(action) from \(mappedButton.displayName)")
                fireAction(action)
            }
        }

        for (stickButton, navAction) in stickToNavAction {
            if newlyPressed.contains(stickButton) {
                var shouldFire = false
                if justPressed.contains(stickButton) {
                    shouldFire = true
                    lastRepeatTime[stickButton] = now
                } else if let lastTime = lastRepeatTime[stickButton], now >= lastTime + Self.repeatDelay {
                    shouldFire = true
                    lastRepeatTime[stickButton] = now
                }
                if shouldFire {
                    fireAction(navAction)
                }
            }
        }
    }

    /// True if `button` was pressed within `comboWindow` seconds (including in a
    /// neighbouring poll frame) and is still considered "recently active".
    private func recentPress(_ button: GamepadNavButton) -> Bool {
        guard let t = lastPressTime[button] else { return false }
        return CACurrentMediaTime() - t <= Self.comboWindow
    }

    private func readDigitalButtons(_ gamepad: GCExtendedGamepad, into buttons: inout Set<GamepadNavButton>) {
        if gamepad.buttonA.isPressed { buttons.insert(.buttonA) }
        if gamepad.buttonB.isPressed { buttons.insert(.buttonB) }
        if gamepad.buttonX.isPressed { buttons.insert(.buttonX) }
        if gamepad.buttonY.isPressed { buttons.insert(.buttonY) }
        if gamepad.leftShoulder.isPressed { buttons.insert(.l1) }
        if gamepad.rightShoulder.isPressed { buttons.insert(.r1) }
        if gamepad.leftTrigger.value > 0.5 { buttons.insert(.l2) }
        if gamepad.rightTrigger.value > 0.5 { buttons.insert(.r2) }
        if gamepad.leftThumbstickButton?.isPressed == true { buttons.insert(.l3) }
        if gamepad.rightThumbstickButton?.isPressed == true { buttons.insert(.r3) }
        if gamepad.buttonMenu.isPressed { buttons.insert(.start) }
        if gamepad.buttonOptions?.isPressed == true { buttons.insert(.select) }
    }

    private func readAnalogInputs(_ gamepad: GCExtendedGamepad, into buttons: inout Set<GamepadNavButton>, now: Double, filterLeftStick: Bool = false) {
        let dz = Self.deadZone

        if gamepad.dpad.up.isPressed { buttons.insert(.dpadUp) }
        if gamepad.dpad.down.isPressed { buttons.insert(.dpadDown) }
        if gamepad.dpad.left.isPressed { buttons.insert(.dpadLeft) }
        if gamepad.dpad.right.isPressed { buttons.insert(.dpadRight) }

        if !filterLeftStick {
            let lx = gamepad.leftThumbstick.xAxis.value
            let ly = gamepad.leftThumbstick.yAxis.value
            if fabsf(ly) >= dz {
                buttons.insert(ly > 0 ? .leftStickUp : .leftStickDown)
            }
            if fabsf(lx) >= dz {
                buttons.insert(lx > 0 ? .leftStickRight : .leftStickLeft)
            }
        }

        let rx = gamepad.rightThumbstick.xAxis.value
        let ry = gamepad.rightThumbstick.yAxis.value
        if fabsf(ry) >= dz {
            buttons.insert(ry > 0 ? .rightStickUp : .rightStickDown)
        }
        if fabsf(rx) >= dz {
            buttons.insert(rx > 0 ? .rightStickRight : .rightStickLeft)
        }
    }

    private func fireAction(_ action: GamepadNavAction) {
        if let context = GamepadNavContextStack.shared.topActive() {
            context.handleAction(action)
        }
    }

    func setGameRunning(_ isRunning: Bool) {
        // Context stack handles game running state now
    }
}
