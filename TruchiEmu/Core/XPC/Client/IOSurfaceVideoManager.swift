import Foundation
import IOSurface
import Metal
import CoreVideo

final class IOSurfaceVideoManager {
    private var surface: IOSurface?
    private var textureCache: CVMetalTextureCache?
    private var cvTexture: CVMetalTexture?
    private(set) var currentWidth: Int = 0
    private(set) var currentHeight: Int = 0
    private(set) var currentFormat: Int = 0

    func createSurface(width: Int, height: Int, format: Int) -> IOSurface? {
        if let existing = surface,
           existing.width == width,
           existing.height == height {
            return existing
        }

        let bpp: Int
        let surfaceFormat: OSType
        switch format {
        case 0:
            bpp = 2
            surfaceFormat = kCVPixelFormatType_16LE555
        case 1:
            bpp = 4
            surfaceFormat = kCVPixelFormatType_32BGRA
        case 2:
            bpp = 2
            surfaceFormat = kCVPixelFormatType_16LE565
        default:
            bpp = 4
            surfaceFormat = kCVPixelFormatType_32BGRA
        }

        let props: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerRow: width * bpp,
            .pixelFormat: Int(surfaceFormat),
            .allocSize: width * height * bpp
        ]

        guard let newSurface = IOSurface(properties: props) else {
            LoggerService.error(category: "IOSurface", "Failed to create IOSurface \(width)x\(height)")
            return nil
        }

        surface = newSurface
        currentWidth = width
        currentHeight = height
        currentFormat = format

        cvTexture = nil
        LoggerService.info(category: "IOSurface", "Created surface: \(width)x\(height) format=\(format)")
        return newSurface
    }

    func getMetalTexture(device: MTLDevice, width: Int, height: Int, format: Int) -> MTLTexture? {
        guard let surface = surface else { return nil }

        if surface.width != width || surface.height != height || currentFormat != format {
            _ = createSurface(width: width, height: height, format: format)
            cvTexture = nil
        }

        if textureCache == nil {
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        }

        if let cache = textureCache, cvTexture == nil || width != currentWidth || height != currentHeight {
            let mtFormat: MTLPixelFormat
            switch format {
            case 0: mtFormat = .a1bgr5Unorm
            case 1: mtFormat = .bgra8Unorm
            case 2: mtFormat = .b5g6r5Unorm
            default: mtFormat = .bgra8Unorm
            }

            var imageBuffer: CVImageBuffer?
            let pixelBufferRef = UnsafeMutablePointer<Unmanaged<CVPixelBuffer>?>.allocate(capacity: 1)
            defer { pixelBufferRef.deallocate() }

            let err = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil, pixelBufferRef)
            guard err == kCVReturnSuccess, let pixelBuffer = pixelBufferRef.pointee?.takeUnretainedValue() else {
                LoggerService.error(category: "IOSurface", "Failed to create CVPixelBuffer from IOSurface: \(err)")
                return nil
            }
            imageBuffer = pixelBuffer

            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                cache,
                imageBuffer!,
                nil,
                mtFormat,
                width,
                height,
                0,
                &cvTexture
            )

            guard status == kCVReturnSuccess else {
                LoggerService.error(category: "IOSurface", "Failed to create MTLTexture from IOSurface: \(status)")
                return nil
            }
        }

        guard let tex = cvTexture else { return nil }
        return CVMetalTextureGetTexture(tex)
    }

    func lock() {
        surface?.lock(options: [], seed: nil)
    }

    func unlock() {
        surface?.unlock(options: [], seed: nil)
    }

    func getCurrentSurface() -> IOSurface? {
        surface
    }

    func cleanup() {
        cvTexture = nil
        textureCache = nil
        surface = nil
        currentWidth = 0
        currentHeight = 0
    }

    deinit {
        cleanup()
    }
}
