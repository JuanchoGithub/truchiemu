// Swift-side caller for LibretroBridge (Objective-C++)
// This wrapper makes it easy to call from Swift without bridging headers issues.

import Foundation

// The @objc class is defined in LibretroBridge.mm and exposed via the bridging header.
// This file holds the Swift-side helper that calls into it.

class LibretroBridgeSwift {
    static func launch(dylibPath: String, romPath: String,
                       videoCallback: @escaping (UnsafeRawPointer?, Int, Int, Int) -> Void) {
        LibretroBridge.launch(withDylibPath: dylibPath, romPath: romPath) { data, w, h, pitch in
            videoCallback(data, Int(w), Int(h), Int(pitch))
        }
    }

    static func stop() {
        LibretroBridge.stop()
    }

    static func saveState() {
        LibretroBridge.saveState()
    }
}
