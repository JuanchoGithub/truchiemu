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

    /// The value of `autoFullscreenEnabled` that was in effect before the user
    /// entered TV Mode. TV Mode forces auto-fullscreen on for any game it
    /// launches (which always open behind the fullscreen TV-mode window
    /// otherwise); when the user leaves TV Mode we restore this prior value
    /// so the main-window launch behavior is unchanged.
    private var priorAutoFullscreen: Bool?

    private init() {
        self.isActive = TVModeSettings.launchInTVMode
        if isActive {
            // Started in TV-mode (persisted launch flag) — mirror enter()'s
            // autoFs save/restore so the main-window behavior is restored
            // when the user leaves TV-mode later.
            priorAutoFullscreen = AppSettings.getBool("autoFullscreenEnabled", defaultValue: false)
            AppSettings.setBool("autoFullscreenEnabled", value: true)
        }
    }

    func toggle() {
        if isActive { exitMode() } else { enter() }
    }

    func enter() {
        guard !isActive else { return }
        if priorAutoFullscreen == nil {
            priorAutoFullscreen = AppSettings.getBool("autoFullscreenEnabled", defaultValue: false)
        }
        AppSettings.setBool("autoFullscreenEnabled", value: true)
        isActive = true
    }

    func exitMode() {
        guard isActive else { return }
        isActive = false
        if let prior = priorAutoFullscreen {
            AppSettings.setBool("autoFullscreenEnabled", value: prior)
            priorAutoFullscreen = nil
        }
    }
}
