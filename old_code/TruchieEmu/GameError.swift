import Foundation

// Represents various errors that can occur during game emulation.
enum GameError: Error, LocalizedError {
    case coreNotFound(coreID: String)
    case launchFailed(reason: String)
    case timeout(message: String)
    case saveStateError(reason: String)
    case loadStateError(reason: String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .coreNotFound(let coreID):
            return "Core not found: \(coreID)"
        case .launchFailed(let reason):
            return "Launch failed: \(reason)"
        case .timeout(let message):
            return "Timeout: \(message)"
        case .saveStateError(let reason):
            return "Save state error: \(reason)"
        case .loadStateError(let reason):
            return "Load state error: \(reason)"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}