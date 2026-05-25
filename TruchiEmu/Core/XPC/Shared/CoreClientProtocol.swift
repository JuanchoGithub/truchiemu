import Foundation

@objc protocol CoreClientProtocol {
    func videoFrameAvailable(width: Int, height: Int, pitch: Int, format: Int)
    func audioSamplesAvailable(count: Int)
    func coreOptionsV1(_ optionsArray: [[String: Any]])
    func coreOptionsV2(_ optionsArray: [[String: Any]], categoriesArray: [[String: Any]])
    func gameLoaded(romPath: String)
    func coreFailed(message: String)
    func geometryChanged(width: Int, height: Int, aspectRatio: Float)
    func rotationChanged(rotation: Int)
}
