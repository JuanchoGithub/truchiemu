import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotResult {
    let url: URL
    let width: Int
    let height: Int
    let capturedAt: Date
}

enum ScreenshotService {
    static var baseDirectory: URL {
        if let customPath = AppSettings.getString("screenshot_output_path"), !customPath.isEmpty {
            return URL(fileURLWithPath: customPath)
        }
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("TruchiEmu", isDirectory: true)
    }

    static func directory(for systemID: String) -> URL {
        if let customPath = AppSettings.getString("screenshot_output_path"), !customPath.isEmpty {
            return URL(fileURLWithPath: customPath)
        }
        let safeSystem = sanitizeFilename(systemID.isEmpty ? "default" : systemID)
        return baseDirectory.appendingPathComponent(safeSystem, isDirectory: true)
    }

    static func url(for romName: String, systemID: String, date: Date = Date(), suffix: String? = nil) -> URL {
        let dir = directory(for: systemID)
        let rom = sanitizeFilename(romName.isEmpty ? "screenshot" : romName)
        let stamp = timestamp(for: date)
        let fileName = suffix.map { "\(rom)_\(stamp)\($0).png" } ?? "\(rom)_\(stamp).png"
        return dir.appendingPathComponent(fileName)
    }

    @MainActor
    static func capture(from texture: MTLTexture, romName: String, systemID: String, suffix: String? = nil) -> ScreenshotResult? {
        guard let image = NSImageFromMTLTexture(texture) else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let url = self.url(for: romName, systemID: systemID, suffix: suffix)
        let dir = url.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            LoggerService.error(category: "Screenshot", "Failed to create directory: \(error.localizedDescription)")
            return nil
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            LoggerService.error(category: "Screenshot", "Failed to create CGImageDestination: \(url.path)")
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            LoggerService.error(category: "Screenshot", "Failed to finalize PNG: \(url.path)")
            return nil
        }

        return ScreenshotResult(
            url: url,
            width: cgImage.width,
            height: cgImage.height,
            capturedAt: Date()
        )
    }

    static func sanitizeFilename(_ raw: String) -> String {
        let invalid: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\0"]
        let cleaned = raw.filter { !invalid.contains($0) }.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = cleaned.count > 80 ? String(cleaned.prefix(80)) : cleaned
        return truncated.isEmpty ? "screenshot" : truncated
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()

    static func timestamp(for date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    static func delete(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            LoggerService.error(category: "Screenshot", "Failed to delete: \(error.localizedDescription)")
            return false
        }
    }

    nonisolated(unsafe) static func writeBGRA(_ bgra: [UInt8], width: Int, height: Int, to url: URL) {
        guard width > 0, height > 0, !bgra.isEmpty else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height

        let provider = CGDataProvider(data: Data(bgra) as CFData)
        guard let provider = provider,
              let cs = colorSpace,
              let cgImage = CGImage(width: width, height: height,
                                     bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: bytesPerRow, space: cs,
                                     bitmapInfo: bitmapInfo,
                                     provider: provider,
                                     decode: nil, shouldInterpolate: false,
                                     intent: .defaultIntent) else {
            LoggerService.error(category: "Screenshot", "Failed to build CGImage for \(url.path)")
            return
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                          UTType.png.identifier as CFString,
                                                          1, nil) else {
            LoggerService.error(category: "Screenshot", "Failed to create PNG destination: \(url.path)")
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        if !CGImageDestinationFinalize(dest) {
            LoggerService.error(category: "Screenshot", "Failed to finalize PNG: \(url.path)")
        }
        _ = totalBytes
    }
}
