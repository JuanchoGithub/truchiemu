import CoreGraphics
import Foundation

enum ChromeDetector {
    static func detect(
        image: CGImage,
        text: [TextHit],
        configuration: BoxArtDecomposer.Configuration
    ) -> MaskBuffer {
        let width = image.width
        let height = image.height
        var mask = MaskBuffer(width: width, height: height)
        let unpacked = ImageIOSupport.rgbaBytes(from: image)

        if let spineEnd = leftSpineEnd(
            rgba: unpacked.pixels,
            width: width,
            height: height,
            maxFraction: configuration.chromeLeftMaxFraction
        ) {
            for y in 0..<height {
                let row = y * width
                for x in 0..<spineEnd {
                    mask.pixels[row + x] = 255
                }
            }
        }

        for hit in text where VisionAnalyzer.isChromeText(hit.string) {
            guard isChromePlacement(hit.boundingBox, width: width, height: height) else { continue }
            mask.fill(hit.boundingBox.insetBy(dx: -4, dy: -4))
        }

        return mask.dilated(radius: 1)
    }

    /// Finds the x where a low-saturation left bar meets the painted art. Nil if no spine.
    static func leftSpineEnd(
        rgba: [UInt8],
        width: Int,
        height: Int,
        maxFraction: Double
    ) -> Int? {
        let maxX = max(4, Int(Double(width) * maxFraction))
        guard maxX < width / 2 else { return nil }

        var saturation = [Double](repeating: 0, count: maxX)
        for x in 0..<maxX {
            var sum = 0.0
            for y in 0..<height {
                let i = (y * width + x) * 4
                sum += saturationOf(r: rgba[i], g: rgba[i + 1], b: rgba[i + 2])
            }
            saturation[x] = sum / Double(height)
        }

        let bodyStart = min(width - 1, Int(Double(width) * 0.22))
        let bodyEnd = min(width, Int(Double(width) * 0.55))
        var bodySat = 0.0
        var bodyCount = 0
        for x in bodyStart..<bodyEnd {
            var sum = 0.0
            let sampleRows = stride(from: 0, to: height, by: max(1, height / 40))
            for y in sampleRows {
                let i = (y * width + x) * 4
                sum += saturationOf(r: rgba[i], g: rgba[i + 1], b: rgba[i + 2])
                bodyCount += 1
            }
            bodySat += sum
        }
        guard bodyCount > 0 else { return nil }
        bodySat /= Double(bodyCount)

        let leftSat = saturation.prefix(max(4, maxX / 3)).reduce(0, +) / Double(max(4, maxX / 3))
        // Spine is typically greyer (GBA silver) or a flat brand strip.
        guard leftSat + 0.08 < bodySat else { return nil }

        let threshold = (leftSat + bodySat) / 2
        var edge = 0
        for x in 2..<maxX {
            if saturation[x] > threshold, saturation[x] - saturation[x - 1] > 0.015 {
                edge = x
                break
            }
        }
        if edge == 0 {
            edge = saturation.enumerated().min(by: { abs($0.element - threshold) < abs($1.element - threshold) })?.offset ?? 0
        }
        let clamped = min(maxX, max(6, edge + 1))
        return clamped
    }

    static func isChromePlacement(_ rect: CGRect, width: Int, height: Int) -> Bool {
        let nx = rect.midX / CGFloat(width)
        let ny = rect.midY / CGFloat(height)
        if nx < 0.20 { return true }
        if ny > 0.78 && nx < 0.48 { return true }
        if ny > 0.70 && nx > 0.62 { return true }
        return false
    }

    static func saturationOf(r: UInt8, g: UInt8, b: UInt8) -> Double {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let maxC = max(rf, gf, bf)
        let minC = min(rf, gf, bf)
        guard maxC > 0.001 else { return 0 }
        return (maxC - minC) / maxC
    }
}
