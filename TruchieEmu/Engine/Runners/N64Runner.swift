import Foundation
import MetalKit
import SwiftUI

final class N64Runner: EmulatorRunner, @unchecked Sendable {
    override func mapPixelFormat(_ format: Int) -> MTLPixelFormat {
        // N64 often uses 32-bit for hardware rendering
        return .bgra8Unorm
    }

}
