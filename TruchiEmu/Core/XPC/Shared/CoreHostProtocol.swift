import Foundation

@objc protocol CoreHostProtocol {
    func launch(dylibPath: String,
                romPath: String,
                coreID: String,
                systemID: String?,
                romFilename: String?,
                shaderDir: String?,
                saveDirectory: String,
                systemDirectory: String,
                language: Int,
                logLevel: Int,
                reply: @escaping (Bool, String?) -> Void)

    func stop(reply: @escaping () -> Void)
    func setPaused(_ paused: Bool, reply: @escaping () -> Void)
    func setLanguage(_ language: Int, reply: @escaping () -> Void)
    func setLogLevel(_ level: Int, reply: @escaping () -> Void)

    func serializeSize(reply: @escaping (Int) -> Void)
    func serializeState(reply: @escaping (Data?) -> Void)
    func unserializeState(_ data: Data, reply: @escaping (Bool) -> Void)

    func getSaveRAMData(reply: @escaping (Data?) -> Void)
    func loadSaveRAMData(_ data: Data, reply: @escaping (Bool) -> Void)

    func applyCheats(_ cheats: [[String: Any]], reply: @escaping () -> Void)
    func applyDirectMemoryCheats(_ cheats: [[String: Any]], reply: @escaping () -> Void)

    func setOptionValue(_ value: String, forKey key: String, reply: @escaping () -> Void)
    func setOptions(_ options: [String: String], reply: @escaping () -> Void)
    func getOptionValue(forKey key: String, reply: @escaping (String?) -> Void)
    func resetOptionToDefault(forKey key: String, reply: @escaping () -> Void)
    func resetAllOptionsToDefaults(reply: @escaping () -> Void)
    func getOptionsDictionary(reply: @escaping ([String: Any]?) -> Void)
    func getCategoriesDictionary(reply: @escaping ([String: Any]?) -> Void)
    func getInputDescriptorsDictionary(reply: @escaping ([String: Any]?) -> Void)

    func getAspectRatio(reply: @escaping (Float) -> Void)
    func getCurrentRotation(reply: @escaping (Int) -> Void)

    func setControllerPortDevice(port: Int, device: Int, reply: @escaping () -> Void)

    func loadCoreForOptions(dylibPath: String, coreID: String, romPath: String?, reply: @escaping () -> Void)
    func isCoreLoadedForOptions(reply: @escaping (Bool) -> Void)

    func setKeyStates(_ states: [Int: Bool], reply: @escaping () -> Void)
    func setKeyState(_ id: Int32, pressed: Bool, reply: @escaping () -> Void)
    func setAnalogStates(_ states: [[Int]], reply: @escaping () -> Void)
    func setAnalogState(_ state: [Int32], reply: @escaping () -> Void)
    func setAnalogButtonStates(_ states: [Int: Int32], reply: @escaping () -> Void)
    func setAnalogButtonState(_ id: Int32, value: Int32, reply: @escaping () -> Void)
    func setTurboStates(_ states: [[Int]], reply: @escaping () -> Void)
    func setTurboState(_ state: [Int32], reply: @escaping () -> Void)
    func setKeyboardStates(_ states: [Int: Bool], reply: @escaping () -> Void)
    func setMouseState(deltaX: Int16, deltaY: Int16, wheelDelta: Int16, buttons: UInt32, reply: @escaping () -> Void)
    func setPointerPosition(x: Int16, y: Int16, pressed: Bool, reply: @escaping () -> Void)
    func dispatchKeyboardEvent(keycode: UInt32, character: UInt32, modifiers: UInt32, down: Bool, reply: @escaping () -> Void)

    func isPaused(reply: @escaping (Bool) -> Void)

    func setSharedMemoryName(_ name: String, reply: @escaping () -> Void)
    func setIOSurfaceForVideo(_ surface: IOSurface?, reply: @escaping () -> Void)

    // Lightweight liveness check — used by the main app's watchdog timer.
    // Must respond immediately to prevent SIGKILL after 3s unresponsiveness.
    func ping(reply: @escaping () -> Void)
}
