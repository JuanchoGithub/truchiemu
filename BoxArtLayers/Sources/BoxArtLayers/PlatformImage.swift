#if canImport(AppKit)
import AppKit
import CoreGraphics

extension BoxArtDecomposer {
    public func decompose(_ image: NSImage) async throws -> LayerBundle {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw BoxArtLayerError.invalidImage
        }
        return try await decompose(cgImage)
    }
}

extension NSImage {
    convenience init?(boxArtLayer cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
#endif

#if canImport(UIKit)
import UIKit
import CoreGraphics

extension BoxArtDecomposer {
    public func decompose(_ image: UIImage) async throws -> LayerBundle {
        guard let cgImage = image.cgImage else {
            throw BoxArtLayerError.invalidImage
        }
        return try await decompose(cgImage)
    }
}
#endif
