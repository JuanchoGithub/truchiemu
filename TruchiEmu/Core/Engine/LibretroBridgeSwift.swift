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

    static func registerGameLoadedCallback(handler: @escaping (String) -> Void) {
        LibretroBridge.registerGameLoadedCallback { romPathPtr in
            if let romPath = String(validatingUTF8: romPathPtr) {
                handler(romPath)
            }
        }
    }


    // MARK: - Launch & Lifecycle

    static func launch(dylibPath: String, romPath: String, coreID: String, systemID: String? = nil, romFilename: String? = nil,
                       shaderDir: String? = nil,
                       videoCallback: @escaping (UnsafeRawPointer?, Int, Int, Int, Int) -> Void,
                       onFailure: ((String) -> Void)? = nil) {
        #if !XPC_SERVICE
        if XPCBridgeAdapter.shared.isActive {
            LoggerService.error(category: "LibretroBridge", "BUG: launch() called in-process while XPC mode is active — blocking to prevent core dylib load in main process")
            onFailure?("XPC mode active — core must run in service process")
            return
        }
        #endif
        LibretroBridge.launch(withDylibPath: dylibPath, romPath: romPath, shaderDir: shaderDir, videoCallback: { data, w, h, pitch, format in
            videoCallback(data, Int(w), Int(h), Int(pitch), Int(format))
        }, coreID: coreID, systemID: systemID, romFilename: romFilename, failureCallback: { message in
            onFailure?(message)
        })
        
        if let sysID = systemID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let coreAR = CGFloat(aspectRatio())
                if coreAR > 0.0 {
                    if let index = SystemDatabase.systems.firstIndex(where: { $0.id == sysID }) {
                        #if LOG_DEBUG
                        LoggerService.debug(category: "LibretroBridge", "Core reported aspect ratio: \(coreAR)")
                        #endif
                        SystemDatabase.systems[index].coreReportedAspectRatio = coreAR
                    }
                }
            }
        }
    }

    static func stop() {
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Stopping LibretroBridge")
        #endif
        LibretroBridge.stop()
    }

  static func waitForCompletion() {
    let result: Void = LibretroBridge.waitForCompletion()
    #if LOG_DEBUG
    LoggerService.debug(category: "LibretroBridge", "Waiting for LibretroBridge to complete: \(result)")
    #endif
    return result
  }

    static func loadCoreForOptions(_ dylibPath: String, coreID: String, romPath: String?) {
        #if !XPC_SERVICE
        if XPCBridgeAdapter.shared.isActive {
            LoggerService.error(category: "LibretroBridge", "BUG: loadCoreForOptions() called in-process while XPC mode is active — blocking")
            return
        }
        #endif
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Loading core for options: \(coreID) from \(dylibPath)")
        #endif
        LibretroBridge.loadCore(forOptions: dylibPath, coreID: coreID, romPath: romPath)
    }

  static func isCoreLoadedForOptions() -> Bool {
    let loaded = LibretroBridge.isCoreLoadedForOptions()
    #if LOG_DEBUG
    LoggerService.debug(category: "LibretroBridge", "Is core loaded for options: \(loaded)")
    #endif
    return loaded
  }

  // MARK: - Global State & Settings
    
    static func setLanguage(_ language: Int) {
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Setting language to: \(language)")
        #endif
        LibretroBridge.setLanguage(Int32(language))
    }

    static func setLogLevel(_ level: Int) {
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Setting log level to: \(level)")
        #endif
        LibretroBridge.setLogLevel(Int32(level))
    }
    
    static func setPaused(_ paused: Bool) {
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Setting paused to: \(paused)")
        #endif
        LibretroBridge.setPaused(paused)
    }
    
    static func isPaused() -> Bool {
        let paused = LibretroBridge.isPaused()
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Checking if paused: \(paused)")
        #endif
        return paused
    }

// MARK: - Save States

static func resetGame() {
LibretroBridge.resetGame()
}

static func saveState() {
        let result: Void = LibretroBridge.saveState()
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Saving state: \(result)")
        #endif
        return result
    }

    static func serializeState() -> Data? {
        let data = LibretroBridge.serializeState()
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Serializing state: \(String(describing: data))")
        #endif
        return data
    }

    static func unserializeState(_ data: Data) -> Bool {
        let result = LibretroBridge.unserializeState(data)
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Unserializing state: \(result)")
        #endif
        return result
    }

    static func serializeSize() -> Int {
        let size = LibretroBridge.serializeSize()
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Getting serialize size: \(size)")
        #endif
        return size
    }

// MARK: - Input

static func setFramePollCallback(_ callback: (@convention(c) () -> Void)?) {
LibretroBridge.setFramePollCallback(callback)
}

static func setKeyState(retroID: Int, pressed: Bool) {
        #if LOG_EXTREME
        LoggerService.extreme(category: "LibretroBridge", "Setting key state: \(retroID) = \(pressed)")
        #endif
        LibretroBridge.setKeyState(Int32(retroID), pressed: pressed)
    }

    static func setKeyState(retroID: Int, player: Int, pressed: Bool) {
        #if LOG_EXTREME
        LoggerService.extreme(category: "LibretroBridge", "Setting key state: player=\(player) retroID=\(retroID) = \(pressed)")
        #endif
        LibretroBridge.setKeyState(Int32(retroID), player: Int32(player), pressed: pressed)
    }

    static func setTurboState(turboIdx: Int, active: Bool, targetButton: Int) {
        LibretroBridge.setTurboState(Int32(turboIdx), active: active, targetButton: Int32(targetButton))
    }

    static func setAnalogState(_ index: Int, id: Int, value: Int32) {
        LibretroBridge.setAnalogState(Int32(index), id: Int32(id), value: value)
    }

    static func setAnalogState(player: Int, stick: Int, axis: Int, value: Int32) {
        LibretroBridge.setAnalogStateForPlayer(Int32(player), stick: Int32(stick), axis: Int32(axis), value: value)
    }

    static func setAnalogButtonState(retroID: Int, value: Int32) {
        LibretroBridge.setAnalogButtonState(Int32(retroID), value: value)
    }

    static func setAnalogButtonState(retroID: Int, player: Int, value: Int32) {
        LibretroBridge.setAnalogButtonState(Int32(retroID), player: Int32(player), value: value)
    }

    // MARK: - Keyboard / Mouse / Pointer Input

    static func dispatchKeyboardEvent(keycode: UInt32, character: UInt32, modifiers: UInt32, down: Bool) {
        LibretroBridge.dispatchKeyboardEvent(keycode, character: character, modifiers: modifiers, down: down)
    }

    static func setMouseDeltaX(_ dx: Int16, y dy: Int16) {
        LibretroBridge.setMouseDeltaX(dx, y: dy)
    }

    static func addMouseDelta(_ dx: Int16, y dy: Int16) {
        LibretroBridge.addMouseDelta(dx, y: dy)
    }

    static func setMouseButton(_ button: Int, pressed: Bool) {
        LibretroBridge.setMouseButton(Int32(button), pressed: pressed)
    }

    static func addMouseWheelDelta(_ delta: Int16) {
        LibretroBridge.addMouseWheelDelta(delta)
    }

    static func resetMouseDeltas() {
        LibretroBridge.resetMouseDeltas()
    }

    static func setAbsoluteMousePosition(_ x: Int16, y: Int16, override: Bool) {
        LibretroBridge.setAbsoluteMousePositionX(x, y: y, override: override)
    }

    static func setPointerPosition(_ x: Int16, y: Int16, pressed: Bool) {
        LibretroBridge.setPointerX(x, y: y, pressed: pressed)
    }

    // MARK: - Analog as Mouse

    static func setAnalogAsMouseEnabled(_ enabled: Bool, forPlayer player: Int = 0) {
        LibretroBridge.setAnalogAsMouseEnabled(enabled, forPlayer: Int32(player))
    }

    static func setAnalogAsMouseSensitivity(_ sensitivity: Float, forPlayer player: Int = 0) {
        LibretroBridge.setAnalogAsMouseSensitivity(sensitivity, forPlayer: Int32(player))
    }

    static func setAnalogAsMouseDeadzone(_ deadzone: Float, forPlayer player: Int = 0) {
        LibretroBridge.setAnalogAsMouseDeadzone(deadzone, forPlayer: Int32(player))
    }

    static func setAnalogAsMouseStick(_ stickIndex: Int, forPlayer player: Int = 0) {
        LibretroBridge.setAnalogAsMouseStick(Int32(stickIndex), forPlayer: Int32(player))
    }

    static func setAnalogMouseDeltaX(_ dx: Int16, y dy: Int16) {
        LibretroBridge.setAnalogMouseDeltaX(dx, y: dy)
    }

    // MARK: - Video / Geometry
    
    static func currentRotation() -> Int {
        let rotation = LibretroBridge.currentRotation()
        return Int(rotation)
    }

    static func aspectRatio() -> Float {
        return LibretroBridge.aspectRatio()
    }

    // MARK: - Core Options Accessors

    
    
    static func getOptionValue(forKey key: String) -> String? {
        let value = LibretroBridge.getOptionValue(forKey: key)
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Getting option value: \(String(describing: value))")
        #endif
        return value
    }

    static func setOptionValue(_ value: String, forKey key: String) {
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Setting option value: \(value) = \(key)")
        #endif
        LibretroBridge.setOptionValue(value, forKey: key)
    }

    static func resetOptionToDefault(forKey key: String) {
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Resetting option to default: \(key)")
        #endif
        LibretroBridge.resetOptionToDefault(forKey: key)
    }

    static func resetAllOptionsToDefaults() {
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Resetting all options to defaults")
        #endif
        LibretroBridge.resetAllOptionsToDefaults()
    }

    // MARK: - Controller Port Device

    static func setControllerPortDevice(_ port: UInt32, device: UInt32) {
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Setting controller port \(port) to device \(device)")
        #endif
        LibretroBridge.setControllerPortDevice(port, device: device)
    }

    static func setVariablesUpdated() {
        LibretroBridge.setVariablesUpdated()
    }

    static func setGenesisDeviceType(_ deviceType: UInt32) {
        LibretroBridge.setGenesisDeviceType(deviceType)
    }

    // MARK: - Direct Memory Access

    static func getMemoryData(type: UInt32, offset: Int, size: Int) -> Data? {
        var memSize: size_t = 0
        guard let ptr = LibretroBridge.getMemoryData(type, size: &memSize), memSize > 0 else {
            return nil
        }
        guard offset < memSize else { return nil }
        let available = min(size, Int(memSize) - offset)
        return Data(bytes: ptr.advanced(by: offset), count: available)
    }

    static func getMemoryDataUnsafe(type: UInt32, offset: Int, size: Int) -> Data? {
        var memSize: size_t = 0
        guard let ptr = LibretroBridge.getMemoryDataUnsafe(type, size: &memSize), memSize > 0 else {
            return nil
        }
        guard offset < memSize else { return nil }
        let available = min(size, Int(memSize) - offset)
        return Data(bytes: ptr.advanced(by: offset), count: available)
    }

    static func getMemorySize(type: UInt32) -> Int {
        var memSize: size_t = 0
        LibretroBridge.getMemoryData(type, size: &memSize)
        return Int(memSize)
    }

    // MARK: - Save RAM (SRAM) Access

    static func getSaveRAMData() -> Data? {
        guard let data = LibretroBridge.getSaveRAMData() else {
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroBridge", "No SAVE_RAM data available")
            #endif
            return nil
        }
        LoggerService.info(category: "LibretroBridge", "Retrieved SAVE_RAM: \(data.count) bytes")
        return data
    }

    static func loadSaveRAMData(_ data: Data) -> Bool {
        let result = LibretroBridge.loadSaveRAMData(data)
        LoggerService.info(category: "LibretroBridge", "Loaded SAVE_RAM (\(data.count) bytes): \(result)")
        return result
    }

    static func saveDirectoryPath() -> String {
        let path = LibretroBridge.saveDirectoryPath()
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Save directory: \(path)")
        #endif
        return path
    }

    static func preloadSaveRAM(from path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroBridge", "No SRAM file to preload: \(path)")
            #endif
            return false
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let result = LibretroBridge.loadSaveRAMData(data)
            LoggerService.info(category: "LibretroBridge", "Preloaded SRAM (\(data.count) bytes) from: \(path) - success: \(result)")
            return result
        } catch {
            LoggerService.error(category: "LibretroBridge", "Failed to preload SRAM: \(error.localizedDescription)")
            return false
        }
    }

    static func getOptionsDictionary() -> [String: Any]? {
        let options = LibretroBridge.getOptionsDictionary() as [String: Any]?
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Getting options dictionary: \(String(describing: options))")
        #endif
        return options
    }

    static func getCategoriesDictionary() -> [String: Any]? {
        let categories = LibretroBridge.getCategoriesDictionary() as [String: Any]?
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Getting categories dictionary: \(String(describing: categories))")
        #endif
        return categories
    }

    // MARK: - Environment Callbacks (Bridge $\rightarrow$ Swift)

    static func setCoreOptionsV1(_ optionsArray: [[String: Any]]) {
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Receiving V1 core options")
        #endif
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
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Receiving V2 core options")
        #endif
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
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Applying cheats: \(cheats)")
        #endif
        LibretroBridge.applyCheats(cheats)
    }
    
    static func applyDirectMemoryCheats(_ cheats: [[String: Any]]) {
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroBridge", "Applying direct memory cheats: \(cheats)")
        #endif
        LibretroBridge.applyDirectMemoryCheats(cheats)
    }
}
