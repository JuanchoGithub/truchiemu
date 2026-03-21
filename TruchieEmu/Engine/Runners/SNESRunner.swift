import Foundation
import MetalKit
import SwiftUI

// Restate inherited @unchecked Sendable from EmulatorRunner to satisfy Swift 6 concurrency checks.
// Marked final to avoid subclassing which simplifies Sendable reasoning.
final class SNESRunner: EmulatorRunner, @unchecked Sendable {
    // SNES specific overrides
    override func mapPixelFormat(_ format: Int) -> MTLPixelFormat {
        // SNES cores often use 16-bit 0RGB1555 (format 0 in libretro) or 565 (format 2).
        // Our bridge gives us the core reported format.
        switch format {
        case 0: return .a1bgr5Unorm // 16-bit 0RGB1555 -> a1bgr5 (bits map to 5-bit R,G,B)
        case 2: return .b5g6r5Unorm // 16-bit RGB565
        default: return .bgra8Unorm // Fallback (e.g. core using 32-bit colors)
        }
    }
    
    // SNES might need handling for specific V-resolutions (Axelay High-Res)
    // The base runner handles this by re-creating texture if width/height changed.
}

