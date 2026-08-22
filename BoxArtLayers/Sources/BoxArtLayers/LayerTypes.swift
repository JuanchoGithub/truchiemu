import CoreGraphics
import Foundation

/// Semantic role of a pixel region in a box-art composite.
public enum LayerRole: String, Codable, Sendable {
    /// Largest foreground character. Frozen — no holographic warp.
    case hero
    /// Game title / logo. Frozen, stacked under the hero.
    case title
    /// Secondary characters, props, terrain. Object-FX bus.
    case midground
    /// Sky / backdrop leftover. Holographic bus.
    case background
    /// Hardware spine, ratings, publisher marks. Frozen overlay.
    case chrome
}

/// One segmented object before or after role assignment.
public struct InstanceLayer: Sendable {
    public let id: Int
    public let role: LayerRole
    /// Grayscale alpha, same size as the source image.
    public let mask: CGImage
    /// Pixel rectangle, origin top-left.
    public let boundingBox: CGRect
    /// Fraction of the art window (after chrome crop) covered by this instance.
    public let areaRatio: Double
    /// 0 = back, 1 = front. Attention saliency unless a depth estimator is plugged in.
    public let frontness: Double
}

public struct LayerMasks: Sendable {
    public let hero: CGImage
    public let title: CGImage
    public let midground: CGImage
    public let background: CGImage
    public let chrome: CGImage
    /// Hero ∪ title ∪ chrome — everything that must not be warped.
    public let frozen: CGImage
}

public struct LayerCutouts: Sendable {
    public let hero: CGImage
    public let title: CGImage
    public let midground: CGImage
    public let background: CGImage
    public let chrome: CGImage
}

public struct QualityReport: Codable, Sendable {
    public let needsReview: Bool
    public let reasons: [String]
    public let heroAreaRatio: Double
    public let titleDetected: Bool
    public let instanceCount: Int
}

public struct InstanceRecord: Codable, Sendable {
    public let id: Int
    public let role: LayerRole
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let areaRatio: Double
    public let frontness: Double
}

public struct LayerManifest: Codable, Sendable {
    public let version: Int
    public let width: Int
    public let height: Int
    public let quality: QualityReport
    public let instances: [InstanceRecord]
}

/// Full decomposition: hard masks for compositing, a soft frontness map for ranking / sky FX.
public struct LayerBundle: Sendable {
    public let source: CGImage
    public let masks: LayerMasks
    public let cutouts: LayerCutouts
    /// Soft heatmap (0 = back, 1 = front). Do not use as an alpha.
    public let frontnessMap: CGImage
    /// Tinted debug composite (hero red, title yellow, mid green, sky blue, chrome gray).
    public let preview: CGImage
    public let instances: [InstanceLayer]
    public let manifest: LayerManifest
}

public enum BoxArtLayerError: Error, LocalizedError, Sendable {
    case invalidImage
    case visionFailed(String)
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The image has no pixel data."
        case .visionFailed(let message):
            return "Vision analysis failed: \(message)"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        }
    }
}
