import Foundation

/// Loads bundled controller-preset JSON files from the app bundle
/// (`Resources/ControllerPresets/*.json`) at startup so new users on the same
/// brand/model hardware start from a curated default mapping instead of the
/// generic system-driven `ControllerGamepadMapping.defaults(...)`.
///
/// Scope: app-wide, "default" system-ID slot only. Per-system or per-game
/// overrides are not shipped. Resolution precedence is handled by
/// `ControllerService` — user-saved `AppSettings` entries always win; bundled
/// data only fills gaps for identities the user has never customized.
@MainActor
enum BundledControllerPresets {
    /// Returns a tuple of dictionaries keyed by `ControllerIdentityKey.compositeKey`.
    static func load() -> (gc: [String: ControllerGamepadMapping], sdl: [String: SDLControllerMapping]) {
        var gc: [String: ControllerGamepadMapping] = [:]
        var sdl: [String: SDLControllerMapping] = [:]

        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let decoder = JSONDecoder()
        for url in urls {
            guard url.lastPathComponent.hasPrefix("controllerPreset_") else { continue }
            do {
                let data = try Data(contentsOf: url)
                let file = try decoder.decode(PresetFile.self, from: data)
                let compositeKey = file.identity.compositeKey
                if let mapping = file.gcMapping {
                    gc[compositeKey] = mapping
                }
                if let mapping = file.sdlMapping {
                    sdl[compositeKey] = mapping
                }
            } catch {
                #if LOG_DEBUG
                LoggerService.debug("BundledControllerPresets: failed to decode \(url.lastPathComponent): \(error)")
                #endif
            }
        }

        #if LOG_DEBUG
        LoggerService.debug("BundledControllerPresets: loaded \(gc.count) GC + \(sdl.count) SDL preset(s)")
        #endif
        return (gc, sdl)
    }

    private struct PresetFile: Codable {
        let identity: Identity
        let gcMapping: ControllerGamepadMapping?
        let sdlMapping: SDLControllerMapping?
    }

    private struct Identity: Codable {
        let inputSystem: InputSystem
        let productKey: String
        let vendorName: String?

        var compositeKey: String {
            let systemTag = inputSystem.rawValue
            let vendor = vendorName ?? ""
            return "\(systemTag)|\(productKey)|\(vendor)"
        }
    }
}
