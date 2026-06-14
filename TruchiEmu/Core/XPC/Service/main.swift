import Foundation

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
