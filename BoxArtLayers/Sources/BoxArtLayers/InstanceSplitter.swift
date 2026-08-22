import Foundation

enum InstanceSplitter {
    /// Vision often lifts a whole painted cover as one subject. Split oversized
    /// blobs using frontness so the hero is the character, not the landscape.
    static func explode(
        _ scene: SceneAnalysis,
        configuration: BoxArtDecomposer.Configuration
    ) -> [InstanceCandidate] {
        let titleHint = LayerAssigner.rasterizeTitle(scene: scene, configuration: configuration)
        let minPixels = max(16, Int(Double(scene.width * scene.height) * 0.006))
        var nextID = (scene.instances.map(\.id).max() ?? 0) + 1
        var output: [InstanceCandidate] = []

        for instance in scene.instances {
            let remainder = instance.mask
                .subtracting(scene.chromeHint)
                .subtracting(titleHint)

            let parts: [MaskBuffer]
            if instance.areaRatio > configuration.heroMaxAreaRatio {
                parts = splitByFrontness(
                    remainder,
                    frontness: scene.frontness,
                    configuration: configuration,
                    minPixels: minPixels
                )
            } else {
                parts = [remainder]
            }

            for mask in parts {
                let area = mask.areaRatio(threshold: configuration.maskThreshold)
                guard area > 0.006 else { continue }
                output.append(
                    InstanceCandidate(
                        id: nextID,
                        mask: mask,
                        boundingBox: mask.boundingBox(threshold: configuration.maskThreshold),
                        areaRatio: area,
                        frontness: mask.mean(of: scene.frontness, threshold: configuration.maskThreshold),
                        centroid: mask.centroid(threshold: configuration.maskThreshold)
                    )
                )
                nextID += 1
            }
        }

        return output.isEmpty ? scene.instances : output
    }

    static func splitByFrontness(
        _ remainder: MaskBuffer,
        frontness: MaskBuffer,
        configuration: BoxArtDecomposer.Configuration,
        minPixels: Int
    ) -> [MaskBuffer] {
        var samples: [UInt8] = []
        for i in 0..<remainder.pixels.count where remainder.pixels[i] >= configuration.maskThreshold {
            samples.append(frontness.pixels[i])
        }
        guard !samples.isEmpty else { return [remainder] }
        samples.sort()

        var bestSeed: MaskBuffer?
        var bestDistance = Double.greatestFiniteMagnitude
        let target = (configuration.heroMinAreaRatio + configuration.heroMaxAreaRatio) / 2

        for percentile in [0.84, 0.76, 0.68, 0.60, 0.52, 0.44] {
            let index = min(samples.count - 1, Int(Double(samples.count - 1) * percentile))
            let cut = samples[index]
            var seed = MaskBuffer(width: remainder.width, height: remainder.height)
            for i in 0..<remainder.pixels.count {
                if remainder.pixels[i] >= configuration.maskThreshold, frontness.pixels[i] >= cut {
                    seed.pixels[i] = remainder.pixels[i]
                }
            }
            let core = seed.connectedComponents(
                threshold: configuration.maskThreshold,
                minArea: minPixels
            ).first
            guard let core else { continue }
            let area = core.areaRatio(threshold: configuration.maskThreshold)
            if area >= configuration.heroMinAreaRatio && area <= configuration.heroMaxAreaRatio {
                return pack(core: core, remainder: remainder, configuration: configuration, minPixels: minPixels)
            }
            let distance = abs(area - target)
            if distance < bestDistance {
                bestDistance = distance
                bestSeed = core
            }
        }

        if let bestSeed {
            return pack(core: bestSeed, remainder: remainder, configuration: configuration, minPixels: minPixels)
        }
        return remainder.connectedComponents(threshold: configuration.maskThreshold, minArea: minPixels)
    }

    private static func pack(
        core: MaskBuffer,
        remainder: MaskBuffer,
        configuration: BoxArtDecomposer.Configuration,
        minPixels: Int
    ) -> [MaskBuffer] {
        let leftover = remainder.subtracting(core)
        return [core] + leftover.connectedComponents(
            threshold: configuration.maskThreshold,
            minArea: minPixels
        )
    }
}
