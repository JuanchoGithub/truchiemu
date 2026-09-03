import Foundation
import AppKit
import Combine
import GameController

/// Listens for new gamepad connections and posts a
/// `.newGamepadConnected` notification with the controller's UUID so SwiftUI
/// overlays can present the test sheet.
///
/// Per-user preference: only the first time a given vendor name is seen
/// (`AppSettings.controllers_seen_vendor_names`). Reconnects of the same
/// vendor model don't re-pop. The user can re-trigger manually from the
/// controller settings page or reset the seen-set via the
/// `ControllerInputObserver.resetSeenVendors()` API.
///
/// Suppressed during:
/// - the first 2s after app launch (let startup settle)
/// - when a game is running (don't interrupt gameplay)
@MainActor
final class NewGamepadPresenter {
    static let shared = NewGamepadPresenter()

    private var cancellables = Set<AnyCancellable>()
    private var appLaunchTime: Date = Date()
    private var connectedAtStartup: Set<String> = []

    private init() {}

    /// Begin observing connection events. Call once at app launch.
    func start() {
        appLaunchTime = Date()
        // Snapshot already-connected controllers so reconnects on launch
        // don't count as "new" — only controllers that connect AFTER
        // startup trigger the test sheet.
        connectedAtStartup = currentVendorNames()

        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .sink { [weak self] _ in self?.handleNewController() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .sdlControllerConnected)
            .sink { [weak self] _ in self?.handleNewController() }
            .store(in: &cancellables)
    }

    private func handleNewController() {
        // Suppress during the 2s startup window.
        guard Date().timeIntervalSince(appLaunchTime) > 2.0 else { return }
        // Suppress when a game is running.
        if RunningGamesTracker.shared.isGameRunning { return }
        // Only consider GC controllers / SDL — not the keyboard.
        let candidates = currentGamepadVendors()
        for vendor in candidates where !connectedAtStartup.contains(vendor) {
            guard !ControllerInputObserver.hasSeenVendor(vendor) else {
                connectedAtStartup.insert(vendor)
                continue
            }
            // Find the PlayerController for this vendor to pass its UUID.
            guard let player = ControllerService.shared.connectedControllers.first(where: { p in
                !p.isKeyboard && (p.gcController?.vendorName == vendor || p.sdlName == vendor)
            }) else { continue }
            connectedAtStartup.insert(vendor)
            ControllerInputObserver.markVendorSeen(vendor)
            NotificationCenter.default.post(
                name: .newGamepadConnected,
                object: nil,
                userInfo: ["playerID": player.id]
            )
        }
    }

    private func currentVendorNames() -> Set<String> {
        var names: Set<String> = []
        for gc in GCController.controllers() {
            if let n = gc.vendorName { names.insert(n) }
        }
        return names
    }

    private func currentGamepadVendors() -> Set<String> {
        currentVendorNames()
    }
}
