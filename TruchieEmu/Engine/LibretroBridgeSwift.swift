import Foundation

class LibretroBridgeSwift {
    
    // MARK: - Logging Integration
    
    static func registerCoreLogger(logger: @escaping (String, Int) -> Void) {
        // Because it is a + (class method) in Obj-C, 
        // we call it on the class name in Swift.
        LibretroBridge.registerCoreLogger { messagePtr, level in
            if let message = String(validatingUTF8: messagePtr) {
                logger(message, Int(level))
            } else {
                logger("Malformed UTF8 string from core", Int(level))
            }
        }
    }


    // MARK: - Launch & Lifecycle

    static func launch(dylibPath: String, romPath: String, coreID: String, systemID: String? = nil,
                       shaderDir: String? = nil,
                       videoCallback: @escaping (UnsafeRawPointer?, Int, Int, Int, Int) -> Void,
                       onFailure: ((String) -> Void)? = nil) {
        LibretroBridge.launch(withDylibPath: dylibPath, romPath: romPath, shaderDir: shaderDir, videoCallback: { data, w, h, pitch, format in
            videoCallback(data, Int(w), Int(h), Int(pitch), Int(format))
        }, coreID: coreID, failureCallback: { message in
            onFailure?(message)
        })
        
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
        let result: Void = LibretroBridge.waitForCompletion()
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
        let paused = LibretroBridge.isPaused()
        LoggerService.debug(category: "LibretroBridge", "Checking if paused: \(paused)")
        return paused
    }

    // MARK: - Save States
    
    static func saveState() {
        let result: Void = LibretroBridge.saveState()
        LoggerService.debug(category: "LibretroBridge", "Saving state: \(result)")
        return result
    }

    static func serializeState() -> Data? {
        let data = LibretroBridge.serializeState()
        LoggerService.debug(category: "LibretroBridge", "Serializing state: \(String(describing: data))")
        return data
    }

    static func unserializeState(_ data: Data) -> Bool {
        let result = LibretroBridge.unserializeState(data)
        LoggerService.debug(category: "LibretroBridge", "Unserializing state: \(result)")
        return result
    }

    static func serializeSize() -> Int {
        let size = LibretroBridge.serializeSize()
        LoggerService.debug(category: "LibretroBridge", "Getting serialize size: \(size)")
        return size
    }

    // MARK: - Input
    
    static func setKeyState(retroID: Int, pressed: Bool) {
        LoggerService.extreme(category: "LibretroBridge", "Setting key state: \(retroID) = \(pressed)")
        LibretroBridge.setKeyState(Int32(retroID), pressed: pressed)
    }

    static func setTurboState(turboIdx: Int, active: Bool, targetButton: Int) {
        LoggerService.extreme(category: "LibretroBridge", "Setting turbo state: \(turboIdx) = \(active) = \(targetButton)")
        LibretroBridge.setTurboState(Int32(turboIdx), active: active, targetButton: Int32(targetButton))
    }

    static func setAnalogState(_ index: Int, id: Int, value: Int32) {
        LoggerService.extreme(category: "LibretroBridge", "Setting analog state: \(index) = \(id) = \(value)")
        LibretroBridge.setAnalogState(Int32(index), id: Int32(id), value: value)
    }

    // MARK: - Video / Geometry
    
    static func currentRotation() -> Int {
        let rotation = LibretroBridge.currentRotation()
        LoggerService.extreme(category: "LibretroBridge", "Getting current rotation: \(rotation)")
        return Int(rotation)
    }

    static func aspectRatio() -> Float {
        LoggerService.extreme(category: "LibretroBridge", "Getting aspect ratio")
        return LibretroBridge.aspectRatio()
    }

    // MARK: - Core Options Accessors
    
    static func getOptionValue(forKey key: String) -> String? {
        let value = LibretroBridge.getOptionValue(forKey: key)
        LoggerService.debug(category: "LibretroBridge", "Getting option value: \(String(describing: value))")
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
        let options = LibretroBridge.getOptionsDictionary() as [String: Any]?
        LoggerService.debug(category: "LibretroBridge", "Getting options dictionary: \(String(describing: options))")
        return options
    }

    static func getCategoriesDictionary() -> [String: Any]? {
        let categories = LibretroBridge.getCategoriesDictionary() as [String: Any]?
        LoggerService.debug(category: "LibretroBridge", "Getting categories dictionary: \(String(describing: categories))")
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
