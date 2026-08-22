import CoreGraphics
import Foundation

enum PreviewRenderer {
    static func render(
        sourceRGBA: [UInt8],
        assigned: AssignedLayers,
        threshold: UInt8
    ) -> CGImage {
        let width = assigned.hero.width
        let height = assigned.hero.height
        var out = [UInt8](repeating: 0, count: width * height * 4)

        for i in 0..<(width * height) {
            let si = i * 4
            let r = sourceRGBA[si]
            let g = sourceRGBA[si + 1]
            let b = sourceRGBA[si + 2]
            let tint: (UInt8, UInt8, UInt8)
            if assigned.hero.pixels[i] >= threshold {
                tint = (220, 64, 64)
            } else if assigned.title.pixels[i] >= threshold {
                tint = (230, 200, 40)
            } else if assigned.chrome.pixels[i] >= threshold {
                tint = (160, 160, 170)
            } else if assigned.midground.pixels[i] >= threshold {
                tint = (48, 180, 96)
            } else {
                tint = (48, 110, 210)
            }
            out[si] = mix(r, tint.0)
            out[si + 1] = mix(g, tint.1)
            out[si + 2] = mix(b, tint.2)
            out[si + 3] = 255
        }
        return ImageIOSupport.rgbaImage(width: width, height: height, pixels: out)
    }

    private static func mix(_ original: UInt8, _ tint: UInt8) -> UInt8 {
        UInt8((Int(original) * 45 + Int(tint) * 55) / 100)
    }
}
