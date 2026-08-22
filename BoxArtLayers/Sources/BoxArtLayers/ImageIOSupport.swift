import Accelerate
import CoreGraphics
import CoreImage
import CoreVideo
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageIOSupport {
    private static let rgbSpace = CGColorSpaceCreateDeviceRGB()
    private static let graySpace = CGColorSpaceCreateDeviceGray()

    static let ciContext = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false,
    ])

    static var rgbaFormat: vImage_CGImageFormat {
        vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: Unmanaged.passUnretained(rgbSpace),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                .union(.byteOrder32Big),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )
    }

    static var grayFormat: vImage_CGImageFormat {
        vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            colorSpace: Unmanaged.passUnretained(graySpace),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )
    }

    static func loadCGImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw BoxArtLayerError.invalidImage
        }
        // Bake EXIF/TIFF orientation into pixels so Vision always sees `.up`.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 8192,
        ]
        if let baked = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return baked
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BoxArtLayerError.invalidImage
        }
        return image
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw BoxArtLayerError.exportFailed("Could not create PNG destination at \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw BoxArtLayerError.exportFailed("Could not write PNG at \(url.path)")
        }
    }

    /// Top-left origin, RGBA_32Big. Matches PNG / CGImage, not Core Image's Y-up space.
    static func rgbaBytes(from image: CGImage) -> (width: Int, height: Int, pixels: [UInt8]) {
        var format = rgbaFormat
        var buffer = vImage_Buffer()
        let error = vImageBuffer_InitWithCGImage(
            &buffer,
            &format,
            nil,
            image,
            vImage_Flags(kvImageNoFlags)
        )
        guard error == kvImageNoError, let data = buffer.data else {
            return (image.width, image.height, [UInt8](repeating: 0, count: image.width * image.height * 4))
        }
        defer { free(data) }
        return compact(buffer: buffer, channels: 4)
    }

    static func grayscaleBytes(from image: CGImage) -> MaskBuffer {
        var format = grayFormat
        var buffer = vImage_Buffer()
        let error = vImageBuffer_InitWithCGImage(
            &buffer,
            &format,
            nil,
            image,
            vImage_Flags(kvImageNoFlags)
        )
        guard error == kvImageNoError, let data = buffer.data else {
            return MaskBuffer(width: image.width, height: image.height)
        }
        defer { free(data) }
        let packed = compact(buffer: buffer, channels: 1)
        return MaskBuffer(width: packed.width, height: packed.height, pixels: packed.pixels)
    }

    static func cgImage(from mask: MaskBuffer) -> CGImage {
        mask.pixels.withUnsafeBytes { raw in
            var buffer = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: raw.baseAddress!),
                height: vImagePixelCount(mask.height),
                width: vImagePixelCount(mask.width),
                rowBytes: mask.width
            )
            var format = grayFormat
            var error: vImage_Error = kvImageNoError
            let image = vImageCreateCGImageFromBuffer(
                &buffer,
                &format,
                nil,
                nil,
                vImage_Flags(kvImageNoFlags),
                &error
            )
            return image!.takeRetainedValue()
        }
    }

    static func cutout(sourceRGBA: [UInt8], mask: MaskBuffer) -> CGImage {
        let width = mask.width
        let height = mask.height
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let a = mask.pixels[i]
            if a == 0 { continue }
            let si = i * 4
            out[si] = sourceRGBA[si]
            out[si + 1] = sourceRGBA[si + 1]
            out[si + 2] = sourceRGBA[si + 2]
            out[si + 3] = a
        }
        return rgbaImage(width: width, height: height, pixels: out)
    }

    static func rgbaImage(width: Int, height: Int, pixels: [UInt8]) -> CGImage {
        pixels.withUnsafeBytes { raw in
            var buffer = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: raw.baseAddress!),
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: width * 4
            )
            var format = rgbaFormat
            var error: vImage_Error = kvImageNoError
            let image = vImageCreateCGImageFromBuffer(
                &buffer,
                &format,
                nil,
                nil,
                vImage_Flags(kvImageNoFlags),
                &error
            )
            return image!.takeRetainedValue()
        }
    }

    /// Vision / CVPixelBuffer is top-left, same as CGImage. Do not round-trip through CI.
    static func mask(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> MaskBuffer {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let srcW = CVPixelBufferGetWidth(pixelBuffer)
        let srcH = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard srcW > 0, srcH > 0, let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return MaskBuffer(width: width, height: height)
        }

        var output = MaskBuffer(width: width, height: height)
        if srcW == width, srcH == height {
            for y in 0..<height {
                for x in 0..<width {
                    output.pixels[y * width + x] = sampleLuma(
                        base: base,
                        format: format,
                        x: x,
                        y: y,
                        stride: stride
                    )
                }
            }
        } else {
            let xDen = Float(max(width - 1, 1))
            let yDen = Float(max(height - 1, 1))
            for y in 0..<height {
                let fy = Float(y) * Float(srcH - 1) / yDen
                let y0 = Int(fy)
                let y1 = min(srcH - 1, y0 + 1)
                let ty = fy - Float(y0)
                for x in 0..<width {
                    let fx = Float(x) * Float(srcW - 1) / xDen
                    let x0 = Int(fx)
                    let x1 = min(srcW - 1, x0 + 1)
                    let tx = fx - Float(x0)
                    let v00 = Float(sampleLuma(base: base, format: format, x: x0, y: y0, stride: stride))
                    let v10 = Float(sampleLuma(base: base, format: format, x: x1, y: y0, stride: stride))
                    let v01 = Float(sampleLuma(base: base, format: format, x: x0, y: y1, stride: stride))
                    let v11 = Float(sampleLuma(base: base, format: format, x: x1, y: y1, stride: stride))
                    let v = v00 * (1 - tx) * (1 - ty) + v10 * tx * (1 - ty)
                        + v01 * (1 - tx) * ty + v11 * tx * ty
                    output.pixels[y * width + x] = UInt8(clamping: Int(v.rounded()))
                }
            }
        }
        return output
    }

    private static func compact(buffer: vImage_Buffer, channels: Int) -> (width: Int, height: Int, pixels: [UInt8]) {
        let width = Int(buffer.width)
        let height = Int(buffer.height)
        let rowBytes = buffer.rowBytes
        let dstStride = width * channels
        var pixels = [UInt8](repeating: 0, count: height * dstStride)
        let src = buffer.data.bindMemory(to: UInt8.self, capacity: height * rowBytes)
        for y in 0..<height {
            let srcRow = src.advanced(by: y * rowBytes)
            let dstIndex = y * dstStride
            for i in 0..<dstStride {
                pixels[dstIndex + i] = srcRow[i]
            }
        }
        return (width, height, pixels)
    }

    private static func sampleLuma(
        base: UnsafeMutableRawPointer,
        format: OSType,
        x: Int,
        y: Int,
        stride: Int
    ) -> UInt8 {
        switch format {
        case kCVPixelFormatType_OneComponent8:
            return base.load(fromByteOffset: y * stride + x, as: UInt8.self)
        case kCVPixelFormatType_OneComponent16Half:
            let bits = base.load(fromByteOffset: y * stride + x * 2, as: UInt16.self)
            let sign: Float = (bits & 0x8000) != 0 ? -1.0 : 1.0
            let exp = Int(bits >> 10) & 0x1F
            let mant = Int(bits & 0x3FF)
            var value: Float
            if exp == 0 {
                value = Float(mant) * Float(pow(2.0, -24.0))
            } else if exp == 31 {
                value = mant == 0 ? .infinity : .nan
            } else {
                value = Float(mant + 1024) * Float(pow(2.0, Double(exp) - 25.0))
            }
            value *= sign
            let f = max(0, min(1, value))
            return UInt8(clamping: Int((f * 255).rounded()))
        case kCVPixelFormatType_OneComponent32Float:
            let value = base.load(fromByteOffset: y * stride + x * 4, as: Float32.self)
            let clamped = max(0, min(1, value))
            return UInt8(clamping: Int((clamped * 255).rounded()))
        case kCVPixelFormatType_32BGRA:
            let i = y * stride + x * 4
            let b = base.load(fromByteOffset: i, as: UInt8.self)
            let g = base.load(fromByteOffset: i + 1, as: UInt8.self)
            let r = base.load(fromByteOffset: i + 2, as: UInt8.self)
            return UInt8((Int(r) * 77 + Int(g) * 150 + Int(b) * 29) >> 8)
        default:
            let i = y * stride + x
            return base.load(fromByteOffset: i, as: UInt8.self)
        }
    }
}
