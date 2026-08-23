import AppKit
import CoreGraphics
import Foundation

// Computes a representative background colour for a box-art image, used by the
// Reverse Holo variant's `.background` colour mode to tint the foil pattern
// with the card's own art. Implemented as a cheap downscaled average (a
// 16×16 draw + pixel mean) — representative enough as a tint, far cheaper
// than a full Vision decompose. Results are cached per romID so cursor-driven
// re-renders of the holo layers never recompute it.
enum HoloColorSampler {
    // Accessed only from the main actor (the card view's render path), so a
    // plain dictionary is safe without locking.
    private static var cache: [String: [Float]] = [:]
    private static let sampleSize = CGSize(width: 16, height: 16)

    /// Average sRGB colour of `image` as `[r, g, b]` (0..1). Cached per
    /// `romID`; pass the same `romID` on subsequent calls to hit the cache.
    /// Returns nil if the image cannot be rasterised.
    static func medianRGB(romID: String, image: NSImage) -> [Float]? {
        if let cached = cache[romID] { return cached }
        guard let result = compute(image) else { return nil }
        cache[romID] = result
        return result
    }

    private static func compute(_ image: NSImage) -> [Float]? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = Int(sampleSize.width)
        let h = Int(sampleSize.height)
        let bytesPerRow = 4 * w
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * h)
        guard let ctx = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(origin: .zero, size: sampleSize))

        var r: Double = 0, g: Double = 0, b: Double = 0
        let count = w * h
        for i in 0..<count {
            let o = i * 4
            r += Double(pixels[o]) / 255.0
            g += Double(pixels[o + 1]) / 255.0
            b += Double(pixels[o + 2]) / 255.0
        }
        return [Float(r / Double(count)), Float(g / Double(count)), Float(b / Double(count))]
    }
}
