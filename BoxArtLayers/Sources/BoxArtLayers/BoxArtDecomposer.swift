import CoreGraphics
import Foundation

/// On-device box-art decomposer. Image in, hard layer masks + frontness heatmap out.
///
/// Uses Apple Vision subject lifting for instances, attention/objectness saliency as a
/// frontness prior (not physical depth), OCR + heuristics for title and chrome.
/// Swap ranking later by replacing the saliency map with a Core ML depth model —
/// the public `LayerBundle` shape stays the same.
public struct BoxArtDecomposer: Sendable {
    public var configuration: Configuration

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public func decompose(_ image: CGImage) async throws -> LayerBundle {
        let configuration = self.configuration
        // Cancellation-aware: cancelling the awaiting task (e.g. a system
        // switch tears down the card's SwiftUI .task) must abort the heavy
        // Vision work, not leave it running to completion on the CPU.
        let task = Task.detached(priority: .userInitiated) {
            try BoxArtDecomposer.run(image: image, configuration: configuration)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public func decompose(contentsOf url: URL) async throws -> LayerBundle {
        let image = try ImageIOSupport.loadCGImage(from: url)
        return try await decompose(image)
    }

    static func run(image: CGImage, configuration: Configuration) throws -> LayerBundle {
        let scene = try VisionAnalyzer.analyze(image, configuration: configuration)
        try Task.checkCancellation()
        let assigned = LayerAssigner.assign(scene, configuration: configuration)
        try Task.checkCancellation()
        let rgba = ImageIOSupport.rgbaBytes(from: image).pixels
        try Task.checkCancellation()
        let threshold = configuration.maskThreshold

        let masks = LayerMasks(
            hero: ImageIOSupport.cgImage(from: assigned.hero),
            title: ImageIOSupport.cgImage(from: assigned.title),
            midground: ImageIOSupport.cgImage(from: assigned.midground),
            background: ImageIOSupport.cgImage(from: assigned.background),
            chrome: ImageIOSupport.cgImage(from: assigned.chrome),
            frozen: ImageIOSupport.cgImage(from: assigned.frozen)
        )

        let cutouts = LayerCutouts(
            hero: ImageIOSupport.cutout(sourceRGBA: rgba, mask: assigned.hero),
            title: ImageIOSupport.cutout(sourceRGBA: rgba, mask: assigned.title),
            midground: ImageIOSupport.cutout(sourceRGBA: rgba, mask: assigned.midground),
            background: ImageIOSupport.cutout(sourceRGBA: rgba, mask: assigned.background),
            chrome: ImageIOSupport.cutout(sourceRGBA: rgba, mask: assigned.chrome)
        )
        try Task.checkCancellation()

        let instanceLayers: [InstanceLayer] = assigned.instances.compactMap { instance in
            guard let role = assigned.roles[instance.id] else { return nil }
            return InstanceLayer(
                id: instance.id,
                role: role,
                mask: ImageIOSupport.cgImage(from: instance.mask),
                boundingBox: instance.boundingBox,
                areaRatio: instance.areaRatio,
                frontness: instance.frontness
            )
        }

        let records = instanceLayers.map {
            InstanceRecord(
                id: $0.id,
                role: $0.role,
                x: $0.boundingBox.origin.x,
                y: $0.boundingBox.origin.y,
                width: $0.boundingBox.width,
                height: $0.boundingBox.height,
                areaRatio: $0.areaRatio,
                frontness: $0.frontness
            )
        }

        let manifest = LayerManifest(
            version: 1,
            width: scene.width,
            height: scene.height,
            quality: assigned.quality,
            instances: records
        )
        try Task.checkCancellation()

        return LayerBundle(
            source: image,
            masks: masks,
            cutouts: cutouts,
            frontnessMap: ImageIOSupport.cgImage(from: scene.frontness),
            preview: PreviewRenderer.render(
                sourceRGBA: rgba,
                assigned: assigned,
                threshold: threshold
            ),
            instances: instanceLayers,
            manifest: manifest
        )
    }
}
