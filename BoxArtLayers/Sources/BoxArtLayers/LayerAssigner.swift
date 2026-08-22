import CoreGraphics
import Foundation

struct AssignedLayers {
    var hero: MaskBuffer
    var title: MaskBuffer
    var midground: MaskBuffer
    var background: MaskBuffer
    var chrome: MaskBuffer
    var frozen: MaskBuffer
    var instances: [InstanceCandidate]
    var roles: [Int: LayerRole]
    var quality: QualityReport
}

enum LayerAssigner {
    static func assign(
        _ scene: SceneAnalysis,
        configuration: BoxArtDecomposer.Configuration
    ) -> AssignedLayers {
        let threshold = configuration.maskThreshold
        let empty = MaskBuffer(width: scene.width, height: scene.height)
        var roles: [Int: LayerRole] = [:]
        var instances = InstanceSplitter.explode(scene, configuration: configuration)

        let chrome = scene.chromeHint
        let imageHeight = Double(scene.height)
        let sky = skyMask(frontness: scene.frontness, chrome: chrome, threshold: threshold)

        for index in instances.indices {
            let overlap = instances[index].mask.intersecting(chrome).areaRatio(threshold: threshold)
            if overlap > instances[index].areaRatio * 0.65 {
                roles[instances[index].id] = .chrome
            }
        }

        let artInstances = instances.indices.filter { roles[instances[$0].id] == nil }
        let lower = artInstances.filter { index in
            let ny = instances[index].centroid.y / Double(scene.height)
            return ny > configuration.titleBand.lowerBound + 0.18 || instances[index].areaRatio > 0.12
        }
        let pool = lower.isEmpty ? artInstances : lower
        let heroIndex = pool.max { lhs, rhs in
            score(instances[lhs]) < score(instances[rhs])
        }

        if let heroIndex {
            roles[instances[heroIndex].id] = .hero
        }

        var title = rasterizeTitle(scene: scene, configuration: configuration)

        for index in instances.indices where roles[instances[index].id] == nil {
            let candidate = instances[index]
            let ny = candidate.centroid.y / imageHeight
            let overlapTitle = candidate.mask.intersecting(title).areaRatio(threshold: threshold)
            let inBand = configuration.titleBand.contains(ny)
            let wide = candidate.boundingBox.width > candidate.boundingBox.height * 1.35
            if overlapTitle > candidate.areaRatio * 0.25 || (inBand && wide && candidate.areaRatio < 0.22) {
                roles[candidate.id] = .title
                title = title.union(candidate.mask)
            }
        }

        for index in instances.indices where roles[instances[index].id] == nil {
            roles[instances[index].id] = .midground
        }

        var hero = empty
        var mid = empty
        var extraChrome = empty
        for instance in instances {
            switch roles[instance.id] {
            case .hero:
                hero = hero.union(instance.mask)
            case .title:
                title = title.union(instance.mask)
            case .chrome:
                extraChrome = extraChrome.union(instance.mask)
            default:
                mid = mid.union(instance.mask)
            }
        }

        let chromeMask = chrome.union(extraChrome)
        hero = hero.subtracting(chromeMask).subtracting(sky)
        title = title.subtracting(hero).subtracting(chromeMask).subtracting(sky)
        mid = mid.subtracting(hero).subtracting(title).subtracting(chromeMask).subtracting(sky)
        // Background = the full frame minus hero, title, chrome. Midground is
        // intentionally NOT subtracted: we ignore midground and keep it as part
        // of the background.
        let background = empty.inverted()
            .subtracting(hero)
            .subtracting(title)
            .subtracting(chromeMask)
        let frozen = hero.union(title).union(chromeMask)

        let heroRatio = hero.areaRatio(threshold: threshold)
        var reasons: [String] = []
        if instances.isEmpty { reasons.append("no-instances") }
        if heroRatio < configuration.heroMinAreaRatio { reasons.append("hero-too-small") }
        if heroRatio > configuration.heroMaxAreaRatio { reasons.append("hero-too-large") }
        let titleDetected = title.area(threshold: threshold) > 0
        if !titleDetected { reasons.append("title-missing") }

        let quality = QualityReport(
            needsReview: !reasons.isEmpty,
            reasons: reasons,
            heroAreaRatio: heroRatio,
            titleDetected: titleDetected,
            instanceCount: instances.count
        )

        for index in instances.indices {
            instances[index].mask = instances[index].mask.subtracting(chromeMask)
        }

        return AssignedLayers(
            hero: hero,
            title: title,
            midground: mid,
            background: background,
            chrome: chromeMask,
            frozen: frozen,
            instances: instances,
            roles: roles,
            quality: quality
        )
    }

    private static func score(_ instance: InstanceCandidate) -> Double {
        // After splitting oversized Vision blobs, the character is the *closest*
        // piece, not the largest leftover landscape.
        if instance.areaRatio < 0.04 {
            return instance.frontness * 0.15
        }
        return instance.frontness * 2.0 + instance.areaRatio
    }

    /// Smooth sky / backdrop: low attention, not chrome.
    static func skyMask(frontness: MaskBuffer, chrome: MaskBuffer, threshold: UInt8) -> MaskBuffer {
        var samples: [UInt8] = []
        samples.reserveCapacity(frontness.pixels.count / 2)
        for i in 0..<frontness.pixels.count where chrome.pixels[i] < threshold {
            samples.append(frontness.pixels[i])
        }
        let cut: UInt8
        if samples.isEmpty {
            cut = 70
        } else {
            samples.sort()
            cut = samples[min(samples.count - 1, samples.count * 32 / 100)]
        }
        var sky = MaskBuffer(width: frontness.width, height: frontness.height)
        for i in 0..<frontness.pixels.count {
            if chrome.pixels[i] < threshold, frontness.pixels[i] <= cut {
                sky.pixels[i] = 255
            }
        }
        return sky
    }

    static func rasterizeTitle(
        scene: SceneAnalysis,
        configuration: BoxArtDecomposer.Configuration
    ) -> MaskBuffer {
        var mask = MaskBuffer(width: scene.width, height: scene.height)
        let height = Double(scene.height)
        for hit in scene.text {
            if VisionAnalyzer.isChromeText(hit.string) { continue }
            if VisionAnalyzer.isPromotionalText(hit.string) { continue }
            let ny = hit.boundingBox.midY / height
            guard configuration.titleBand.contains(ny) else { continue }
            mask.fill(hit.boundingBox.insetBy(dx: -6, dy: -4))
        }
        if configuration.titleDilateRadius > 0 {
            mask = mask.dilated(radius: configuration.titleDilateRadius)
        }
        return mask
    }
}
