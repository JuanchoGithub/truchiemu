import Foundation
import Combine
import SwiftUI
import AppKit

/// Single source of truth for whether TV Mode is currently active. Both the
/// View menu and ContentView read/observe this so the menu item always
/// reflects the current state and the swap is reliable across rebuilds.
///
/// Also owns the screen-selection state machine. Every entry path (menu,
/// gamepad combo, library grid, cold-start resume) funnels through
/// `requestScreenSelection()` so the picker, remembered screen, and origin
/// capture behave identically no matter how the user got into TV mode.
@MainActor
final class TVModeSettingsManager: ObservableObject {
    static let shared = TVModeSettingsManager()

    @Published var isActive: Bool {
        didSet {
            AppSettings.setBool("tvMode_currentlyActive", value: isActive)
        }
    }

    /// Non-nil while the screen picker should be on screen. `TVModeView`
    /// observes this and renders the picker overlay; the user picks (or
    /// cancels) and the manager clears the request. Lives here rather than
    /// inside the view so entry paths that don't mount `TVModeView` first
    /// (e.g. cold-start resume) can still flow through the same code.
    @Published var screenPickerRequest: ScreenPickerRequest?

    /// The value of `autoFullscreenEnabled` that was in effect before the user
    /// entered TV Mode. TV Mode forces auto-fullscreen on for any game it
    /// launches (which always open behind the fullscreen TV-mode window
    /// otherwise); when the user leaves TV Mode we restore this prior value
    /// so the main-window launch behavior is unchanged.
    private var priorAutoFullscreen: Bool?

    private init() {
        // Resume the last TV-mode session. The `currentlyActive` key is written
        // on every `isActive` change, so it reflects what the user was doing at
        // quit. Fall back to the `launchInTVMode` user preference only when no
        // prior session exists (i.e. truly first launch).
        if AppSettingsCache.shared.getData("tvMode_currentlyActive") != nil {
            self.isActive = AppSettings.getBool("tvMode_currentlyActive", defaultValue: false)
        } else {
            self.isActive = TVModeSettings.launchInTVMode
        }
        if isActive {
            // Started in TV-mode (persisted launch flag) — mirror enter()'s
            // autoFs save/restore so the main-window behavior is restored
            // when the user leaves TV-mode later.
            priorAutoFullscreen = AppSettings.getBool("autoFullscreenEnabled", defaultValue: false)
            AppSettings.setBool("autoFullscreenEnabled", value: true)
            // Cold-start bypasses the picker — there's no view to mount it
            // on yet. Resolve directly via the user's mode (remembered >
            // main) and stash origin so a later exit can still restore.
            requestScreenSelection(allowPicker: false)
        }
    }

    /// Guard: when the app cold-starts in TV-mode, the user almost certainly
    /// quit the app while it was fullscreen (that's the whole point of the
    /// 10-foot launcher). `requestScreenSelection()` resolves the target
    /// display synchronously and fullscreens the window on it.
    ///
    /// Cold-start intentionally bypasses the picker — no SwiftUI view is
    /// mounted yet to render it. The user can change screens by exiting and
    /// re-entering TV Mode from the menu once the UI is up.
    private func requestScreenSelection(allowPicker: Bool) {
        let catalog = ScreenCatalog.shared
        catalog.refresh()
        let screens = catalog.screens

        // 1. Capture the screen the main window is on right now so the exit
        //    path can put the user back where they came from.
        if let current = currentWindowScreenID() {
            TVModeSettings.setOriginScreenID(current)
        }

        // 2. Resolve a target based on the user's mode. `.ask` shows the
        //    picker when more than one screen is connected AND we have a
        //    view to mount it on; otherwise fall through to remembered or
        //    main, matching the v1 "no fuss" behavior.
        let mode = TVModeSettings.screenSelectionMode
        let resolved: ScreenDescriptor? = {
            switch mode {
            case .alwaysMain:
                return catalog.main ?? screens.first
            case .ask:
                guard allowPicker, screens.count > 1 else {
                    return screenCatalogResolveRememberedOrMain(catalog)
                }
                return nil
            case .lastUsed:
                return screenCatalogResolveRememberedOrMain(catalog)
            }
        }()

        if let resolved {
            commitScreenSelection(resolved)
        } else {
            screenPickerRequest = ScreenPickerRequest(
                screens: screens,
                initialFocusIndex: initialPickerFocusIndex(catalog: catalog)
            )
        }
    }

    /// Look up the screen the main window is currently on. Uses the window's
    /// own `screen` when available (which AppKit updates automatically when
    /// the window moves); falls back to `NSScreen.main`.
    private func currentWindowScreenID() -> String? {
        let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) })
            ?? NSApp.windows.first
        return Self.idString(for: window?.screen)
    }

    private static func idString(for screen: NSScreen?) -> String? {
        guard let screen,
              let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return "\(n.uint32Value)"
    }

    private func screenCatalogResolveRememberedOrMain(_ catalog: ScreenCatalog) -> ScreenDescriptor? {
        if let stored = TVModeSettings.rememberedScreenID,
           let match = catalog.screens.first(where: { $0.id == stored }) {
            return match
        }
        return catalog.main ?? catalog.screens.first
    }

    /// Initial focus index in the picker: the remembered screen (returning
    /// user) or main display (first run with no memory).
    private func initialPickerFocusIndex(catalog: ScreenCatalog) -> Int {
        if let stored = TVModeSettings.rememberedScreenID,
           let idx = catalog.screens.firstIndex(where: { $0.id == stored }) {
            return idx
        }
        if let mainID = catalog.mainScreenID,
           let idx = catalog.screens.firstIndex(where: { $0.id == mainID }) {
            return idx
        }
        return 0
    }

    /// Public hook called by `TVModeView` when the user picks (or cancels)
    /// in the picker. Clears the request and commits the move.
    func resolveScreenPicker(selected: ScreenDescriptor?) {
        screenPickerRequest = nil
        if let selected {
            commitScreenSelection(selected)
        } else {
            // Cancel: fullscreen on the main screen so we don't leave the
            // user staring at a windowed TV-mode view.
            let fallback = ScreenCatalog.shared.main ?? ScreenCatalog.shared.screens.first
            if let fallback {
                commitScreenSelection(fallback)
            } else {
                enterFullscreenOnCurrentScreen()
            }
        }
    }

    /// Moves the host window onto the chosen screen, then enters fullscreen.
    /// Order matters: macOS will not fullscreen on a specific screen — the
    /// target is always the screen the window is currently on. So we have to
    /// `setFrame` first while the window is still windowed, then call
    /// `toggleFullScreen` on the next runloop (issuing both synchronously
    /// races and can land the fullscreen on the wrong display).
    func commitScreenSelection(_ screen: ScreenDescriptor) {
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && $0.styleMask.contains(.titled) && !$0.styleMask.contains(.fullScreen)
        }) else {
            enterFullscreenOnCurrentScreen()
            return
        }
        moveWindowOntoScreen(window, screen: screen, fillingVisibleFrame: true)
        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
        }
        // Persist the pick so `.lastUsed` re-targets the same screen next
        // time without re-prompting. Harmless to write in `.alwaysMain`
        // since the picker is bypassed there.
        TVModeSettings.setRememberedScreenID(screen.id)
    }

    /// Last-resort path: fullscreen on whatever screen the window is already
    /// on (the existing v1 behavior). Used when no resolvable screen exists
    /// or the main window can't be found by the title/style-mask filter.
    func enterFullscreenOnCurrentScreen() {
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && $0.styleMask.contains(.titled) && !$0.styleMask.contains(.fullScreen)
        }), window.contentViewController != nil || window.contentView != nil else { return }
        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
        }
    }

    /// Cross-screen-safe move. The naive `window.setFrame(target.visibleFrame,
    /// display: true)` looks right (frames are in global coords) but is
    /// unreliable across displays: AppKit validates the rect against the
    /// window's *current* screen and, when the rect doesn't fully intersect
    /// that screen, parks the window off-screen or in the gap between
    /// displays. The user sees it in Mission Control but it's invisible on
    /// any connected monitor.
    ///
    /// Fix: shrink the window into a tiny rect fully inside the target
    /// screen first. That intermediate frame is guaranteed to pass AppKit's
    /// host-screen check, which causes the window's `screen` property to
    /// re-bind to the target. Only then do we expand to the final frame.
    /// Doing the resize before the re-bind is what gets the move rejected.
    private func moveWindowOntoScreen(_ window: NSWindow, screen: ScreenDescriptor, fillingVisibleFrame: Bool) {
        let target = screen.visibleFrame
        guard target.width > 0, target.height > 0 else { return }

        // Tiny rect centered inside the target screen. 100×100 is small
        // enough to fit on any display we ship on and big enough that
        // AppKit doesn't treat it as a degenerate window.
        let tiny = NSRect(
            x: target.midX - 50,
            y: target.midY - 50,
            width: 100,
            height: 100
        )
        window.setFrame(tiny, display: true)

        // Now that the window's host screen is the target, expand to fill
        // the visible frame (or to whatever final rect the caller wants).
        if fillingVisibleFrame {
            window.setFrame(target, display: true)
        }
    }

    /// Installs a transient `NSWindowDelegate` on the fullscreen window that
    /// moves it onto the user's origin screen during the fullscreen-exit
    /// transition. `windowWillExitFullScreen` is the documented hook for
    /// setting the post-fullscreen frame: AppKit reads `window.frame` at
    /// that moment and uses it as the windowed result's starting position.
    /// Setting the frame here (rather than before the toggle) avoids the
    /// race where SwiftUI reasserts the window's screen between our
    /// `setFrame` and the actual transition.
    ///
    /// No-op when:
    ///   - no origin was captured (defensive),
    ///   - the origin display is no longer attached,
    ///   - the origin is the same screen the fullscreen window is on,
    ///   - no fullscreen window is currently up.
    func prepareOriginScreenRestore() {
        guard let originID = TVModeSettings.originScreenID else { return }
        // Clear immediately so a failed restore doesn't loop on the next
        // exit (and so a successful restore doesn't get re-applied).
        TVModeSettings.setOriginScreenID(nil)
        guard let origin = ScreenCatalog.shared.screens.first(where: { $0.id == originID }) else {
            return
        }
        guard let window = NSApp.windows.first(where: {
            $0.styleMask.contains(.fullScreen)
        }) else { return }
        let fullscreenScreenID = Self.idString(for: window.screen)
        // No-op when the user is exiting TV Mode on the same screen they
        // started from — common with single-display setups.
        guard fullscreenScreenID != originID else { return }

        // Stash the target frame on a delegate that fires during the
        // exit transition. The delegate removes itself in
        // `windowDidExitFullScreen` so it doesn't outlive this exit.
        weak var weakDelegate: OriginRestoreDelegate?
        let delegate = OriginRestoreDelegate(
            window: window,
            targetFrame: origin.visibleFrame,
            screenID: originID,
            onComplete: { [weak window] in
                guard let window, let delegate = weakDelegate else { return }
                if window.delegate === delegate {
                    window.delegate = nil
                }
            }
        )
        weakDelegate = delegate
        window.delegate = delegate
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
        // Picker is mounted by `TVModeView`; that's the only entry path
        // that actually has a SwiftUI surface to render it on.
        requestScreenSelection(allowPicker: true)
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

/// Marker type for the screen-picker state held by `TVModeSettingsManager`.
/// Captured as a value so SwiftUI diffs the published change correctly when
/// the request appears / clears.
struct ScreenPickerRequest: Equatable {
    let screens: [ScreenDescriptor]
    let initialFocusIndex: Int
}

/// Transient `NSWindowDelegate` that moves a fullscreen window onto a
/// specific screen during the fullscreen-exit transition, then removes
/// itself. `windowWillExitFullScreen` is AppKit's documented hook for
/// setting the post-fullscreen position — calling `setFrame` there is
/// honored atomically as part of the transition, sidestepping the
/// cross-screen move race that plain `setFrame` hits on a windowed
/// window. Self-removes in `windowDidExitFullScreen` so it never
/// affects future transitions.
private final class OriginRestoreDelegate: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?
    private let targetFrame: NSRect
    private let targetScreenID: String
    private let onComplete: () -> Void

    init(window: NSWindow, targetFrame: NSRect, screenID: String, onComplete: @escaping () -> Void) {
        self.window = window
        self.targetFrame = targetFrame
        self.targetScreenID = screenID
        self.onComplete = onComplete
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        // AppKit reads `window.frame` here and uses it as the post-exit
        // starting position. `setFrameOrigin` is more lenient than
        // `setFrame` for cross-screen moves: AppKit will accept an origin
        // outside the window's current screen and rebind `window.screen`
        // accordingly, while `setFrame` with a full rect gets clamped to
        // the current screen. We only move the origin here — the size
        // adjustment happens after the transition lands.
        guard let window else { return }
        window.setFrameOrigin(NSPoint(x: targetFrame.minX, y: targetFrame.minY))
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // Now that the transition has landed and the window is windowed,
        // finish the move by resizing to the target frame. At this point
        // `window.screen` has been rebound to the target by our origin
        // move, so the resize sticks.
        defer { onComplete() }
        guard let window else { return }
        window.setContentSize(targetFrame.size)
        // Belt-and-braces full setFrame in case the window's frame
        // autosave or SwiftUI positioning reasserted between origin move
        // and now. If AppKit still ignores us, the user at least lands in
        // a valid state (window on the target screen at the right size).
        if !isWindowOnTargetScreen(window) {
            window.setFrame(targetFrame, display: true)
        }
    }

    private func isWindowOnTargetScreen(_ window: NSWindow) -> Bool {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let n = window.screen?.deviceDescription[key] as? NSNumber else {
            return false
        }
        return "\(n.uint32Value)" == targetScreenID
    }
}
