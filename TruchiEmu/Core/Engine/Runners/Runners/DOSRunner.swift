import MetalKit
import Foundation
import SwiftUI
import GameController

class DOSRunner: EmulatorRunner, @unchecked Sendable {

    // MARK: - DOS-Specific Configuration

    private var cyclesSetting: String {
        AppSettings.get("dosbox_pure_cycles", type: String.self) ?? "auto"
    }

    @MainActor @Published var isMouseMode: Bool = false

    override func stop() {
        analogMouseTimer?.invalidate()
        analogMouseTimer = nil
        super.stop()
    }

    // MARK: - Launch Override

    @MainActor
    override func launch(rom: ROM, coreID: String, shaderUniformOverrides: [String: Float] = [:]) {
        LoggerService.info(category: "DOSRunner", "Launching DOS game: \(rom.name), cycles: \(cyclesSetting)")

        configureCoreOptions()

        super.launch(rom: rom, coreID: coreID, shaderUniformOverrides: shaderUniformOverrides)

        if let window = self.window, !InputCaptureManager.shared.isCapturing {
            InputCaptureManager.shared.startCapture(window: window)
        }

        configureAnalogMouse()
    }

    // MARK: - Core Options Configuration

    private func configureCoreOptions() {
        let cycles = cyclesSetting
        AppSettings.set("dosbox_pure_cycles", value: cycles)
        AppSettings.setBool("dosbox_pure_start_menu", value: true)
        AppSettings.setBool("dosbox_pure_mouse", value: true)
    }

    // MARK: - Analog Mouse Configuration

    @MainActor
    private func configureAnalogMouse() {
        let sysID = "dos"
        let systemDefault = AppSettings.getBool("analogMouse_enabled_\(sysID)", defaultValue: true)
        let enabled = rom?.settings.analogMouseEnabled ?? systemDefault

        isMouseMode = enabled

        if enabled {
            let sensitivity = Float(AppSettings.getDouble("analogMouse_sensitivity_\(sysID)", defaultValue: 0.8))
            let deadZone = Float(AppSettings.getDouble("analogMouse_deadZone_\(sysID)", defaultValue: 0.15))
            let stickString = AppSettings.getString("analogMouse_stick_\(sysID)", defaultValue: "left") ?? "left"
            let stickIndex = stickString == "right" ? 1 : 0

            XPCBridgeAdapter.shared.setAnalogMouseConfig(player: 0, enabled: true, sensitivity: sensitivity, deadzone: deadZone, stickIndex: stickIndex)

            analogMouseButtonLeft = AppSettings.getString("analogMouse_buttonLeft_\(sysID)", defaultValue: "a") ?? "a"
            analogMouseButtonDownRight = AppSettings.getString("analogMouse_buttonRight_\(sysID)", defaultValue: "b") ?? "b"
            analogMouseButtonDownMiddle = AppSettings.getString("analogMouse_buttonMiddle_\(sysID)", defaultValue: "x") ?? "x"

            LoggerService.info(category: "DOSRunner", "Analog mouse enabled: sensitivity=\(sensitivity), deadZone=\(deadZone), stick=\(stickString), left=\(analogMouseButtonLeft), right=\(analogMouseButtonDownRight), middle=\(analogMouseButtonDownMiddle)")
        } else {
            XPCBridgeAdapter.shared.setAnalogMouseConfig(player: 0, enabled: false, sensitivity: 0.8, deadzone: 0.15, stickIndex: 0)
            #if LOG_DEBUG
            LoggerService.debug(category: "DOSRunner", "Analog mouse disabled")
            #endif
        }
    }

    // MARK: - Mouse Mode Toggle

    @MainActor func toggleMouseMode() {
        isMouseMode.toggle()
        if isMouseMode {
            let sysID = "dos"
            let sensitivity = Float(AppSettings.getDouble("analogMouse_sensitivity_\(sysID)", defaultValue: 0.8))
            let deadZone = Float(AppSettings.getDouble("analogMouse_deadZone_\(sysID)", defaultValue: 0.15))
            let stickString = AppSettings.getString("analogMouse_stick_\(sysID)", defaultValue: "left") ?? "left"
            let stickIndex = stickString == "right" ? 1 : 0
            XPCBridgeAdapter.shared.setAnalogMouseConfig(player: 0, enabled: true, sensitivity: sensitivity, deadzone: deadZone, stickIndex: stickIndex)
        } else {
            XPCBridgeAdapter.shared.setAnalogMouseConfig(player: 0, enabled: false, sensitivity: 0.8, deadzone: 0.15, stickIndex: 0)
        }
        #if LOG_DEBUG
        LoggerService.debug(category: "DOSRunner", "Mouse mode: \(isMouseMode ? "ON" : "OFF")")
        #endif
    }

    // MARK: - DOS-Specific Input Handling

    @MainActor
    override func setupGamepadInput() {
        super.setupGamepadInput()

        let sysID = "dos"
        let systemDefault = AppSettings.getBool("analogMouse_enabled_\(sysID)", defaultValue: true)
        let analogMouseEnabled = rom?.settings.analogMouseEnabled ?? systemDefault
        guard analogMouseEnabled else { return }

        let cs = ControllerService.shared
        let sensitivity = Float(AppSettings.getDouble("analogMouse_sensitivity_\(sysID)", defaultValue: 0.8))
        let deadZone = Float(AppSettings.getDouble("analogMouse_deadZone_\(sysID)", defaultValue: 0.15))
        let stickString = AppSettings.getString("analogMouse_stick_\(sysID)", defaultValue: "left") ?? "left"

        for player in cs.connectedControllers {
            guard let controller = player.gcController,
                  let extendedGamepad = controller.extendedGamepad else { continue }
            let mapping = cs.mapping(for: controller.vendorName ?? "Unknown", systemID: sysID)
            let ports = player.assignedPlayers.map { $0 - 1 }
            let dpad = extendedGamepad.dpad

            let primaryStick = stickString == "right" ? extendedGamepad.rightThumbstick : extendedGamepad.leftThumbstick
            let secondaryStick = stickString == "right" ? extendedGamepad.leftThumbstick : extendedGamepad.rightThumbstick

            setupAnalogMouseTimer(primaryStick: primaryStick, secondaryStick: secondaryStick,
                                  sensitivity: sensitivity, deadZone: deadZone)

            extendedGamepad.valueChangedHandler = { [weak self] _, element in
                guard let self = self else { return }
                if GameGuideViewModel.isGuideSidebarOpen,
                   let btn = element as? GCControllerButtonInput {
                    #if LOG_DEBUG
                    LoggerService.debug(category: "DOSRunner", "Sidebar button: element=\(element.localizedName) isPressed=\(btn.isPressed) btnA=\(btn === extendedGamepad.buttonA) btnB=\(btn === extendedGamepad.buttonB)")
                    #endif
                    if btn === extendedGamepad.buttonA {
                        LoggerService.info(category: "DOSRunner", "A button → left click down=\(btn.isPressed)")
                        self.postMacMouseClick(button: .left, down: btn.isPressed)
                        return
                    }
                    if btn === extendedGamepad.buttonB {
                        LoggerService.info(category: "DOSRunner", "B button → right click down=\(btn.isPressed)")
                        self.postMacMouseClick(button: .right, down: btn.isPressed)
                        return
                    }
                    if btn === extendedGamepad.buttonX || btn === extendedGamepad.buttonY {
                        LoggerService.info(category: "DOSRunner", "X/Y button → left click down=\(btn.isPressed)")
                        self.postMacMouseClick(button: .left, down: btn.isPressed)
                        return
                    }
                }
                for port in ports {
                    self.handleDOSButtons(element, in: mapping, player: port, dpad: dpad)
                }
            }
        }
    }

    private func handleDOSButtons(_ element: GCControllerElement, in mapping: ControllerGamepadMapping, player: Int, dpad: GCControllerDirectionPad) {
        if let dirPad = element as? GCControllerDirectionPad {
            if dirPad === dpad {
                XPCBridgeAdapter.shared.dispatchKeyboardEvent(keycode: 273, character: 0, modifiers: 0, down: dpad.up.isPressed)
                XPCBridgeAdapter.shared.dispatchKeyboardEvent(keycode: 274, character: 0, modifiers: 0, down: dpad.down.isPressed)
                XPCBridgeAdapter.shared.dispatchKeyboardEvent(keycode: 275, character: 0, modifiers: 0, down: dpad.right.isPressed)
                XPCBridgeAdapter.shared.dispatchKeyboardEvent(keycode: 276, character: 0, modifiers: 0, down: dpad.left.isPressed)
            }
            return
        }

        guard let btn = element as? GCControllerButtonInput else { return }
        for (retroBtn, btnMapping) in mapping.buttons {
            guard elementMatches(element, name: btnMapping.gcElementName) else { continue }
            let raw = retroBtn.rawValue

            if retroBtn == .r3 || retroBtn == .l3 {
                handleGuideToggleButton(retroBtn: retroBtn, pressed: btn.isPressed, systemID: "dos")
                break
            }

            if retroBtn == .start {
                XPCBridgeAdapter.shared.dispatchKeyboardEvent(keycode: 13, character: 13, modifiers: 0, down: btn.isPressed)
                break
            }
            if retroBtn == .select {
                XPCBridgeAdapter.shared.dispatchKeyboardEvent(keycode: 32, character: 32, modifiers: 0, down: btn.isPressed)
                break
            }

            handleAnalogMouseButton(raw, pressed: btn.isPressed)
            break
        }
    }

    // MARK: - Disk Control for Multi-Disc Games

    func loadDisk(imagePath: String) {
        LoggerService.info(category: "DOSRunner", "Loading disk image: \(imagePath)")
    }

    var currentDiskIndex: Int { return 0 }
    var totalDisks: Int { return 1 }
}
