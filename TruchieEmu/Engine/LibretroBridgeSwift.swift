import Foundation

class LibretroBridgeSwift {
    
    // MARK: - Launch & Lifecycle
    
    static func launch(dylibPath: String, romPath: String, coreID: String, systemID: String? = nil,
                       shaderDir: String? = nil,
                       videoCallback: @escaping (UnsafeRawPointer?, Int, Int, Int, Int) -> Void) {
        LibretroBridge.launch(withDylibPath: dylibPath, romPath: romPath, shaderDir: shaderDir, videoCallback: { data, w, h, pitch, format in
            videoCallback(data, Int(w), Int(h), Int(pitch), Int(format))
        }, coreID: coreID)
        
        if let sysID = systemID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let coreAR = CGFloat(aspectRatio())
                if coreAR > 0.0 {
                    if let index = SystemDatabase.systems.firstIndex(where: { $0.id == sysID }) {
                        LoggerService.debug(category: "LibretroBridge", "Core reported aspect ratio: \(coreAR)")
                        SystemDatabase.systems[index].coreReportedAspectRatio = coreAR
                    }
                }
            }
        }
    }

    static func stop() {
        LoggerService.debug(category: "LibretroBridge", "Stopping LibretroBridge")
        LibretroBridge.stop()
    }

    static func waitForCompletion() {
        var result = LibretroBridge.waitForCompletion()
        LoggerService.debug(category: "LibretroBridge", "Waiting for LibretroBridge to complete: \(result)")
        return result
    }

    // MARK: - Global State & Settings
    
    static func setLanguage(_ language: Int) {
        LoggerService.debug(category: "LibretroBridge", "Setting language to: \(language)")
        LibretroBridge.setLanguage(Int32(language))
    }

    static func setLogLevel(_ level: Int) {
        LoggerService.debug(category: "LibretroBridge", "Setting log level to: \(level)")
        LibretroBridge.setLogLevel(Int32(level))
    }
    
    static func setPaused(_ paused: Bool) {
        LoggerService.debug(category: "LibretroBridge", "Setting paused to: \(paused)")
        LibretroBridge.setPaused(paused)
    }
    
    static func isPaused() -> Bool {
        var paused = LibretroBridge.isPaused()
        LoggerService.debug(category: "LibretroBridge", "Checking if paused: \(paused)")
        return paused
    }

    // MARK: - Save States
    
    static func saveState() {
        var result = LibretroBridge.saveState()
        LoggerService.debug(category: "LibretroBridge", "Saving state: \(result)")
        return result
    }

    static func serializeState() -> Data? {
        var data = LibretroBridge.serializeState()
        LoggerService.debug(category: "LibretroBridge", "Serializing state: \(data)")
        return data
    }

    static func unserializeState(_ data: Data) -> Bool {
        var result = LibretroBridge.unserializeState(data)
        LoggerService.debug(category: "LibretroBridge", "Unserializing state: \(result)")
        return result
    }

    static func serializeSize() -> Int {
        var size = LibretroBridge.serializeSize()
        LoggerService.debug(category: "LibretroBridge", "Getting serialize size: \(size)")
        return size
    }

    // MARK: - Input
    
    static func setKeyState(retroID: Int, pressed: Bool) {
        LoggerService.debug(category: "LibretroBridge", "Setting key state: \(retroID) = \(pressed)")
        LibretroBridge.setKeyState(Int32(retroID), pressed: pressed)
    }

    static func setTurboState(turboIdx: Int, active: Bool, targetButton: Int) {
        LoggerService.debug(category: "LibretroBridge", "Setting turbo state: \(turboIdx) = \(active) = \(targetButton)")
        LibretroBridge.setTurboState(Int32(turboIdx), active: active, targetButton: Int32(targetButton))
    }

    static func setAnalogState(_ index: Int, id: Int, value: Int32) {
        LoggerService.debug(category: "LibretroBridge", "Setting analog state: \(index) = \(id) = \(value)")
        LibretroBridge.setAnalogState(Int32(index), id: Int32(id), value: value)
    }

    // MARK: - Video / Geometry
    
    static func currentRotation() -> Int {
        var rotation = LibretroBridge.currentRotation()
        LoggerService.debug(category: "LibretroBridge", "Getting current rotation: \(rotation)")
        return Int(rotation)
    }

    static func aspectRatio() -> Float {
        LoggerService.debug(category: "LibretroBridge", "Getting aspect ratio")
        return LibretroBridge.aspectRatio()
    }

    // MARK: - Core Options Accessors
    
    static func getOptionValue(forKey key: String) -> String? {
        var value = LibretroBridge.getOptionValue(forKey: key)
        LoggerService.debug(category: "LibretroBridge", "Getting option value: \(value)")
        return value
    }

    static func setOptionValue(_ value: String, forKey key: String) {
        LoggerService.debug(category: "LibretroBridge", "Setting option value: \(value) = \(key)")
        LibretroBridge.setOptionValue(value, forKey: key)
    }

    static func resetOptionToDefault(forKey key: String) {
        LoggerService.debug(category: "LibretroBridge", "Resetting option to default: \(key)")
        LibretroBridge.resetOptionToDefault(forKey: key)
    }

    static func resetAllOptionsToDefaults() {
        LoggerService.debug(category: "LibretroBridge", "Resetting all options to defaults")
        LibretroBridge.resetAllOptionsToDefaults()
    }

    static func getOptionsDictionary() -> [String: Any]? {
        var options = LibretroBridge.getOptionsDictionary() as [String: Any]?
        LoggerService.debug(category: "LibretroBridge", "Getting options dictionary: \(options)")
        return options
    }

    static func getCategoriesDictionary() -> [String: Any]? {
        var categories = LibretroBridge.getCategoriesDictionary() as [String: Any]?
        LoggerService.debug(category: "LibretroBridge", "Getting categories dictionary: \(categories)")
        return categories
    }

    // MARK: - Cheats
    
    static func applyCheats(_ cheats: [[String: Any]]) {
        LoggerService.debug(category: "LibretroBridge", "Applying cheats: \(cheats)")
        LibretroBridge.applyCheats(cheats)
    }
    
    static func applyDirectMemoryCheats(_ cheats: [[String: Any]]) {
        LoggerService.debug(category: "LibretroBridge", "Applying direct memory cheats: \(cheats)")
        LibretroBridge.applyDirectMemoryCheats(cheats)
    }
}