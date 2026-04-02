// Swift-side caller for LibretroBridge (Objective-C++)
// This wrapper makes it easy to call from Swift without bridging headers issues.

import Foundation

// The @objc class is defined in LibretroBridge.mm and exposed via the bridging header.
// This file holds the Swift-side helper that calls into it.

class LibretroBridgeSwift {
    static func launch(dylibPath: String, romPath: String, coreID: String,
                       videoCallback: @escaping (UnsafeRawPointer?, Int, Int, Int, Int) -> Void) {
        LibretroBridge.launch(withDylibPath: dylibPath, romPath: romPath, videoCallback: { data, w, h, pitch, format in
            videoCallback(data, Int(w), Int(h), Int(pitch), Int(format))
        }, coreID: coreID)
    }

    static func setKeyState(retroID: Int, pressed: Bool) {
        LibretroBridge.setKeyState(Int32(retroID), pressed: pressed)
    }

    static func setTurboState(turboIdx: Int, active: Bool, targetButton: Int) {
        LibretroBridge.setTurboState(Int32(turboIdx), active: active, targetButton: Int32(targetButton))
    }

    static func stop() {
        LibretroBridge.stop()
    }

    // MARK: - Rotation
    /// Returns the current rotation from the core: 0, 1, 2, or 3
    /// (representing 0, 90, 180, or 270 degrees clockwise)
    static func currentRotation() -> Int {
        return Int(LibretroBridge.currentRotation())
    }

    static func saveState() {
        LibretroBridge.saveState()
    }

    // MARK: - Core Options Accessors
    static func getOptionValue(forKey key: String) -> String? {
        LibretroBridge.getOptionValue(forKey: key)
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
        LibretroBridge.getOptionsDictionary() as [String: Any]?
    }

    static func getCategoriesDictionary() -> [String: Any]? {
        LibretroBridge.getCategoriesDictionary() as [String: Any]?
    }
}
