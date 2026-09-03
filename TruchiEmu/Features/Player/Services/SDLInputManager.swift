import Foundation
import AppKit
import GameController

extension Notification.Name {
    static let sdlControllerConnected = Notification.Name("sdlControllerConnected")
    static let sdlControllerDisconnected = Notification.Name("sdlControllerDisconnected")

    /// Posted by `ControllerInputObserver.stopObserving` when it releases
    /// its `valueChangedHandler` chains on a `GCController` and the SDL
    /// axis/button observers. Listeners (e.g. `StickVisualizerView`) re-run
    /// their attach logic on receipt, since the handler slots are
    /// persistent on the controller and the observer stomps them on
    /// every open/close.
    static let controllerInputObserverStopped = Notification.Name("controllerInputObserverStopped")
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

    // Live axis observer for the settings stick visualizer. Single-slot:
    // only the currently-selected controller's axes are observed, mirroring
    // the single-selection model of the controller settings UI.
    private nonisolated(unsafe) var axisObserverCallback: ((Int32, Float, Float, Float, Float) -> Void)?
    private nonisolated(unsafe) var axisObserverInstanceID: Int32?
    private nonisolated(unsafe) var observedAxes: [Int32: (lX: Float, lY: Float, rX: Float, rY: Float)] = [:]

    // Live button observer for the controller test sheet. Single-slot:
    // only the currently-selected controller's buttons are observed. The
    // callback receives the generic `PadButton` (mapped from SDL button
    // index) and whether the button is pressed; unrecognized indices yield
    // `nil` so the caller can ignore them.
    private nonisolated(unsafe) var buttonObserverCallback: ((Int32, PadButton?, Bool) -> Void)?
    private nonisolated(unsafe) var buttonObserverInstanceID: Int32?

    // Live trigger observer for the controller test sheet. Reports the
    // normalized `0...1` value of L2/R2 (axis 4/5 on recognized controllers)
    // each time SDL fires an axis event. The test sheet uses this to draw
    // the trigger bar fill.
    private nonisolated(unsafe) var triggerObserverCallback: ((Int32, PadButton, Float) -> Void)?
    private nonisolated(unsafe) var triggerObserverInstanceID: Int32?

    // SDL share button index cached at runner registration. The same
    // physical button dispatches single-press vs long-press ShareBehaviors
    // via the long-press detector (BaseRunner.handleSharePress).
    nonisolated(unsafe) var cachedShareButtonIndex: Int? = nil

    // Active runner's systemID cached at runner registration, used to
    // resolve per-system SDL deadzone mappings on the SDL thread. Mirrors
    // the cachedShareButtonIndex precedent. Falls back to "default" when
    // no runner is registered (e.g. while in the settings UI).
    private nonisolated(unsafe) var cachedActiveSystemID: String? = nil

    // Pollable snapshot of currently-pressed buttons, keyed by the app's
    // GamepadNavButton vocabulary, so GamepadNavigationManager can drive UI
    // navigation (and button combos like L3+R3) for controllers that SDL
    // handles as raw joysticks and never exposes as GCController instances.
    nonisolated(unsafe) private var navButtonState: [GamepadNavButton: Bool] = [:]
    private let navStateLock = NSLock()

    private nonisolated static let deadzone: Int16 = 8000
    private nonisolated static let triggerThreshold: Int16 = 16384

    // Known USB vendor IDs for controllers that GCController handles natively
    // on macOS. When an SDL-recognized game controller matches one of these,
    // we skip opening it — GCController already routes its input, and opening
    // it via SDL would create a duplicate controller entry and double-input.
    private nonisolated static let gcControllerVendors: Set<UInt16> = [
        0x045E, // Microsoft (Xbox One / Series X|S)
        0x054C, // Sony (DualSense / DualShock 4)
        0x057E, // Nintendo (Switch Pro Controller — macOS 13+)
        0x0F0D, // HORI (MFi)
        0x20D6, // PowerA (MFi)
        0x0738, // Mad Catz
        0x0E6F, // PDP
        0x1A79, // Various MFi
    ]

    private nonisolated static func isKnownGCVendor(vendorID: UInt16) -> Bool {
        gcControllerVendors.contains(vendorID)
    }

    // Check whether this SDL controller is already handled by GCController.
    // macOS can recognise controllers (e.g. 8BitDo) whose vendor ID isn't in
    // gcControllerVendors. Since GCController doesn't expose USB identifiers
    // on macOS, we match on the HID device name — both APIs read the same
    // descriptor, so the same physical device reports the same string.
    private nonisolated func isDuplicateGCController(sdlName: String) -> Bool {
        GCController.controllers().contains { $0.vendorName == sdlName }
    }


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

    // SDL game-controller button enum index → generic pad button (used by the
    // controller test sheet to highlight physical buttons on the rendered pad).
    // Note: SDL has no separate share button; share = back/select on most pads.
    private nonisolated static let sdlControllerPadMap: [Int32: PadButton] = [
        SDL_CONTROLLER_BUTTON_A.rawValue: .a,
        SDL_CONTROLLER_BUTTON_B.rawValue: .b,
        SDL_CONTROLLER_BUTTON_X.rawValue: .x,
        SDL_CONTROLLER_BUTTON_Y.rawValue: .y,
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

    // Raw joystick button index → generic pad button (used for unrecognized
    // controllers handled via the SDL_JOYBUTTON* fallback events). Standard
    // HID gamepad layout: 0=A, 1=B, 2=X, 3=Y, 4=LB, 5=RB, 6=LT, 7=RT,
    // 8=Select, 9=Start, 10=L3, 11=R3.
    private nonisolated static let joystickPadMap: [Int: PadButton] = [
        0: .a, 1: .b, 2: .x, 3: .y,
        4: .l1, 5: .r1, 6: .l2, 7: .r2,
        8: .select, 9: .start, 10: .l3, 11: .r3,
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
        cachedActiveSystemID = sysID
    }

    func unregisterRunner() {
        runnerLock.lock()
        _activeRunner = nil
        runnerLock.unlock()
        cachedActiveSystemID = nil
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

        if SDL_IsGameController(deviceIndex) == SDL_TRUE {
            // Open the controller with SDL_GameController so we can read its
            // vendor/product IDs. If GCController already handles this device,
            // close the SDL handle and skip it — otherwise the controller
            // appears twice in the UI and SDL dispatches duplicate input
            // alongside GCController's path.
            guard let controller = SDL_GameControllerOpen(deviceIndex) else {
                let err = String(cString: SDL_GetError())
                LoggerService.warning(category: "SDL", "Failed to open game controller: \(err)")
                return
            }
            let joystick = SDL_GameControllerGetJoystick(controller)
            let instanceID = SDL_JoystickInstanceID(joystick)
            let vendor = SDL_JoystickGetVendor(joystick)
            let product = SDL_JoystickGetProduct(joystick)

            let sdlName: String? = SDL_GameControllerName(controller).map { String(cString: $0) }
            let isKnownGCVendor = vendor != 0 && Self.isKnownGCVendor(vendorID: vendor)
            let isGCCDuplicate = sdlName != nil && isDuplicateGCController(sdlName: sdlName!)

            if isKnownGCVendor || isGCCDuplicate {
                let version = SDL_JoystickGetProductVersion(joystick)
                let serial = SDL_JoystickGetSerial(joystick).map { String(cString: $0) }
                var guid = SDL_JoystickGetGUID(joystick)
                let guidStr = Self.formatGUID(&guid)
                SDL_GameControllerClose(controller)
                if let name = sdlName {
                    LoggerService.info(category: "SDL", "Game controller '\(name)' (instance \(instanceID), vendor 0x\(String(format: "%04X", vendor)), product 0x\(String(format: "%04X", product)), version \(version)) skipped — GCController handles it. serial=\(serial ?? "nil") guid=\(guidStr)")
                } else {
                    LoggerService.info(category: "SDL", "Game controller (instance \(instanceID), vendor 0x\(String(format: "%04X", vendor)), product 0x\(String(format: "%04X", product)), version \(version)) skipped — GCController handles it. serial=\(serial ?? "nil") guid=\(guidStr)")
                }
                return
            }

            sdlDataLock.lock()
            gameControllers[instanceID] = controller
            joystickIsGameController.insert(instanceID)
            let port = assignPortLocked(for: instanceID)
            sdlDataLock.unlock()

            if let name = sdlName {
                LoggerService.info(category: "SDL", "Game controller '\(name)' (instance \(instanceID)) opened on port \(port)")
            } else {
                LoggerService.info(category: "SDL", "Game controller (instance \(instanceID)) opened on port \(port)")
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sdlControllerConnected, object: nil)
            }
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

        // If the disconnected controller was the active axis-observation
        // target, drop the observer so its closure doesn't dangle into a
        // destroyed SwiftUI view. The visualizer is rebuilt by
        // ControllerService.refreshConnectedControllers once the
        // disconnection notification fires.
        sdlDataLock.lock()
        observedAxes.removeValue(forKey: instanceID)
        if axisObserverInstanceID == instanceID {
            axisObserverInstanceID = nil
            axisObserverCallback = nil
        }
        sdlDataLock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sdlControllerDisconnected, object: nil)
        }
    }

    // Closes any open SDL game controller whose name is also reported by a
    // connected GCController. GCController can register a controller a moment
    // after SDL's poll loop has already accepted it (the connect race, which
    // is common on reconnect), leaving the device listed as both GCC and SDL.
    // Called from ControllerService on GC/SDL connect notifications so the
    // duplicate is removed regardless of which system registers the device
    // first.
    @MainActor
    func reconcileWithGCControllers() {
        let gcNames = Set(GCController.controllers().compactMap { $0.vendorName })
        guard !gcNames.isEmpty else { return }

        var toClose: [(instanceID: Int32, controller: OpaquePointer)] = []
        sdlDataLock.lock()
        for (instanceID, ctrl) in gameControllers {
            if let name = SDL_GameControllerName(ctrl).map({ String(cString: $0) }),
               gcNames.contains(name) {
                gameControllers.removeValue(forKey: instanceID)
                joystickIsGameController.remove(instanceID)
                portForInstance.removeValue(forKey: instanceID)
                toClose.append((instanceID, ctrl))
            }
        }
        sdlDataLock.unlock()

        guard !toClose.isEmpty else { return }
        sdlQueue.async {
            for item in toClose { SDL_GameControllerClose(item.controller) }
        }
        let instances = toClose.map { "\($0.instanceID)" }.joined(separator: ", ")
        LoggerService.info(category: "SDL", "Reconciled with GCController: closed \(toClose.count) duplicate SDL game controller(s) — instance \(instances)")
        NotificationCenter.default.post(name: .sdlControllerDisconnected, object: nil)
    }

    // Caller must hold sdlDataLock
    private nonisolated func assignPortLocked(for instanceID: Int32) -> Int {
        if let existing = portForInstance[instanceID] {
            return existing
        }
        let port = nextPort
        portForInstance[instanceID] = port
        nextPort += 1
        #if LOG_DEBUG
        LoggerService.debug(category: "SDL", "Assigned port \(port) to instance \(instanceID)")
        #endif
        return port
    }

    // MARK: - Game Controller Events

    private nonisolated func handleButtonEvent(_ event: SDL_ControllerButtonEvent, pressed: Bool) {
        if let navButton = Self.sdlControllerNavMap[Int32(event.button)] {
            setNavButton(navButton, pressed: pressed)
        }
        notifyButtonObserverIfMatched(instanceID: event.which, padButton: Self.sdlControllerPadMap[Int32(event.button)], pressed: pressed)
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
        guard let retroID = Self.buttonMap[Int32(event.button)], port != nil else { return }
        dispatchButton(retroID: retroID, instanceID: event.which, pressed: pressed)
    }

    private nonisolated func handleAxisEvent(_ event: SDL_ControllerAxisEvent) {
        notifyAxisObserverIfMatched(instanceID: event.which, axis: Int(event.axis), rawValue: event.value)
        notifyTriggerObserverIfMatched(instanceID: event.which, axis: Int(event.axis), rawValue: event.value)
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
        guard port != nil else { return }

        let axis = Int32(event.axis)
        if axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT.rawValue {
            let pressed = event.value > Self.triggerThreshold
            dispatchButton(retroID: 12, instanceID: event.which, pressed: pressed)
            dispatchAnalogButton(retroID: 12, value: event.value, instanceID: event.which)
            return
        }
        if axis == SDL_CONTROLLER_AXIS_TRIGGERRIGHT.rawValue {
            let pressed = event.value > Self.triggerThreshold
            dispatchButton(retroID: 13, instanceID: event.which, pressed: pressed)
            dispatchAnalogButton(retroID: 13, value: event.value, instanceID: event.which)
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
        dispatchAnalog(index: index, id: id, value: event.value, instanceID: event.which)
    }

    // MARK: - Raw Joystick Events (Fallback)

    private nonisolated func handleJoyButtonEvent(_ event: SDL_JoyButtonEvent, pressed: Bool) {
        if let navButton = Self.joystickNavMap[Int(event.button)] {
            setNavButton(navButton, pressed: pressed)
        }
        notifyButtonObserverIfMatched(instanceID: event.which, padButton: Self.joystickPadMap[Int(event.button)], pressed: pressed)
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

        guard !isGC, port != nil else { return }
        guard let retroID = Self.joystickButtonMap[Int(event.button)] else { return }
        dispatchButton(retroID: retroID, instanceID: event.which, pressed: pressed)
        if retroID == 12 || retroID == 13 {
            dispatchAnalogButton(retroID: retroID, value: pressed ? Int16.max : 0, instanceID: event.which)
        }
    }

    private nonisolated func handleJoyAxisEvent(_ event: SDL_JoyAxisEvent) {
        notifyAxisObserverIfMatched(instanceID: event.which, axis: Int(event.axis), rawValue: event.value)
        // Raw HID gamepad: axes 4/5 are L2/R2 in the standard layout (0-3 are sticks).
        // The button observer (handleJoyButtonEvent) already reports l2/r2 as
        // digital press when value crosses threshold; here we feed the analog
        // value so the test sheet can draw the trigger bar continuously.
        if event.axis == 4 || event.axis == 5 {
            let padButton: PadButton = event.axis == 4 ? .l2 : .r2
            sdlDataLock.lock()
            let obsID = triggerObserverInstanceID
            let cb = triggerObserverCallback
            sdlDataLock.unlock()
            if event.which == obsID, let cb {
                let normalized = max(0.0, min(1.0, Float(event.value) / 32768.0))
                cb(event.which, padButton, normalized)
            }
        }
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
        guard !isGC, port != nil else { return }

        let axis = Int(event.axis)
        if axis == 4 {
            let pressed = event.value > Self.triggerThreshold
            dispatchButton(retroID: 12, instanceID: event.which, pressed: pressed)
            dispatchAnalogButton(retroID: 12, value: event.value, instanceID: event.which)
            return
        }
        if axis == 5 {
            let pressed = event.value > Self.triggerThreshold
            dispatchButton(retroID: 13, instanceID: event.which, pressed: pressed)
            dispatchAnalogButton(retroID: 13, value: event.value, instanceID: event.which)
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
        dispatchAnalog(index: index, id: id, value: event.value, instanceID: event.which)
    }

    private nonisolated func handleJoyHatEvent(_ event: SDL_JoyHatEvent) {
        let hat = event.value
        #if LOG_DEBUG
        LoggerService.debug(category: "SDL", "handleJoyHatEvent which=\(event.which) hat=\(hat) (Up:\((hat & UInt8(SDL_HAT_UP)) != 0) Right:\((hat & UInt8(SDL_HAT_RIGHT)) != 0) Down:\((hat & UInt8(SDL_HAT_DOWN)) != 0) Left:\((hat & UInt8(SDL_HAT_LEFT)) != 0))")
        #endif
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
        guard !isGC, port != nil else { return }

        dispatchButton(retroID: 4, instanceID: event.which, pressed: (hat & UInt8(SDL_HAT_UP)) != 0)
        dispatchButton(retroID: 5, instanceID: event.which, pressed: (hat & UInt8(SDL_HAT_DOWN)) != 0)
        dispatchButton(retroID: 6, instanceID: event.which, pressed: (hat & UInt8(SDL_HAT_LEFT)) != 0)
        dispatchButton(retroID: 7, instanceID: event.which, pressed: (hat & UInt8(SDL_HAT_RIGHT)) != 0)
    }

    // MARK: - Input Dispatch

    private nonisolated func dispatchButton(retroID: Int, instanceID: Int32, pressed: Bool) {
        #if LOG_DEBUG
        LoggerService.debug(category: "SDL", "dispatchButton retroID=\(retroID) instanceID=\(instanceID) pressed=\(pressed)")
        #endif
        weak var runner: EmulatorRunner?
        runnerLock.lock()
        runner = _activeRunner
        runnerLock.unlock()

        guard let runner else { return }
        Task { @MainActor in
            if GamepadNavigationManager.shared.isGamepadToolbarActive { return }
            let player = resolvePlayerPort(for: instanceID)
            runner.setKeyState(retroID: retroID, player: player, pressed: pressed)
        }
    }

    private nonisolated func dispatchAnalog(index: Int, id: Int, value: Int16, instanceID: Int32) {
        let raw = Float(value) / 32768.0
        let sysID = cachedActiveSystemID ?? "default"
        Task { @MainActor in
            if GamepadNavigationManager.shared.isGamepadToolbarActive { return }

            let player = resolvePlayerPort(for: instanceID)

            let deadzone: Float
            let calibration: ControllerCalibration
            if let identity = ControllerService.shared.identityKey(forSDL: instanceID) {
                let m = ControllerService.shared.sdlMapping(forIdentity: identity, systemID: sysID)
                deadzone = index == 0 ? m.leftStickDeadzone : m.rightStickDeadzone
                calibration = ControllerService.shared.calibration(for: identity)
            } else {
                let vendor = SDLInputManager.shared.sdlVendorName(for: instanceID)
                let m = ControllerService.shared.sdlMapping(for: vendor, systemID: sysID)
                deadzone = index == 0 ? m.leftStickDeadzone : m.rightStickDeadzone
                calibration = ControllerService.shared.calibration(forSDL: instanceID)
            }

            // Apply stick range calibration before the deadzone remap. The Y
            // axis is inverted between SDL raw values (positive = down) and
            // the GC convention (positive = up) the calibration is captured
            // in, so convert there and back; the sign handed to the core is
            // preserved.
            let stickCal = index == 0 ? calibration.leftStick : calibration.rightStick
            let calibrated = id == 1 ? -stickCal.applyY(-raw) : stickCal.applyX(raw)

            let scaled = AnalogDeadZone(radial: deadzone, anti: 0.0).apply(calibrated)
            let retroValue = Int32(scaled * 32767.0)
            XPCBridgeAdapter.shared.setAnalogState(index, id: id, value: retroValue, player: player)
        }
    }

    private nonisolated func dispatchAnalogButton(retroID: Int, value: Int16, instanceID: Int32) {
        let value = Int32(value)
        Task { @MainActor in
            if GamepadNavigationManager.shared.isGamepadToolbarActive { return }
            let player = resolvePlayerPort(for: instanceID)
            XPCBridgeAdapter.shared.setAnalogButtonState(retroID: retroID, value: value, player: player)
        }
    }

    @MainActor
    private func resolvePlayerPort(for instanceID: Int32) -> Int {
        let slots = ControllerService.shared.sdlSlotAssignments[instanceID] ?? []
        return (slots.min() ?? 1) - 1
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

    private nonisolated static func formatGUID(_ guid: inout SDL_JoystickGUID) -> String {
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

    // MARK: - Live Axis Observation (settings stick visualizer)

    /// Register a single observer for live analog stick values of the given
    /// SDL instance ID. The callback receives normalized `[-1, 1]` floats
    /// `(leftX, leftY, rightX, rightY)` and is invoked on the SDL thread, so
    /// callers must hop to main themselves if they touch UI state.
    /// Replaces any previously-registered observer (single-slot design — only
    /// one controller is selected in the settings UI at a time).
    func startAxisObservation(instanceID: Int32, callback: @escaping (Float, Float, Float, Float) -> Void) {
        sdlDataLock.lock()
        axisObserverInstanceID = instanceID
        axisObserverCallback = { _, lX, lY, rX, rY in callback(lX, lY, rX, rY) }
        observedAxes[instanceID] = (0, 0, 0, 0)
        sdlDataLock.unlock()
    }

    func stopAxisObservation() {
        sdlDataLock.lock()
        let id = axisObserverInstanceID
        axisObserverInstanceID = nil
        axisObserverCallback = nil
        if let id { observedAxes.removeValue(forKey: id) }
        sdlDataLock.unlock()
    }

    // MARK: - Live Button Observation (controller test sheet)

    /// Register a single observer for live button press state of the given SDL
    /// instance ID. The callback receives `(instanceID, padButton, pressed)`.
    /// `padButton` is the generic Xbox-layout button (nil for unmapped indices).
    /// Replaces any previously-registered observer (single-slot).
    func startButtonObservation(instanceID: Int32, callback: @escaping (Int32, PadButton?, Bool) -> Void) {
        sdlDataLock.lock()
        buttonObserverInstanceID = instanceID
        buttonObserverCallback = callback
        sdlDataLock.unlock()
    }

    func stopButtonObservation() {
        sdlDataLock.lock()
        buttonObserverInstanceID = nil
        buttonObserverCallback = nil
        sdlDataLock.unlock()
    }

    /// Register a single observer for live trigger (L2/R2) values. Callback
    /// receives `(instanceID, padButton, normalized)` where `normalized` is
    /// `0...1`. Single-slot. The button and axis observers are independent
    /// and can be active together.
    func startTriggerObservation(instanceID: Int32, callback: @escaping (Int32, PadButton, Float) -> Void) {
        sdlDataLock.lock()
        triggerObserverInstanceID = instanceID
        triggerObserverCallback = callback
        sdlDataLock.unlock()
    }

    func stopTriggerObservation() {
        sdlDataLock.lock()
        triggerObserverInstanceID = nil
        triggerObserverCallback = nil
        sdlDataLock.unlock()
    }

    /// Invoked from both SDL button paths (recognized game controllers and raw
    /// joysticks) so the test sheet sees live press state for the observed
    /// controller. Trigger axes (LT/RT) are reported as `l2`/`r2` by the axis
    /// path, not here, so the digital-button press map stays accurate.
    private nonisolated func notifyButtonObserverIfMatched(instanceID: Int32, padButton: PadButton?, pressed: Bool) {
        sdlDataLock.lock()
        let obsID = buttonObserverInstanceID
        let cb = buttonObserverCallback
        sdlDataLock.unlock()
        guard instanceID == obsID, let cb else { return }
        cb(instanceID, padButton, pressed)
    }

    /// Invoked from both SDL axes paths to feed trigger values (axis 4/5) to
    /// the test sheet's trigger bar. Sticks (axes 0-3) are ignored here — the
    /// axis observer handles those.
    private nonisolated func notifyTriggerObserverIfMatched(instanceID: Int32, axis: Int, rawValue: Int16) {
        let padButton: PadButton
        switch axis {
        case Int(SDL_CONTROLLER_AXIS_TRIGGERLEFT.rawValue): padButton = .l2
        case Int(SDL_CONTROLLER_AXIS_TRIGGERRIGHT.rawValue): padButton = .r2
        default: return
        }
        sdlDataLock.lock()
        let obsID = triggerObserverInstanceID
        let cb = triggerObserverCallback
        sdlDataLock.unlock()
        guard instanceID == obsID, let cb else { return }
        let normalized = max(0.0, min(1.0, Float(rawValue) / 32768.0))
        cb(instanceID, padButton, normalized)
    }

    /// Invoked from both SDL axes paths (recognized game controllers and raw
    /// joysticks) before any capture/dispatch gating, so the visualizer sees
    /// raw axis data even when the gamepad toolbar overlay is open. Maps
    /// SDL axis → (leftX=0, leftY=1, rightX=2, rightY=3); other axes are
    /// ignored. The Y axes are negated to match the GCController convention
    /// (Y-positive-up) that the stick visualizer consumes; the gameplay
    /// dispatch path is unaffected since libretro interprets the Y sign itself.
    private nonisolated func notifyAxisObserverIfMatched(instanceID: Int32, axis: Int, rawValue: Int16) {
        sdlDataLock.lock()
        let obsID = axisObserverInstanceID
        let cb = axisObserverCallback
        sdlDataLock.unlock()
        guard instanceID == obsID, let cb, axis >= 0, axis <= 3 else { return }
        let normalized = Float(rawValue) / 32768.0
        var state = observedAxes[instanceID] ?? (0, 0, 0, 0)
        switch axis {
        case 0: state.lX = normalized
        case 1: state.lY = -normalized
        case 2: state.rX = normalized
        default: state.rY = -normalized
        }
        observedAxes[instanceID] = state
        cb(instanceID, state.lX, state.lY, state.rX, state.rY)
    }
}
