import Foundation
import AppKit
import Combine

/// Live snapshot of connected displays. Re-reads `NSScreen.screens` whenever
/// macOS posts `didChangeScreenParametersNotification` (display added,
/// removed, resolution change, arrangement change) so the picker always
/// reflects the user's current setup.
///
/// Exposes the descriptors as `@Published` so SwiftUI views observe changes
/// for free; the picker rebuilds its list when a screen is unplugged while
/// the overlay is on-screen.
@MainActor
final class ScreenCatalog: ObservableObject {
    static let shared = ScreenCatalog()

    @Published private(set) var screens: [ScreenDescriptor] = []
    @Published private(set) var mainScreenID: String?

    private var observer: NSObjectProtocol?

    private init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Hop back to MainActor explicitly — this closure lands on the
            // notification queue, and `refresh()` mutates `@Published` state
            // that must be touched on the main actor.
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Re-reads `NSScreen.screens`. Cheap (called rarely — only on display
    /// parameter changes) so no caching is needed.
    func refresh() {
        let descriptors = NSScreen.screens.compactMap(ScreenDescriptor.make(from:))
        screens = descriptors
        mainScreenID = NSScreen.main.flatMap { screen in
            descriptors.first(where: { $0.id == Self.idString(for: screen) })?.id
        }
    }

    /// Returns the descriptor matching the remembered screen id, falling back
    /// to `NSScreen.main` when the stored id no longer corresponds to an
    /// attached display (display unplugged between launches).
    func resolveRememberedOrMain() -> ScreenDescriptor? {
        if let stored = TVModeSettings.rememberedScreenID,
           let match = screens.first(where: { $0.id == stored }) {
            return match
        }
        if let mainID = mainScreenID {
            return screens.first(where: { $0.id == mainID })
        }
        return screens.first
    }

    /// Returns the main screen descriptor, or the first available screen when
    /// `NSScreen.main` reports nil (some headless configurations).
    var main: ScreenDescriptor? {
        if let mainID = mainScreenID, let match = screens.first(where: { $0.id == mainID }) {
            return match
        }
        return screens.first
    }

    private static func idString(for screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let n = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        return "\(n.uint32Value)"
    }
}
