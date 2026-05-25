import Foundation
import IOSurface

final class CoreClientDelegate: NSObject, CoreClientProtocol {
    static let shared = CoreClientDelegate()

    var onVideoFrame: ((Int, Int, Int, Int) -> Void)?
    var onAudioAvailable: ((Int) -> Void)?
    var onGameLoaded: ((String) -> Void)?
    var onCoreFailed: ((String) -> Void)?
    var onGeometryChanged: ((Int, Int, Float) -> Void)?
    var onRotationChanged: ((Int) -> Void)?
    var onCoreOptionsV1: (([[String: Any]]) -> Void)?
    var onCoreOptionsV2: (([[String: Any]], [[String: Any]]) -> Void)?

    private override init() { super.init() }

    func videoFrameAvailable(width: Int, height: Int, pitch: Int, format: Int) {
        onVideoFrame?(width, height, pitch, format)
    }

    func audioSamplesAvailable(count: Int) {
        onAudioAvailable?(count)
    }

    func coreOptionsV1(_ optionsArray: [[String: Any]]) {
        onCoreOptionsV1?(optionsArray)
    }

    func coreOptionsV2(_ optionsArray: [[String: Any]], categoriesArray: [[String: Any]]) {
        onCoreOptionsV2?(optionsArray, categoriesArray)
    }

    func gameLoaded(romPath: String) {
        onGameLoaded?(romPath)
    }

    func coreFailed(message: String) {
        onCoreFailed?(message)
    }

    func geometryChanged(width: Int, height: Int, aspectRatio: Float) {
        onGeometryChanged?(width, height, aspectRatio)
    }

    func rotationChanged(rotation: Int) {
        onRotationChanged?(rotation)
    }
}
