import Foundation
import AppKit
import GameController

extension Notification.Name {
    static let sdlControllerConnected = Notification.Name("sdlControllerConnected")
    static let sdlControllerDisconnected = Notification.Name("sdlControllerDisconnected")
}

@MainActor
class SDLInputManager: ObservableObject {
    static let shared = SDLInputManager()

    private let sdlQueue = DispatchQueue(label: "com.truchiemu.sdl", qos: .userInteractive)
    private let sdlDataLock = NSLock()
    private nonisolated(unsafe) var isRunning = false

    private let runnerLock = NSLock()
    private nonisolated(unsafe) weak var _activeRunner: EmulatorRunner?

    // SDL_GameController handles — recognized controllers with built-in mappings
    private nonisolated(unsafe) var gameControllers: [Int32: OpaquePointer] = [:]
    // Raw SDL_Joystick handles — unrecognized controllers (fallback path)
    private nonisolated(unsafe) var joysticks: [Int32: OpaquePointer] = [:]
    // Track which instance IDs are game controllers to avoid double-processing
    private nonisolated(unsafe) var joystickIsGameController: Set<Int32> = []
    private nonisolated(unsafe) var portForInstance: [Int32: Int] = [:]
    private nonisolated(unsafe) var nextPort = 0

    // Capture callback for button remapping in settings
    private nonisolated(unsafe) var captureCallback: ((Int, String) -> Void)?
    private nonisolated(unsafe) var captureInstanceID: Int32?

    // SDL share button index cached at runner registration. The same
    // physical button dispatches single-press vs long-press ShareBehaviors
    // via the long-press detector (BaseRunner.handleSharePress).
    nonisolated(unsafe) var cachedShareButtonIndex: Int? = nil

    // Pollable snapshot of currently-pressed buttons, keyed by the app's
    // GamepadNavButton vocabulary, so GamepadNavigationManager can drive UI
    // navigation (and button combos like L3+R3) for controllers that SDL
    // handles as raw joysticks and never exposes as GCController instances.
    nonisolated(unsafe) private var navButtonState: [GamepadNavButton: Bool] = [:]
    private let navStateLock = NSLock()

    private nonisolated static let deadzone: Int16 = 8000
    private nonisolated static let triggerThreshold: Int16 = 16384

    // SDL_GameController button → retroID (used for recognized controllers)
    private nonisolated static let buttonMap: [Int32: Int] = [
        SDL_CONTROLLER_BUTTON_A.rawValue: 8,
        SDL_CONTROLLER_BUTTON_B.rawValue: 0,
        SDL_CONTROLLER_BUTTON_X.rawValue: 1,
        SDL_CONTROLLER_BUTTON_Y.rawValue: 9,
        SDL_CONTROLLER_BUTTON_BACK.rawValue: 2,
        SDL_CONTROLLER_BUTTON_START.rawValue: 3,
        SDL_CONTROLLER_BUTTON_DPAD_UP.rawValue: 4,
        SDL_CONTROLLER_BUTTON_DPAD_DOWN.rawValue: 5,
        SDL_CONTROLLER_BUTTON_DPAD_LEFT.rawValue: 6,
        SDL_CONTROLLER_BUTTON_DPAD_RIGHT.rawValue: 7,
        SDL_CONTROLLER_BUTTON_LEFTSHOULDER.rawValue: 10,
        SDL_CONTROLLER_BUTTON_RIGHTSHOULDER.rawValue: 11,
        SDL_CONTROLLER_BUTTON_LEFTSTICK.rawValue: 14,
        SDL_CONTROLLER_BUTTON_RIGHTSTICK.rawValue: 15,
    ]

    // Raw joystick button index → retroID (fallback for unrecognized controllers)
    // Standard HID gamepad layout: 0=A, 1=B, 2=X, 3=Y, 4=L, 5=R, 6=ZL, 7=ZR,
    // 8=Select, 9=Start, 10=L3, 11=R3
    private nonisolated static let joystickButtonMap: [Int: Int] = [
        0: 8,   // A (bottom) → RETRO_A
        1: 0,   // B (right) → RETRO_B
        2: 1,   // X (left) → RETRO_Y
        3: 9,   // Y (top) → RETRO_X
        4: 10,  // L → RETRO_L
        5: 11,  // R → RETRO_R
        6: 12,  // ZL → RETRO_L2
        7: 13,  // ZR → RETRO_R2
        8: 2,   // Select → RETRO_SELECT
        9: 3,   // Start → RETRO_START
        10: 14, // L3 → RETRO_L3
        11: 15, // R3 → RETRO_R3
    ]

    // Game controller axis → (stick index, axis id)
    private nonisolated static let axisMap: [Int32: (index: Int, id: Int)] = [
        SDL_CONTROLLER_AXIS_LEFTX.rawValue: (0, 0),
        SDL_CONTROLLER_AXIS_LEFTY.rawValue: (0, 1),
        SDL_CONTROLLER_AXIS_RIGHTX.rawValue: (1, 0),
        SDL_CONTROLLER_AXIS_RIGHTY.rawValue: (1, 1),
    ]

    // Raw joystick axis index → (stick index, axis id)
    // Standard HID gamepad: 0=LX, 1=LY, 2=RX, 3=RY, 4=ZL, 5=ZR
    private nonisolated static let joystickAxisMap: [Int: (index: Int, id: Int)] = [
        0: (0, 0),
        1: (0, 1),
        2: (1, 0),
        3: (1, 1),
    ]

    private init() {}

    // SDL game-controller button enum index → app nav button (used for
    // recognized controllers handled via the SDL_CONTROLLERBUTTON* events).
    private nonisolated static let sdlControllerNavMap: [Int32: GamepadNavButton] = [
        SDL_CONTROLLER_BUTTON_A.rawValue: .buttonA,
        SDL_CONTROLLER_BUTTON_B.rawValue: .buttonB,
        SDL_CONTROLLER_BUTTON_X.rawValue: .buttonX,
        SDL_CONTROLLER_BUTTON_Y.rawValue: .buttonY,
        SDL_CONTROLLER_BUTTON_BACK.rawValue: .select,
        SDL_CONTROLLER_BUTTON_START.rawValue: .start,
        SDL_CONTROLLER_BUTTON_LEFTSHOULDER.rawValue: .l1,
        SDL_CONTROLLER_BUTTON_RIGHTSHOULDER.rawValue: .r1,
        SDL_CONTROLLER_BUTTON_DPAD_UP.rawValue: .dpadUp,
        SDL_CONTROLLER_BUTTON_DPAD_DOWN.rawValue: .dpadDown,
        SDL_CONTROLLER_BUTTON_DPAD_LEFT.rawValue: .dpadLeft,
        SDL_CONTROLLER_BUTTON_DPAD_RIGHT.rawValue: .dpadRight,
        SDL_CONTROLLER_BUTTON_LEFTSTICK.rawValue: .l3,
        SDL_CONTROLLER_BUTTON_RIGHTSTICK.rawValue: .r3,
    ]

    // Raw joystick button index → app nav button (used for unrecognized
    // controllers handled via the SDL_JOYBUTTON* fallback events).
    private nonisolated static let joystickNavMap: [Int: GamepadNavButton] = [
        0: .buttonA, 1: .buttonB, 2: .buttonX, 3: .buttonY,
        4: .l1, 5: .r1, 6: .l2, 7: .r2,
        8: .select, 9: .start, 10: .l3, 11: .r3,
    ]

    private nonisolated func setNavButton(_ button: GamepadNavButton, pressed: Bool) {
        navStateLock.lock()
        navButtonState[button] = pressed
        navStateLock.unlock()
    }

    /// Returns the set of app nav buttons currently held, for UI navigation
    /// polling. Safe to call from the main thread.
    nonisolated func pollNavButtons() -> Set<GamepadNavButton> {
        navStateLock.lock()
        let held = Set(navButtonState.compactMap { $0.value ? $0.key : nil })
        navStateLock.unlock()
        return held
    }

    // MARK: - Public API

    func start() {
        guard !isRunning else { return }
        isRunning = true
        sdlQueue.async { self.runSDLLoop() }
    }

    func stop() {
        isRunning = false
    }

    func registerRunner(_ runner: EmulatorRunner) {
        runnerLock.lock()
        _activeRunner = runner
        runnerLock.unlock()
        // Cache the SDL share button index (per-system resolved, falling
        // back to the global binding when no per-system override exists).
        let sysID = runner.rom?.systemID
        let binding = HotkeyConfigManager.shared.controllerBinding(for: .shareButton, systemID: sysID, source: .sdl)
        cachedShareButtonIndex = Int(binding.identifier)
    }

    func unregisterRunner() {
        runnerLock.lock()
        _activeRunner = nil
        runnerLock.unlock()
    }

    // MARK: - SDL Loop

    private nonisolated func runSDLLoop() {
        guard SDL_Init(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER) == 0 else {
            let err = String(cString: SDL_GetError())
            LoggerService.warning(category: "SDL", "Failed to init SDL2: \(err)")
            isRunning = false
            return
        }

        SDL_GameControllerEventState(SDL_ENABLE)

        while isRunning {
            var event = SDL_Event()
            while SDL_PollEvent(&event) > 0 {
                handleEvent(event)
            }
            Thread.sleep(forTimeInterval: 0.016)
        }

        shutdownSDL()
    }

    private nonisolated func shutdownSDL() {
        sdlDataLock.lock()
        for (_, ctrl) in gameControllers {
            SDL_GameControllerClose(ctrl)
        }
        for (_, joy) in joysticks {
            SDL_JoystickClose(joy)
        }
        gameControllers.removeAll()
        joysticks.removeAll()
        joystickIsGameController.removeAll()
        portForInstance.removeAll()
        sdlDataLock.unlock()
        SDL_QuitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER)
    }

    // MARK: - Event Handling

    private nonisolated func handleEvent(_ event: SDL_Event) {
        switch event.type {
        case SDL_JOYDEVICEADDED.rawValue:
            handleDeviceAdded(event.jdevice)
        case SDL_JOYDEVICEREMOVED.rawValue:
            handleDeviceRemoved(event.jdevice)
        // Game controller events (only for recognized controllers)
        case SDL_CONTROLLERBUTTONDOWN.rawValue:
            handleButtonEvent(event.cbutton, pressed: true)
        case SDL_CONTROLLERBUTTONUP.rawValue:
            handleButtonEvent(event.cbutton, pressed: false)
        case SDL_CONTROLLERAXISMOTION.rawValue:
            handleAxisEvent(event.caxis)
        // Raw joystick events (fallback for unrecognized controllers)
        case SDL_JOYBUTTONDOWN.rawValue:
            handleJoyButtonEvent(event.jbutton, pressed: true)
        case SDL_JOYBUTTONUP.rawValue:
            handleJoyButtonEvent(event.jbutton, pressed: false)
        case SDL_JOYAXISMOTION.rawValue:
            handleJoyAxisEvent(event.jaxis)
        case SDL_JOYHATMOTION.rawValue:
            handleJoyHatEvent(event.jhat)
        default:
            break
        }
    }

    // MARK: - Device Connection

    private nonisolated func handleDeviceAdded(_ event: SDL_JoyDeviceEvent) {
        let deviceIndex = event.which

        // Skip recognized game controllers — GCController already handles them
        if SDL_IsGameController(deviceIndex) == SDL_TRUE {
            LoggerService.info(category: "SDL", "Skipping game controller (device \(deviceIndex)) — already handled by GCController")
            return
        }

        // Fallback: open as raw joystick for unrecognized controllers
        guard let joystick = SDL_JoystickOpen(deviceIndex) else {
            let err = String(cString: SDL_GetError())
            LoggerService.warning(category: "SDL", "Failed to open joystick: \(err)")
            return
        }
        let instanceID = SDL_JoystickInstanceID(joystick)
        let numButtons = Int(SDL_JoystickNumButtons(joystick))
        let numAxes = Int(SDL_JoystickNumAxes(joystick))
        let numHats = Int(SDL_JoystickNumHats(joystick))

        sdlDataLock.lock()
        joysticks[instanceID] = joystick
        let port = assignPortLocked(for: instanceID)
        sdlDataLock.unlock()

        if let name = SDL_JoystickName(joystick) {
            LoggerService.info(category: "SDL", "Joystick '\(String(cString: name))' (instance \(instanceID)) opened as raw joystick on port \(port) — buttons:\(numButtons) axes:\(numAxes) hats:\(numHats)")
        } else {
            LoggerService.info(category: "SDL", "Unknown joystick (instance \(instanceID)) opened on port \(port) — buttons:\(numButtons) axes:\(numAxes) hats:\(numHats)")
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sdlControllerConnected, object: nil)
        }
    }

    private nonisolated func handleDeviceRemoved(_ event: SDL_JoyDeviceEvent) {
        let instanceID = event.which

        sdlDataLock.lock()
        if let controller = gameControllers.removeValue(forKey: instanceID) {
            joystickIsGameController.remove(instanceID)
            portForInstance.removeValue(forKey: instanceID)
            sdlDataLock.unlock()
            SDL_GameControllerClose(controller)
            LoggerService.info(category: "SDL", "Game controller (instance \(instanceID)) disconnected")
        } else if let joystick = joysticks.removeValue(forKey: instanceID) {
            portForInstance.removeValue(forKey: instanceID)
            sdlDataLock.unlock()
            SDL_JoystickClose(joystick)
            LoggerService.info(category: "SDL", "Joystick (instance \(instanceID)) disconnected")
        } else {
            sdlDataLock.unlock()
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sdlControllerDisconnected, object: nil)
        }
    }

    // Caller must hold sdlDataLock
    private nonisolated func assignPortLocked(for instanceID: Int32) -> Int {
        if let existing = portForInstance[instanceID] {
            return existing
        }
        let port = nextPort
        portForInstance[instanceID] = port
        nextPort += 1
        LoggerService.debug(category: "SDL", "Assigned port \(port) to instance \(instanceID)")
        return port
    }

    // MARK: - Game Controller Events

    private nonisolated func handleButtonEvent(_ event: SDL_ControllerButtonEvent, pressed: Bool) {
        if let navButton = Self.sdlControllerNavMap[Int32(event.button)] {
            setNavButton(navButton, pressed: pressed)
        }
        if pressed {
            sdlDataLock.lock()
            let capID = captureInstanceID
            let cb = captureCallback
            if capID != nil { captureInstanceID = nil; captureCallback = nil }
            sdlDataLock.unlock()

            if event.which == capID, let cb = cb {
                if let name = SDL_GameControllerGetStringForButton(SDL_GameControllerButton(rawValue: Int32(event.button))) {
                    cb(Int(event.button), String(cString: name))
                } else {
                    cb(Int(event.button), "Button \(event.button)")
                }
                return
            }

            // Check share button after capture check. A single physical
            // button is dispatched here; short vs long press is resolved
            // by the long-press detector on the runner side.
            let btn = Int(event.button)
            if btn == cachedShareButtonIndex {
                if pressed {
                    DispatchQueue.main.async { ControllerLongPressDetector.shared.handleSDLPressDown(buttonIndex: btn) }
                } else {
                    DispatchQueue.main.async { ControllerLongPressDetector.shared.handleSDLPressUp(buttonIndex: btn) }
                }
                return
            }
        }

        sdlDataLock.lock()
        let port = portForInstance[event.which]
        sdlDataLock.unlock()
        guard let retroID = Self.buttonMap[Int32(event.button)], let port else { return }
        dispatchButton(retroID: retroID, player: port, pressed: pressed)
    }

    private nonisolated func handleAxisEvent(_ event: SDL_ControllerAxisEvent) {
        if abs(Int32(event.value)) > Self.triggerThreshold {
            sdlDataLock.lock()
            let capID = captureInstanceID
            let cb = captureCallback
            if capID != nil { captureInstanceID = nil; captureCallback = nil }
            sdlDataLock.unlock()

            if event.which == capID, let cb = cb {
                let axisNames: [Int32: (Int, String)] = [
                    SDL_CONTROLLER_AXIS_LEFTX.rawValue: (100, "Left Stick X"),
                    SDL_CONTROLLER_AXIS_LEFTY.rawValue: (101, "Left Stick Y"),
                    SDL_CONTROLLER_AXIS_RIGHTX.rawValue: (102, "Right Stick X"),
                    SDL_CONTROLLER_AXIS_RIGHTY.rawValue: (103, "Right Stick Y"),
                    SDL_CONTROLLER_AXIS_TRIGGERLEFT.rawValue: (104, "Left Trigger"),
                    SDL_CONTROLLER_AXIS_TRIGGERRIGHT.rawValue: (105, "Right Trigger"),
                ]
                if let (idx, name) = axisNames[Int32(event.axis)] { cb(idx, name) }
                return
            }
        }

        sdlDataLock.lock()
        let port = portForInstance[event.which]
        sdlDataLock.unlock()
        guard let port else { return }

        let axis = Int32(event.axis)
        if axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT.rawValue {
            let pressed = event.value > Self.triggerThreshold
            dispatchButton(retroID: 12, player: port, pressed: pressed)
            dispatchAnalogButton(retroID: 12, value: event.value, player: port)
            return
        }
        if axis == SDL_CONTROLLER_AXIS_TRIGGERRIGHT.rawValue {
            let pressed = event.value > Self.triggerThreshold
            dispatchButton(retroID: 13, player: port, pressed: pressed)
            dispatchAnalogButton(retroID: 13, value: event.value, player: port)
            return
        }

        let dz = Int32(Self.deadzone)
        if axis == SDL_CONTROLLER_AXIS_LEFTX.rawValue {
            setNavButton(.leftStickLeft, pressed: event.value < -dz)
            setNavButton(.leftStickRight, pressed: event.value > dz)
        } else if axis == SDL_CONTROLLER_AXIS_LEFTY.rawValue {
            setNavButton(.leftStickUp, pressed: event.value < -dz)
            setNavButton(.leftStickDown, pressed: event.value > dz)
        } else if axis == SDL_CONTROLLER_AXIS_RIGHTX.rawValue {
            setNavButton(.rightStickLeft, pressed: event.value < -dz)
            setNavButton(.rightStickRight, pressed: event.value > dz)
        } else if axis == SDL_CONTROLLER_AXIS_RIGHTY.rawValue {
            setNavButton(.rightStickUp, pressed: event.value < -dz)
            setNavButton(.rightStickDown, pressed: event.value > dz)
        }

        guard let (index, id) = Self.axisMap[axis] else { return }
        dispatchAnalog(index: index, id: id, value: event.value, player: port)
    }

    // MARK: - Raw Joystick Events (Fallback)

    private nonisolated func handleJoyButtonEvent(_ event: SDL_JoyButtonEvent, pressed: Bool) {
        if let navButton = Self.joystickNavMap[Int(event.button)] {
            setNavButton(navButton, pressed: pressed)
        }
        if pressed {
            sdlDataLock.lock()
            let capID = captureInstanceID
            let cb = captureCallback
            if capID != nil { captureInstanceID = nil; captureCallback = nil }
            sdlDataLock.unlock()

            if event.which == capID, let cb = cb {
                let name = "Button \(event.button)"
                cb(Int(event.button), name)
                return
            }

            // Check share button after capture check. A single physical
            // button is dispatched here; short vs long press is resolved
            // by the long-press detector on the runner side.
            let btn = Int(event.button)
            if btn == cachedShareButtonIndex {
                if pressed {
                    DispatchQueue.main.async { ControllerLongPressDetector.shared.handleSDLPressDown(buttonIndex: btn) }
                } else {
                    DispatchQueue.main.async { ControllerLongPressDetector.shared.handleSDLPressUp(buttonIndex: btn) }
                }
                return
            }
        }

        sdlDataLock.lock()
        let isGC = joystickIsGameController.contains(event.which)
        let port = portForInstance[event.which]
        sdlDataLock.unlock()

        guard !isGC, let port else { return }
        guard let retroID = Self.joystickButtonMap[Int(event.button)] else { return }
        dispatchButton(retroID: retroID, player: port, pressed: pressed)
    }

    private nonisolated func handleJoyAxisEvent(_ event: SDL_JoyAxisEvent) {
        if abs(Int32(event.value)) > Self.triggerThreshold {
            sdlDataLock.lock()
            let capID = captureInstanceID
            let cb = captureCallback
            if capID != nil { captureInstanceID = nil; captureCallback = nil }
            sdlDataLock.unlock()

            if event.which == capID, let cb = cb {
                let axisNames: [Int: (Int, String)] = [
                    0: (100, "Left Stick X"), 1: (101, "Left Stick Y"),
                    2: (102, "Right Stick X"), 3: (103, "Right Stick Y"),
                    4: (104, "Left Trigger"), 5: (105, "Right Trigger"),
                ]
                if let (idx, name) = axisNames[Int(event.axis)] { cb(idx, name) }
                return
            }
        }

        sdlDataLock.lock()
        let isGC = joystickIsGameController.contains(event.which)
        let port = portForInstance[event.which]
        sdlDataLock.unlock()
        guard !isGC, let port else { return }

        let axis = Int(event.axis)
        if axis == 4 {
            let pressed = event.value > Self.triggerThreshold
            dispatchButton(retroID: 12, player: port, pressed: pressed)
            dispatchAnalogButton(retroID: 12, value: event.value, player: port)
            return
        }
        if axis == 5 {
            let pressed = event.value > Self.triggerThreshold
            dispatchButton(retroID: 13, player: port, pressed: pressed)
            dispatchAnalogButton(retroID: 13, value: event.value, player: port)
            return
        }

        let dz = Int32(Self.deadzone)
        if axis == 0 {
            setNavButton(.leftStickLeft, pressed: event.value < -dz)
            setNavButton(.leftStickRight, pressed: event.value > dz)
        } else if axis == 1 {
            setNavButton(.leftStickUp, pressed: event.value < -dz)
            setNavButton(.leftStickDown, pressed: event.value > dz)
        } else if axis == 2 {
            setNavButton(.rightStickLeft, pressed: event.value < -dz)
            setNavButton(.rightStickRight, pressed: event.value > dz)
        } else if axis == 3 {
            setNavButton(.rightStickUp, pressed: event.value < -dz)
            setNavButton(.rightStickDown, pressed: event.value > dz)
        }

        guard let (index, id) = Self.joystickAxisMap[axis] else { return }
        dispatchAnalog(index: index, id: id, value: event.value, player: port)
    }

    private nonisolated func handleJoyHatEvent(_ event: SDL_JoyHatEvent) {
        let hat = event.value
        setNavButton(.dpadUp, pressed: (hat & UInt8(SDL_HAT_UP)) != 0)
        setNavButton(.dpadDown, pressed: (hat & UInt8(SDL_HAT_DOWN)) != 0)
        setNavButton(.dpadLeft, pressed: (hat & UInt8(SDL_HAT_LEFT)) != 0)
        setNavButton(.dpadRight, pressed: (hat & UInt8(SDL_HAT_RIGHT)) != 0)
        if event.value != 0 {
            sdlDataLock.lock()
            let capID = captureInstanceID
            let cb = captureCallback
            if capID != nil { captureInstanceID = nil; captureCallback = nil }
            sdlDataLock.unlock()

            if event.which == capID, let cb = cb {
                if (hat & UInt8(SDL_HAT_UP)) != 0 { cb(11, "D-Pad Up") }
                else if (hat & UInt8(SDL_HAT_DOWN)) != 0 { cb(12, "D-Pad Down") }
                else if (hat & UInt8(SDL_HAT_LEFT)) != 0 { cb(13, "D-Pad Left") }
                else if (hat & UInt8(SDL_HAT_RIGHT)) != 0 { cb(14, "D-Pad Right") }
                return
            }
        }

        sdlDataLock.lock()
        let isGC = joystickIsGameController.contains(event.which)
        let port = portForInstance[event.which]
        sdlDataLock.unlock()
        guard !isGC, let port else { return }

        dispatchButton(retroID: 4, player: port, pressed: (hat & UInt8(SDL_HAT_UP)) != 0)
        dispatchButton(retroID: 5, player: port, pressed: (hat & UInt8(SDL_HAT_DOWN)) != 0)
        dispatchButton(retroID: 6, player: port, pressed: (hat & UInt8(SDL_HAT_LEFT)) != 0)
        dispatchButton(retroID: 7, player: port, pressed: (hat & UInt8(SDL_HAT_RIGHT)) != 0)
    }

    // MARK: - Input Dispatch

    private nonisolated func dispatchButton(retroID: Int, player: Int, pressed: Bool) {
        weak var runner: EmulatorRunner?
        runnerLock.lock()
        runner = _activeRunner
        runnerLock.unlock()

        guard let runner else { return }
        Task { @MainActor in
            // Ignore controller input while the gamepad toolbar overlay is open
            // so presses aren't double-handled by the game.
            if GamepadNavigationManager.shared.isGamepadToolbarActive { return }
            runner.setKeyState(retroID: retroID, player: player, pressed: pressed)
        }
    }

    private nonisolated func dispatchAnalog(index: Int, id: Int, value: Int16, player: Int) {
        let value = Int32(value)
        Task { @MainActor in
            // Ignore controller input while the gamepad toolbar overlay is open
            // so presses aren't double-handled by the game.
            if GamepadNavigationManager.shared.isGamepadToolbarActive { return }
            XPCBridgeAdapter.shared.setAnalogState(index, id: id, value: value, player: player)
        }
    }

    private nonisolated func dispatchAnalogButton(retroID: Int, value: Int16, player: Int) {
        let value = Int32(value)
        Task { @MainActor in
            if GamepadNavigationManager.shared.isGamepadToolbarActive { return }
            XPCBridgeAdapter.shared.setAnalogButtonState(retroID: retroID, value: value, player: player)
        }
    }

    // MARK: - Thread-safe Query Methods

    func connectedSDLInstanceIDs() -> [Int32] {
        sdlDataLock.lock()
        let ids = Array(gameControllers.keys) + Array(joysticks.keys)
        sdlDataLock.unlock()
        return ids
    }

    func sdlControllerName(for instanceID: Int32) -> String? {
        sdlDataLock.lock()
        defer { sdlDataLock.unlock() }

        if let controller = gameControllers[instanceID] {
            if let name = SDL_GameControllerName(controller) {
                return String(cString: name)
            }
            return nil
        }
        if let joystick = joysticks[instanceID] {
            if let name = SDL_JoystickName(joystick) {
                return String(cString: name)
            }
            return nil
        }
        return nil
    }

    func sdlVendorName(for instanceID: Int32) -> String {
        sdlControllerName(for: instanceID) ?? "SDL Controller"
    }

    func sdlControllerGUID(for instanceID: Int32) -> String? {
        sdlDataLock.lock()
        defer { sdlDataLock.unlock() }

        let joystick: OpaquePointer?
        if let controller = gameControllers[instanceID] {
            joystick = SDL_GameControllerGetJoystick(controller)
        } else {
            joystick = joysticks[instanceID]
        }
        guard let joy = joystick else { return nil }

        var guid: SDL_JoystickGUID = SDL_JoystickGetGUID(joy)
        return Self.formatGUID(&guid)
    }

    func sdlVendorProductID(for instanceID: Int32) -> (vendor: UInt16, product: UInt16)? {
        sdlDataLock.lock()
        defer { sdlDataLock.unlock() }

        let joystick: OpaquePointer?
        if let controller = gameControllers[instanceID] {
            joystick = SDL_GameControllerGetJoystick(controller)
        } else {
            joystick = joysticks[instanceID]
        }
        guard let joy = joystick else { return nil }

        let vendor = SDL_JoystickGetVendor(joy)
        let product = SDL_JoystickGetProduct(joy)
        if vendor == 0 && product == 0 { return nil }
        return (UInt16(vendor), UInt16(product))
    }

    private static func formatGUID(_ guid: inout SDL_JoystickGUID) -> String {
        return withUnsafeBytes(of: &guid) { rawBuf -> String in
            let bytes = Array(rawBuf)
            return bytes.map { String(format: "%02X", $0) }.joined()
        }
    }

    // MARK: - Capture Callback (lock-based, not dispatched to sdlQueue)

    func startCapture(instanceID: Int32, callback: @escaping (Int, String) -> Void) {
        sdlDataLock.lock()
        captureInstanceID = instanceID
        captureCallback = callback
        sdlDataLock.unlock()
    }

    func stopCapture() {
        sdlDataLock.lock()
        captureInstanceID = nil
        captureCallback = nil
        sdlDataLock.unlock()
    }
}
