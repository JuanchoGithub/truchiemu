import Foundation

// Suyu (yuzu lineage) renders through MoltenVK (Vulkan to Metal). Some Switch
// games bind integer (RGBA32Uint) and stencil (X32_Stencil8) textures where the
// translated MSL expects float. Metal API validation aborts on that mismatch,
// which freezes the core thread and trips the XPC watchdog. Log and continue
// instead. This must run before any MTLDevice exists in this process.
setenv("MTL_DEBUG_LAYER_ERROR_MODE", "nslog", 1)

LibretroBridge.registerCoreLogger { messagePtr, level in
    guard let message = String(cString: messagePtr, encoding: .utf8) else { return }
    let category = "LibretroCore"
    switch level {
    case 0: // RETRO_LOG_INFO
        LoggerService.info(category: category, message)
    case 1: // RETRO_LOG_WARN
        LoggerService.info(category: category, message)
    case 2: // RETRO_LOG_ERROR
        LoggerService.error(category: category, message)
    default:
        #if LOG_DEBUG
        LoggerService.debug(category: category, message)
        #endif
    }
}

let service = CoreHostService()
