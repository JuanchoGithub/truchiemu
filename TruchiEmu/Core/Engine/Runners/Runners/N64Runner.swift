import Foundation
import MetalKit
import SwiftUI

final class N64Runner: EmulatorRunner, @unchecked Sendable {
    override func mapPixelFormat(_ format: Int) -> MTLPixelFormat {
        switch format {
        case 0: return .a1bgr5Unorm // 0RGB1555 (A1R5G5B5 on LE)
        case 1: return .bgra8Unorm  // XRGB8888 (BGRA on LE)
        case 2: return .b5g6r5Unorm // RGB565
        default: return .bgra8Unorm
        }
    }

}
