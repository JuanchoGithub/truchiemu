import CoreGraphics
import Foundation
import Vision

struct TextHit {
    let string: String
    let boundingBox: CGRect
    let confidence: Float
}

struct InstanceCandidate {
    let id: Int
    var mask: MaskBuffer
    let boundingBox: CGRect
    let areaRatio: Double
    let frontness: Double
    let centroid: CGPoint
}

struct SceneAnalysis {
    let width: Int
    let height: Int
    let instances: [InstanceCandidate]
    let text: [TextHit]
    let frontness: MaskBuffer
    let chromeHint: MaskBuffer
}

enum VisionAnalyzer {
    static let chromeKeywords: [String] = [
        "nintendo", "game boy", "gameboy", "only for",
        "esrb", "everyone", "teen", "mature", "e10", "pegi",
        "playstation", "xbox", "sega", "switch", "wii",
        "content rated", "rating pending",
    ]

    static func analyze(_ image: CGImage, configuration: BoxArtDecomposer.Configuration) throws -> SceneAnalysis {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { throw BoxArtLayerError.invalidImage }

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])

        let instanceRequest = VNGenerateForegroundInstanceMaskRequest()
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let objectnessRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        textRequest.recognitionLanguages = ["en-US"]

        do {
            try handler.perform([instanceRequest, saliencyRequest, objectnessRequest, textRequest])
        } catch {
            throw BoxArtLayerError.visionFailed(error.localizedDescription)
        }

        let attention = (saliencyRequest.results?.first as? VNSaliencyImageObservation).map {
            ImageIOSupport.mask(from: $0.pixelBuffer, width: width, height: height)
        }
        let objectness = (objectnessRequest.results?.first as? VNSaliencyImageObservation).map {
            ImageIOSupport.mask(from: $0.pixelBuffer, width: width, height: height)
        }

        let frontness: MaskBuffer
        if let attention, let objectness {
            frontness = attention.union(objectness)
        } else {
            frontness = attention ?? objectness ?? MaskBuffer(width: width, height: height)
        }

        var instances = try extractInstances(
            from: instanceRequest,
            handler: handler,
            frontness: frontness,
            configuration: configuration
        )

        if instances.isEmpty, let fallback = fallbackInstance(from: frontness, configuration: configuration) {
            instances = [fallback]
        }

        let text = (textRequest.results ?? []).compactMap { observation -> TextHit? in
            guard let best = observation.topCandidates(1).first else { return nil }
            return TextHit(
                string: best.string,
                boundingBox: pixelRect(from: observation.boundingBox, width: width, height: height),
                confidence: best.confidence
            )
        }

        let chromeHint = ChromeDetector.detect(
            image: image,
            text: text,
            configuration: configuration
        )

        return SceneAnalysis(
            width: width,
            height: height,
            instances: instances,
            text: text,
            frontness: frontness,
            chromeHint: chromeHint
        )
    }

    private static func extractInstances(
        from request: VNGenerateForegroundInstanceMaskRequest,
        handler: VNImageRequestHandler,
        frontness: MaskBuffer,
        configuration: BoxArtDecomposer.Configuration
    ) throws -> [InstanceCandidate] {
        guard let observation = request.results?.first else { return [] }
        var result: [InstanceCandidate] = []
        var nextID = 1
        for index in observation.allInstances {
            do {
                let buffer = try observation.generateScaledMaskForImage(
                    forInstances: IndexSet(integer: index),
                    from: handler
                )
                var mask = ImageIOSupport.mask(
                    from: buffer,
                    width: frontness.width,
                    height: frontness.height
                )
                if configuration.instanceDilateRadius > 0 {
                    mask = mask.dilated(radius: configuration.instanceDilateRadius)
                }
                let area = mask.areaRatio(threshold: configuration.maskThreshold)
                guard area > 0.002 else { continue }
                result.append(
                    InstanceCandidate(
                        id: nextID,
                        mask: mask,
                        boundingBox: mask.boundingBox(threshold: configuration.maskThreshold),
                        areaRatio: area,
                        frontness: mask.mean(of: frontness, threshold: configuration.maskThreshold),
                        centroid: mask.centroid(threshold: configuration.maskThreshold)
                    )
                )
                nextID += 1
            } catch {
                continue
            }
        }
        return result
    }

    private static func fallbackInstance(
        from frontness: MaskBuffer,
        configuration: BoxArtDecomposer.Configuration
    ) -> InstanceCandidate? {
        let mask = frontness.thresholded(90)
        let area = mask.areaRatio(threshold: configuration.maskThreshold)
        guard area > 0.02 else { return nil }
        return InstanceCandidate(
            id: 1,
            mask: mask,
            boundingBox: mask.boundingBox(threshold: configuration.maskThreshold),
            areaRatio: area,
            frontness: 0.8,
            centroid: mask.centroid(threshold: configuration.maskThreshold)
        )
    }

    static func pixelRect(from normalized: CGRect, width: Int, height: Int) -> CGRect {
        CGRect(
            x: normalized.origin.x * CGFloat(width),
            y: (1 - normalized.origin.y - normalized.height) * CGFloat(height),
            width: normalized.width * CGFloat(width),
            height: normalized.height * CGFloat(height)
        )
    }

    static func isChromeText(_ string: String) -> Bool {
        let folded = string.lowercased()
        return chromeKeywords.contains { folded.contains($0) }
    }

    static func isPromotionalText(_ string: String) -> Bool {
        let folded = string.lowercased()
        let phrases = [
            "bonus", "included", "link it up", "players", "e-reader",
            "see back", "power-up", "game pak", "gamepak",
        ]
        return phrases.contains { folded.contains($0) }
    }
}
