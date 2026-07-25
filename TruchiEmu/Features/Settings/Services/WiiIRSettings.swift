import Foundation

// MARK: - Wii IR Settings

/// Persists Wiimote IR calibration settings to a per-system `.cfg` file in the
/// CoreOverride directory. Reads back at launch via `applyPersistedOverrides()`
/// which feeds them to the Dolphin libretro core options.
///
/// Defaults are tuned for mouse-pointer mode on a Mac — narrow yaw/pitch reduce
/// sensitivity, "Top" sensor bar fixes the inverted Y axis users commonly report.
@MainActor
final class WiiIRSettings: ObservableObject {
    static let shared = WiiIRSettings()

    static let dolphinCoreID = "dolphin_libretro"
    private static let defaultCoreID = "_default"

    /// Defaults baked into the bundled `dolphin_libretro_default.json` — kept in
    /// sync with that file. UI shows them when no user override is set.
    enum Defaults {
        static let irMode = "Mouse controls pointer"
        static let sensorBarPosition = "Top"
        static let yaw = 7
        static let pitch = 7
        static let verticalOffset = 10
    }

    /// Mirrors the option names declared by the Dolphin libretro core.
    enum OptionKey {
        static let irMode = "dolphin_ir_mode"
        static let sensorBarPosition = "dolphin_sensor_bar_position"
        static let yaw = "dolphin_ir_yaw"
        static let pitch = "dolphin_ir_pitch"
        static let verticalOffset = "dolphin_ir_offset"
    }

    /// Available IR control modes — labels match Dolphin's core option enum so
    /// they pass through to the core verbatim.
    enum IRMode: String, CaseIterable, Identifiable {
        case rightStickRelative = "Right Stick controls pointer (relative)"
        case rightStickAbsolute = "Right Stick controls pointer (absolute)"
        case mousePointer = "Mouse controls pointer"
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
        case top = "Top"
        case bottom = "Bottom"
        var id: String { rawValue }
        var labelKey: String {
            self == .top ? "controllers.wiiIR.sensorBar.top" : "controllers.wiiIR.sensorBar.bottom"
        }
    }

    // MARK: - Public read API

    func irMode(systemID: String) -> IRMode {
        IRMode(rawValue: string(systemID: systemID, key: OptionKey.irMode, default: Defaults.irMode))
            ?? .mousePointer
    }

    func sensorBarPosition(systemID: String) -> SensorBarPosition {
        SensorBarPosition(rawValue: string(systemID: systemID, key: OptionKey.sensorBarPosition, default: Defaults.sensorBarPosition))
            ?? .top
    }

    func yaw(systemID: String) -> Int {
        int(systemID: systemID, key: OptionKey.yaw, default: Defaults.yaw)
    }

    func pitch(systemID: String) -> Int {
        int(systemID: systemID, key: OptionKey.pitch, default: Defaults.pitch)
    }

    func verticalOffset(systemID: String) -> Int {
        int(systemID: systemID, key: OptionKey.verticalOffset, default: Defaults.verticalOffset)
    }

    /// Inverted absolute paths under CoreOverrides. Kept here so other layers
    /// (e.g., Live Streaming / Recording ban lists) can reuse them later.
    nonisolated var overridesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchiEmu/CoreOverrides", isDirectory: true)
    }

    // MARK: - Public write API

    func setIRMode(_ value: IRMode, systemID: String) {
        setString(value.rawValue, systemID: systemID, key: OptionKey.irMode)
    }

    func setSensorBarPosition(_ value: SensorBarPosition, systemID: String) {
        setString(value.rawValue, systemID: systemID, key: OptionKey.sensorBarPosition)
    }

    func setYaw(_ value: Int, systemID: String) {
        setInt(value, systemID: systemID, key: OptionKey.yaw)
    }

    func setPitch(_ value: Int, systemID: String) {
        setInt(value, systemID: systemID, key: OptionKey.pitch)
    }

    func setVerticalOffset(_ value: Int, systemID: String) {
        setInt(value, systemID: systemID, key: OptionKey.verticalOffset)
    }

    /// Strip a single setting back to the bundled default by deleting the line
    /// from the system override cfg.
    func reset(key: String, systemID: String) {
        var all = CoreOptionsManager.shared.loadSystemOverrides(for: Self.dolphinCoreID, systemID: systemID)
        all.removeValue(forKey: key)
        if all.isEmpty {
            CoreOptionsManager.shared.deleteSystemOverride(for: Self.dolphinCoreID, systemID: systemID)
        } else {
            CoreOptionsManager.shared.saveSystemOverride(for: Self.dolphinCoreID, systemID: systemID, values: all)
        }
        broadcast(key: key, systemID: systemID, value: nil)
    }

    // MARK: - Private helpers

    private func string(systemID: String, key: String, default fallback: String) -> String {
        if let user = CoreOptionsManager.shared.loadSystemOverrides(for: Self.dolphinCoreID, systemID: systemID)[key] {
            return user
        }
        if let appDefault = CoreOverrideService.shared.getOverrides(for: Self.dolphinCoreID, scope: "default")[key] {
            return appDefault
        }
        return fallback
    }

    private func int(systemID: String, key: String, default fallback: Int) -> Int {
        if let user = CoreOptionsManager.shared.loadSystemOverrides(for: Self.dolphinCoreID, systemID: systemID)[key],
           let parsed = Int(user) {
            return parsed
        }
        if let appDefault = CoreOverrideService.shared.getOverrides(for: Self.dolphinCoreID, scope: "default")[key],
           let parsed = Int(appDefault) {
            return parsed
        }
        return fallback
    }

    private func setString(_ value: String, systemID: String, key: String) {
        merge(userValue: value, systemID: systemID, key: key)
        broadcast(key: key, systemID: systemID, value: value)
    }

    private func setInt(_ value: Int, systemID: String, key: String) {
        merge(userValue: String(value), systemID: systemID, key: key)
        broadcast(key: key, systemID: systemID, value: String(value))
    }

    private func merge(userValue: String, systemID: String, key: String) {
        var all = CoreOptionsManager.shared.loadSystemOverrides(for: Self.dolphinCoreID, systemID: systemID)
        all[key] = userValue
        CoreOptionsManager.shared.saveSystemOverride(for: Self.dolphinCoreID, systemID: systemID, values: all)
    }

    /// Push live changes to a running Dolphin core, if any, and notify the core
    /// to re-read its options.
    private func broadcast(key: String, systemID: String, value: String?) {
        if let value {
            XPCBridgeAdapter.shared.setOptionValue(value, forKey: key)
        }
        XPCBridgeAdapter.shared.setVariablesUpdated()
    }
}
