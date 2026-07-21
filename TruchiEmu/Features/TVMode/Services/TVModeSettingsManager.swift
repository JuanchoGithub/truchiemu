import Foundation
import Combine
import SwiftUI

/// Single source of truth for whether TV Mode is currently active. Both the
/// View menu and ContentView read/observe this so the menu item always
/// reflects the current state and the swap is reliable across rebuilds.
@MainActor
final class TVModeSettingsManager: ObservableObject {
    static let shared = TVModeSettingsManager()

    @Published var isActive: Bool {
        didSet {
            AppSettings.setBool("tvMode_currentlyActive", value: isActive)
        }
    }

    private init() {
        self.isActive = TVModeSettings.launchInTVMode
    }

    func toggle() { isActive.toggle() }
    func enter() { isActive = true }
    func exitMode() { isActive = false }
}
