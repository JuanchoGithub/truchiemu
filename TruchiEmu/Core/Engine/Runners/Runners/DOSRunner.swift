import MetalKit
import Foundation
import SwiftUI
import GameController

// DOS-specific emulator runner using DOSBox-Pure.
//
// DOSBox-Pure is designed to work with ZIP files directly, providing:
// - Automatic C: drive mounting from ZIP contents
// - Built-in "Start Menu" for selecting executables
// - Game controller auto-mapping (arrows, space, ctrl, alt)
// - Mouse mode support for point-and-click adventures
// - Save state support via Libretro API
class DOSRunner: EmulatorRunner, @unchecked Sendable {

    // MARK: - DOS-Specific Configuration

    private var cyclesSetting: String {
        AppSettings.get("dosbox_pure_cycles", type: String.self) ?? "auto"
    }

    @MainActor @Published var isMouseMode: Bool = false

    private var analogMouseButtonLeft: String = "a"
    private var analogMouseButtonDownRight: String = "b"
    private var analogMouseButtonDownMiddle: String = "x"
    private var analogMouseTimer: Timer?

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
        let enabled = AppSettings.getBool("analogMouse_enabled_\(sysID)", defaultValue: false)

        isMouseMode = enabled

        if enabled {
            let sensitivity = Float(AppSettings.getDouble("analogMouse_sensitivity_\(sysID)", defaultValue: 1.0))
            let deadZone = Float(AppSettings.getDouble("analogMouse_deadZone_\(sysID)", defaultValue: 0.15))
            let stickString = AppSettings.getString("analogMouse_stick_\(sysID)", defaultValue: "left") ?? "left"
            let stickIndex = stickString == "right" ? 1 : 0

            XPCBridgeAdapter.shared.setAnalogMouseConfig(player: 0, enabled: true, sensitivity: sensitivity, deadzone: deadZone, stickIndex: stickIndex)

            analogMouseButtonLeft = AppSettings.getString("analogMouse_buttonLeft_\(sysID)", defaultValue: "a") ?? "a"
            analogMouseButtonDownRight = AppSettings.getString("analogMouse_buttonRight_\(sysID)", defaultValue: "b") ?? "b"
            analogMouseButtonDownMiddle = AppSettings.getString("analogMouse_buttonMiddle_\(sysID)", defaultValue: "x") ?? "x"

            LoggerService.info(category: "DOSRunner", "Analog mouse enabled: sensitivity=\(sensitivity), deadZone=\(deadZone), stick=\(stickString), left=\(analogMouseButtonLeft), right=\(analogMouseButtonDownRight), middle=\(analogMouseButtonDownMiddle)")
        } else {
            XPCBridgeAdapter.shared.setAnalogMouseConfig(player: 0, enabled: false, sensitivity: 1.0, deadzone: 0.15, stickIndex: 0)
            LoggerService.debug(category: "DOSRunner", "Analog mouse disabled")
        }
    }

    // MARK: - Mouse Mode Toggle

    @MainActor func toggleMouseMode() {
        isMouseMode.toggle()
        XPCBridgeAdapter.shared.setAnalogMouseConfig(player: 0, enabled: isMouseMode, sensitivity: 1.0, deadzone: 0.15, stickIndex: 0)
        LoggerService.debug(category: "DOSRunner", "Mouse mode: \(isMouseMode ? "ON" : "OFF")")
    }

    // MARK: - DOS-Specific Input Handling

    @MainActor
    override func setupGamepadInput() {
        super.setupGamepadInput()

        let sysID = "dos"
        let analogMouseEnabled = AppSettings.getBool("analogMouse_enabled_\(sysID)", defaultValue: false)
        guard analogMouseEnabled else { return }

        let cs = ControllerService.shared
        let sensitivity = Float(AppSettings.getDouble("analogMouse_sensitivity_\(sysID)", defaultValue: 1.0))
        let deadZone = Float(AppSettings.getDouble("analogMouse_deadZone_\(sysID)", defaultValue: 0.15))
        let stickString = AppSettings.getString("analogMouse_stick_\(sysID)", defaultValue: "left") ?? "left"

        for player in cs.connectedControllers {
            guard let controller = player.gcController,
                  let extendedGamepad = controller.extendedGamepad else { continue }
            let mapping = cs.mapping(for: controller.vendorName ?? "Unknown", systemID: sysID)
            let ports = player.assignedPlayers.map { $0 - 1 }

            let stick = stickString == "right" ? extendedGamepad.rightThumbstick : extendedGamepad.leftThumbstick
            let secondaryStick = stickString == "right" ? extendedGamepad.leftThumbstick : extendedGamepad.rightThumbstick

            analogMouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                guard self != nil else { return }
                var xVal = stick.xAxis.value
                var yVal = stick.yAxis.value
                if fabsf(xVal) < deadZone { xVal = 0 }
                if fabsf(yVal) < deadZone { yVal = 0 }
                var dx = Int16(xVal * sensitivity * 8.0)
                var dy = Int16(-yVal * sensitivity * 8.0)

                let x2 = secondaryStick.xAxis.value
                let y2 = secondaryStick.yAxis.value
                if fabsf(x2) >= deadZone { dx += Int16(x2 * sensitivity * 8.0 * 0.2) }
                if fabsf(y2) >= deadZone { dy += Int16(-y2 * sensitivity * 8.0 * 0.2) }

                XPCBridgeAdapter.shared.setAnalogMouseDeltaX(dx, y: dy)
            }

            extendedGamepad.valueChangedHandler = { [weak self] _, element in
                guard let self = self else { return }
                for port in ports {
                    self.handleDOSButtons(element, in: mapping, player: port)
                }
            }
        }
    }

    private func handleDOSButtons(_ element: GCControllerElement, in mapping: ControllerGamepadMapping, player: Int) {
        if let dpad = element as? GCControllerDirectionPad {
            updateGamepadButton(dpad.up, in: mapping, player: player)
            updateGamepadButton(dpad.down, in: mapping, player: player)
            updateGamepadButton(dpad.left, in: mapping, player: player)
            updateGamepadButton(dpad.right, in: mapping, player: player)
            updateGamepadButton(dpad, in: mapping, player: player)

            setKeyState(retroID: 4, player: player, pressed: dpad.up.isPressed)
            setKeyState(retroID: 5, player: player, pressed: dpad.down.isPressed)
            setKeyState(retroID: 6, player: player, pressed: dpad.left.isPressed)
            setKeyState(retroID: 7, player: player, pressed: dpad.right.isPressed)
        } else {
            updateGamepadButton(element, in: mapping, player: player)
        }

        guard let btn = element as? GCControllerButtonInput else { return }
        for (retroBtn, btnMapping) in mapping.buttons {
            guard elementMatches(element, name: btnMapping.gcElementName) else { continue }
            let raw = retroBtn.rawValue
            if raw == analogMouseButtonLeft {
                XPCBridgeAdapter.shared.setMouseButton(0, pressed: btn.isPressed)
            }
            if raw == analogMouseButtonDownRight {
                XPCBridgeAdapter.shared.setMouseButton(1, pressed: btn.isPressed)
            }
            if raw == analogMouseButtonDownMiddle {
                XPCBridgeAdapter.shared.setMouseButton(2, pressed: btn.isPressed)
            }

            let name = btn.localizedName ?? ""
            if name.contains("A") || name.contains("X") {
                setKeyState(retroID: 13, player: player, pressed: btn.isPressed)
            } else if name.contains("B") || name.contains("Circle") {
                setKeyState(retroID: 44, player: player, pressed: btn.isPressed)
            }
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