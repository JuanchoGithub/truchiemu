import AppKit
import Metal

extension NSImage {
    // Resize the image to the specified size
    func resized(to targetSize: NSSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        
        self.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1.0
        )
        
        return newImage
    }
    
    // Convert MTLTexture to NSImage
    // - Parameters:
    //   - texture: The MTLTexture to convert
    //   - width: Width of the texture
    //   - height: Height of the texture
    // - Returns: NSImage representation, or nil on failure
    static func fromMTLTexture(_ texture: MTLTexture, width: Int, height: Int) -> NSImage? {
        // Create a CIImage from the texture
        let ciContext = CIContext(options: nil)
        
        // Use MTKTextureLoader to get a CIImage
        guard let textureLoader = try? MTKTextureLoader(device: MTLCreateSystemDefaultDevice()!),
              let cgImage = texture.toCGImage() else {
            return nil
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        guard let cgImageOut = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return NSImage(cgImage: cgImageOut, size: NSSize(width: width, height: height))
    }
}

extension MTLTexture {
    // Convert MTLTexture to CGImage
    func toCGImage() -> CGImage? {
        // Ensure texture is in a readable format
        guard pixelFormat == .bgra8Unorm || pixelFormat == .rgba8Unorm else {
            // For other formats, we'd need to convert first
            return nil
        }
        
        let width = self.width
        let height = self.height
        let byteCount = width * height * 4
        
        // Create a buffer to hold the texture data
        var byteArray = [UInt8](repeating: 0, count: byteCount)
        
        // Get the bytes from the texture
        let region = MTLRegionMake2D(0, 0, width, height)
        byteArray.withUnsafeMutableBytes { pointer in
            getBytes(pointer.baseAddress!, bytesPerRow: width * 4, from: region, mipmapLevel: 0)
        }
        
        // Create colorspace
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        
        // Create bitmap context
        guard let context = CGContext(
            data: byteArray,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: pixelFormat == .bgra8Unorm ? CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        return context.makeImage()
    }
}