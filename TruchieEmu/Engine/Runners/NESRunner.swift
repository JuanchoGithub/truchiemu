import Foundation
import MetalKit
import SwiftUI

class NESRunner: EmulatorRunner {
    // NES specific overrides
    override func mapPixelFormat(_ format: Int) -> MTLPixelFormat {
        // NES cores usually use RGB8888, but let's handle 16-bit just in case
        switch format {
        case 0: return .a1bgr5Unorm
        case 2: return .b5g6r5Unorm
        default: return .bgra8Unorm
        }
    }

}
