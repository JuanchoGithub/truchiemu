import Foundation

@objc class LibretroBridgeSwift: NSObject {
    
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

    // MARK: - Keyboard / Mouse / Pointer Input

    static func dispatchKeyboardEvent(keycode: UInt32, character: UInt32, modifiers: UInt32, down: Bool) {
        LoggerService.info(category: "LibretroBridge", "Keyboard event: keycode=\(keycode) char=\(character) mod=\(modifiers) down=\(down)")
        LibretroBridge.dispatchKeyboardEvent(keycode, character: character, modifiers: modifiers, down: down)
    }

    static func setMouseDeltaX(_ dx: Int16, y dy: Int16) {
        LoggerService.extreme(category: "LibretroBridge", "Mouse delta: \(dx), \(dy)")
        LibretroBridge.setMouseDeltaX(dx, y: dy)
    }

    static func setMouseButton(_ button: Int, pressed: Bool) {
        LoggerService.extreme(category: "LibretroBridge", "Mouse button: \(button) pressed=\(pressed)")
        LibretroBridge.setMouseButton(Int32(button), pressed: pressed)
    }

    static func addMouseWheelDelta(_ delta: Int16) {
        LoggerService.extreme(category: "LibretroBridge", "Mouse wheel delta: \(delta)")
        LibretroBridge.addMouseWheelDelta(delta)
    }

    static func resetMouseDeltas() {
        LoggerService.extreme(category: "LibretroBridge", "Resetting mouse deltas")
        LibretroBridge.resetMouseDeltas()
    }

    static func setPointerPosition(_ x: Int16, y: Int16, pressed: Bool) {
        LoggerService.extreme(category: "LibretroBridge", "Pointer: \(x), \(y) pressed=\(pressed)")
        LibretroBridge.setPointerX(x, y: y, pressed: pressed)
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

    // MARK: - Environment Callbacks (Bridge $\rightarrow$ Swift)

    static func setCoreOptionsV1(_ optionsArray: [[String: Any]]) {
        LoggerService.debug(category: "LibretroBridge", "Receiving V1 core options")
        var options: [CoreOption] = []
        for dict in optionsArray {
            let key = dict["key"] as? String ?? ""
            let desc = dict["desc"] as? String ?? ""
            let info = dict["info"] as? String ?? ""
            let catKey = dict["category"] as? String ?? ""
            let defaultVal = dict["defaultValue"] as? String ?? ""
            let currentVal = dict["currentValue"] as? String ?? defaultVal
            
            var values: [CoreOptionValue] = []
            if let valsArr = dict["values"] as? [[String: String]] {
                for v in valsArr {
                    values.append(CoreOptionValue(value: v["value"] ?? "", label: v["label"] ?? v["value"] ?? ""))
                }
            }
            if values.isEmpty {
                values = [CoreOptionValue(value: currentVal, label: currentVal)]
            }
            
            options.append(CoreOption(
                key: key,
                description: desc,
                info: info,
                category: catKey.isEmpty ? nil : catKey,
                values: values,
                defaultValue: defaultVal,
                currentValue: currentVal,
                version: .v1
            ))
        }
        Task { @MainActor in
            CoreOptionsManager.shared.setOptionsV1(options)
        }
    }

    static func setCoreOptionsV2(_ optionsArray: [[String: Any]], categoriesArray: [[String: Any]]) {
        LoggerService.debug(category: "LibretroBridge", "Receiving V2 core options")
        var options: [CoreOption] = []
        for dict in optionsArray {
            let key = dict["key"] as? String ?? ""
            let desc = dict["desc"] as? String ?? ""
            let info = dict["info"] as? String ?? ""
            let catKey = dict["category"] as? String ?? ""
            let defaultVal = dict["defaultValue"] as? String ?? ""
            let currentVal = dict["currentValue"] as? String ?? defaultVal
            
            var values: [CoreOptionValue] = []
            if let valsArr = dict["values"] as? [[String: String]] {
                for v in valsArr {
                    values.append(CoreOptionValue(value: v["value"] ?? "", label: v["label"] ?? v["value"] ?? ""))
                }
            }
            if values.isEmpty {
                values = [CoreOptionValue(value: currentVal, label: currentVal)]
            }
            
            options.append(CoreOption(
                key: key,
                description: desc,
                info: info,
                category: catKey.isEmpty ? nil : catKey,
                values: values,
                defaultValue: defaultVal,
                currentValue: currentVal,
                version: .v2
            ))
        }
        
        var categories: [CoreOptionCategory] = []
        for dict in categoriesArray {
            let key = dict["key"] as? String ?? ""
            let desc = dict["desc"] as? String ?? ""
            let info = dict["info"] as? String ?? ""
            categories.append(CoreOptionCategory(key: key, description: desc, info: info))
        }
        
        Task { @MainActor in
            CoreOptionsManager.shared.setOptions(options, categories: categories)
        }
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
