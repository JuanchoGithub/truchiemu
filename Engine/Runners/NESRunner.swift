import Foundation
import MetalKit
import SwiftUI

/// NESRunner inherits thread-safe behavior from EmulatorRunner but contains reference semantics.
/// We restate the inherited `@unchecked Sendable` conformance to satisfy the compiler and document intent.
/// Ensure any added mutable state is properly synchronized.
final class NESRunner: EmulatorRunner, @unchecked Sendable {
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
