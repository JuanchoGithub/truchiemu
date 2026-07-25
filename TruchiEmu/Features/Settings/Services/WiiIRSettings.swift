import Foundation
import Combine
import SwiftUI

// MARK: - Wii IR Settings

/// Persists Wiimote IR calibration settings to a per-system `.cfg` file in the
/// CoreOverride directory. Reads back at launch via `applyPersistedOverrides()`
/// which feeds them to the Dolphin libretro core options.
///
/// @Published state drives SwiftUI bindings; on every set the live Dolphin
/// core is also notified so option changes take effect without relaunching.
@MainActor
final class WiiIRSettings: ObservableObject {
    static let shared = WiiIRSettings()

    static let dolphinCoreID = "dolphin_libretro"

    /// Bundled defaults baked into `dolphin_libretro_default.json`. Mirrored
    /// here so the UI can show them and "reset" can restore them.
    /// NOTE: Dolphin core stores these as STRINGIFIED INTEGERS — the libretro
    /// Option<>::Updated() lookup compares the var.value (the frontend's
    /// selection) against the OPTION VALUE, not the display label. So the
    /// raw string we write must be "0" / "1" / "2" / etc., never the label.
    enum Defaults {
        // String values written to / read from the core option CFG
        static let irModeValue = "2"           // Mouse controls pointer
        static let sensorBarPositionValue = "1" // Top
        static let yawValue = "7"
        static let pitchValue = "7"
        static let verticalOffsetValue = "0"  // Dolphin center is 0

        // Integer parallel for SystemState / UI sliders
        static let yaw = 7
        static let pitch = 7
        static let verticalOffset = 0
    }

    /// Mirrors the option names declared by the Dolphin libretro core.
    enum OptionKey {
        static let irMode = "dolphin_ir_mode"
        static let sensorBarPosition = "dolphin_sensor_bar_position"
        static let yaw = "dolphin_ir_yaw"
        static let pitch = "dolphin_ir_pitch"
        static let verticalOffset = "dolphin_ir_offset"
    }

    enum IRMode: String, CaseIterable, Identifiable {
        /// "0" — Right Stick (Relative). Dolphin value, not the user-facing label.
        case rightStickRelative = "0"
        /// "1" — Right Stick (Absolute). Dolphin value.
        case rightStickAbsolute = "1"
        /// "2" — Mouse controls pointer. Dolphin value.
        case mousePointer = "2"
        var id: String { rawValue }
        var labelKey: String {
            switch self {
            case .rightStickRelative: return "controllers.wiiIR.mode.rightStickRelative"
            case .rightStickAbsolute: return "controllers.wiiIR.mode.rightStickAbsolute"
            case .mousePointer:       return "controllers.wiiIR.mode.mousePointer"
            }
        }
    }

    enum SensorBarPosition: String, CaseIterable, Identifiable {
        /// "0" — Bottom. Dolphin value.
        case bottom = "0"
        /// "1" — Top. Dolphin value.
        case top = "1"
        var id: String { rawValue }
        var labelKey: String {
            self == .top ? "controllers.wiiIR.sensorBar.top" : "controllers.wiiIR.sensorBar.bottom"
        }
    }

    /// Published state keyed by systemID so each system keeps its own snapshot
    /// but the whole binding still triggers a redraw when any field changes.
    @Published private var state: [String: SystemState] = [:]

    struct SystemState: Equatable {
        var irMode: IRMode
        var sensorBarPosition: SensorBarPosition
        var yaw: Int
        var pitch: Int
        var verticalOffset: Int
    }

    private init() {
        for sysID in ["wii", "gamecube"] {
            state[sysID] = loadState(forSystemID: sysID)
        }
    }

    // MARK: - Public read API

    func snapshot(for systemID: String) -> SystemState {
        if let cached = state[systemID] { return cached }
        let loaded = loadState(forSystemID: systemID)
        state[systemID] = loaded
        return loaded
    }

    // MARK: - Public write API

    func setIRMode(_ value: IRMode, systemID: String) {
        var s = snapshot(for: systemID)
        s.irMode = value
        commit(s, systemID: systemID, optionKey: OptionKey.irMode, value: value.rawValue)
    }

    func setSensorBarPosition(_ value: SensorBarPosition, systemID: String) {
        var s = snapshot(for: systemID)
        s.sensorBarPosition = value
        commit(s, systemID: systemID, optionKey: OptionKey.sensorBarPosition, value: value.rawValue)
    }

    func setYaw(_ value: Int, systemID: String) {
        var s = snapshot(for: systemID)
        s.yaw = value
        commit(s, systemID: systemID, optionKey: OptionKey.yaw, value: String(value))
    }

    func setPitch(_ value: Int, systemID: String) {
        var s = snapshot(for: systemID)
        s.pitch = value
        commit(s, systemID: systemID, optionKey: OptionKey.pitch, value: String(value))
    }

    func setVerticalOffset(_ value: Int, systemID: String) {
        var s = snapshot(for: systemID)
        s.verticalOffset = value
        commit(s, systemID: systemID, optionKey: OptionKey.verticalOffset, value: String(value))
    }

    /// Strip a single setting back to the bundled default. Currently unused in
    /// UI but kept so future "reset to default" buttons can call it directly.
    func reset(optionKey: String, systemID: String) {
        var s = snapshot(for: systemID)
        switch optionKey {
        case OptionKey.irMode:             s.irMode = IRMode(rawValue: Defaults.irModeValue) ?? .mousePointer
        case OptionKey.sensorBarPosition:  s.sensorBarPosition = SensorBarPosition(rawValue: Defaults.sensorBarPositionValue) ?? .top
        case OptionKey.yaw:                s.yaw = Defaults.yaw
        case OptionKey.pitch:              s.pitch = Defaults.pitch
        case OptionKey.verticalOffset:     s.verticalOffset = Defaults.verticalOffset
        default: return
        }

        var cfg = CoreOptionsManager.shared.loadSystemOverrides(for: Self.dolphinCoreID, systemID: systemID)
        cfg.removeValue(forKey: optionKey)
        if cfg.isEmpty {
            CoreOptionsManager.shared.deleteSystemOverride(for: Self.dolphinCoreID, systemID: systemID)
        } else {
            CoreOptionsManager.shared.saveSystemOverride(for: Self.dolphinCoreID, systemID: systemID, values: cfg)
        }

        state[systemID] = s
        broadcast(value: nil, optionKey: optionKey)
    }

    // MARK: - Private helpers

    private func loadState(forSystemID sysID: String) -> SystemState {
        let userCfg = CoreOptionsManager.shared.loadSystemOverrides(for: Self.dolphinCoreID, systemID: sysID)
        let bundled = CoreOverrideService.shared.getOverrides(for: Self.dolphinCoreID, scope: "default")

        return SystemState(
            irMode: IRMode(rawValue: userCfg[OptionKey.irMode] ?? bundled[OptionKey.irMode] ?? Defaults.irModeValue) ?? .mousePointer,
            sensorBarPosition: SensorBarPosition(rawValue: userCfg[OptionKey.sensorBarPosition] ?? bundled[OptionKey.sensorBarPosition] ?? Defaults.sensorBarPositionValue) ?? .top,
            yaw: parseInt(userCfg[OptionKey.yaw] ?? bundled[OptionKey.yaw]) ?? Defaults.yaw,
            pitch: parseInt(userCfg[OptionKey.pitch] ?? bundled[OptionKey.pitch]) ?? Defaults.pitch,
            verticalOffset: parseInt(userCfg[OptionKey.verticalOffset] ?? bundled[OptionKey.verticalOffset]) ?? Defaults.verticalOffset
        )
    }

    private func parseInt(_ s: String?) -> Int? {
        guard let s else { return nil }
        return Int(s)
    }

    private func commit(_ newState: SystemState, systemID: String, optionKey: String, value: String) {
        state[systemID] = newState

        var cfg = CoreOptionsManager.shared.loadSystemOverrides(for: Self.dolphinCoreID, systemID: systemID)
        cfg[optionKey] = value
        CoreOptionsManager.shared.saveSystemOverride(for: Self.dolphinCoreID, systemID: systemID, values: cfg)

        broadcast(value: value, optionKey: optionKey)
    }

    /// Push live changes to a running Dolphin core, if any, and notify it to
    /// re-read its options. Passing `nil` for value signals "delete override";
    /// the core still needs to re-poll, but we don't push a value.
    private func broadcast(value: String?, optionKey: String) {
        if let value {
            XPCBridgeAdapter.shared.setOptionValue(value, forKey: optionKey)
        }
        XPCBridgeAdapter.shared.setVariablesUpdated()
    }
}
