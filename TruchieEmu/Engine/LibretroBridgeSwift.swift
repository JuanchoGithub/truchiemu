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
                        SystemDatabase.systems[index].coreReportedAspectRatio = coreAR
                    }
                }
            }
        }
    }

    static func stop() {
        LibretroBridge.stop()
    }

    static func waitForCompletion() {
        LibretroBridge.waitForCompletion()
    }

    // MARK: - Global State & Settings
    
    static func setLanguage(_ language: Int) {
        LibretroBridge.setLanguage(Int32(language))
    }

    static func setLogLevel(_ level: Int) {
        LibretroBridge.setLogLevel(Int32(level))
    }
    
    static func setPaused(_ paused: Bool) {
        LibretroBridge.setPaused(paused)
    }
    
    static func isPaused() -> Bool {
        return LibretroBridge.isPaused()
    }

    // MARK: - Save States
    
    static func saveState() {
        LibretroBridge.saveState()
    }

    static func serializeState() -> Data? {
        return LibretroBridge.serializeState()
    }

    static func unserializeState(_ data: Data) -> Bool {
        return LibretroBridge.unserializeState(data)
    }

    static func serializeSize() -> Int {
        return LibretroBridge.serializeSize()
    }

    // MARK: - Input
    
    static func setKeyState(retroID: Int, pressed: Bool) {
        LibretroBridge.setKeyState(Int32(retroID), pressed: pressed)
    }

    static func setTurboState(turboIdx: Int, active: Bool, targetButton: Int) {
        LibretroBridge.setTurboState(Int32(turboIdx), active: active, targetButton: Int32(targetButton))
    }

    static func setAnalogState(_ index: Int, id: Int, value: Int32) {
        LibretroBridge.setAnalogState(Int32(index), id: Int32(id), value: value)
    }

    // MARK: - Video / Geometry
    
    static func currentRotation() -> Int {
        return Int(LibretroBridge.currentRotation())
    }

    static func aspectRatio() -> Float {
        return LibretroBridge.aspectRatio()
    }

    // MARK: - Core Options Accessors
    
    static func getOptionValue(forKey key: String) -> String? {
        return LibretroBridge.getOptionValue(forKey: key)
    }

    static func setOptionValue(_ value: String, forKey key: String) {
        LibretroBridge.setOptionValue(value, forKey: key)
    }

    static func resetOptionToDefault(forKey key: String) {
        LibretroBridge.resetOptionToDefault(forKey: key)
    }

    static func resetAllOptionsToDefaults() {
        LibretroBridge.resetAllOptionsToDefaults()
    }

    static func getOptionsDictionary() -> [String: Any]? {
        return LibretroBridge.getOptionsDictionary() as [String: Any]?
    }

    static func getCategoriesDictionary() -> [String: Any]? {
        return LibretroBridge.getCategoriesDictionary() as [String: Any]?
    }

    // MARK: - Cheats
    
    static func applyCheats(_ cheats: [[String: Any]]) {
        LibretroBridge.applyCheats(cheats)
    }
    
    static func applyDirectMemoryCheats(_ cheats: [[String: Any]]) {
        LibretroBridge.applyDirectMemoryCheats(cheats)
    }
}