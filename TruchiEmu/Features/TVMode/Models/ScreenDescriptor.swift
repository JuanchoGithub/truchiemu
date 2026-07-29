import Foundation
import AppKit
import CoreGraphics

/// Lightweight snapshot of a connected display at the time the picker reads
/// it. Captured as a value type so callers can hold on to it across view
/// rebuilds without worrying about the underlying `NSScreen` going away when
/// the user unplugs a monitor mid-pick.
struct ScreenDescriptor: Identifiable, Equatable, Hashable {
    /// Stable display identifier — the `CGDirectDisplayID` rendered as a
    /// decimal string. Survives sleep/wake and resolution changes; only
    /// changes when the user physically swaps displays, which is exactly when
    /// we want to invalidate the "remembered screen" preference.
    let id: String

    /// Human-readable name (e.g. "LG UltraFine 5K"). Falls back to the
    /// localized model name or "Display N" when macOS doesn't expose one.
    let name: String

    /// Frame in global screen coordinates (origin bottom-left). The picker
    /// uses this to position the preview tile and to ask AppKit to move the
    /// window onto the chosen screen.
    let frame: CGRect

    /// Visible frame excludes Dock and menu bar; useful for "where would the
    /// fullscreen window actually land".
    let visibleFrame: CGRect

    /// Backing scale factor (1.0 for non-Retina, 2.0 for Retina, etc.).
    let backingScaleFactor: CGFloat

    /// Logical pixel resolution derived from `frame.size` × backing scale.
    let pixelSize: CGSize

    /// True if this is the screen the system currently considers primary
    /// (the one with the menu bar / key window on first launch).
    let isMain: Bool

    /// True for displays that report a built-in panel (the Mac's internal
    /// screen on laptops / iMacs). Used to label "Built-in Display" in the
    /// picker when the OS doesn't give us a friendlier name.
    let isBuiltIn: Bool

    /// Width/height ratio for the preview tile. Returns 1.0 when height is 0
    /// to avoid divide-by-zero in degenerate layouts.
    var aspectRatio: CGFloat {
        frame.height > 0 ? frame.width / frame.height : 1.0
    }

    /// Compact label like "27-inch (2560 × 1440)" combining the physical size
    /// (mm, exposed via `NSDeviceSize`) with pixel resolution. Returns just
    /// the resolution when the device doesn't report a physical size (common
    /// for TVs/projectors over HDMI).
    var summary: String {
        let pixels = "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
        if let inches = physicalSizeInches {
            return String(format: "%d\" (%@)", Int(inches.rounded()), pixels)
        }
        return pixels
    }

    /// Diagonal in inches derived from `NSDeviceSize` (mm). `nil` when the
    /// device doesn't report a physical size.
    var physicalSizeInches: Double? {
        guard let mm = deviceSizeMM, mm.width > 0, mm.height > 0 else { return nil }
        let widthInches = Double(mm.width) / 25.4
        let heightInches = Double(mm.height) / 25.4
        return (widthInches * widthInches + heightInches * heightInches).squareRoot()
    }

    /// `NSDeviceSize` in millimeters. AppKit returns these as `NSNumber`
    /// values inside `deviceDescription`; missing keys yield `nil`.
    private var deviceSizeMM: (width: Int, height: Int)? {
        guard let screen = nsScreen.screen,
              let size = screen.deviceDescription[NSDeviceDescriptionKey.size] as? NSValue else { return nil }
        var rect = NSRect.zero
        size.getValue(&rect)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return (Int(rect.width.rounded()), Int(rect.height.rounded()))
    }

    /// Held weakly through the picker so that the descriptor can still hand
    /// callers a live `NSScreen` for window positioning (Apple discourages
    /// caching `NSScreen` long-term because it can become a dangling
    /// reference after display changes).
    let nsScreen: WeakScreen

    /// Equatable / Hashable based on the stable display id only. `nsScreen`
    /// and other UIKit-derived state is intentionally excluded.
    static func == (lhs: ScreenDescriptor, rhs: ScreenDescriptor) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// `NSScreen` is a class type but we don't want callers holding a strong
/// reference after a display is unplugged. Wrap it in a thin holder so
/// `ScreenDescriptor` stays a value type without forcing the runtime screen
/// to outlive its origin.
struct WeakScreen {
    private let storage: WeakStorage<NSScreen>

    init(_ screen: NSScreen) {
        self.storage = WeakStorage(value: screen)
    }

    var screen: NSScreen? { storage.value }
}

/// Tiny `Weak<T>` box so we can put a weak reference inside a value type.
private final class WeakStorage<T: AnyObject> {
    weak var value: T?
    init(value: T) { self.value = value }
}

extension ScreenDescriptor {
    /// Builds a descriptor from an `NSScreen`. Returns `nil` when the screen
    /// doesn't expose a usable display id (extremely rare, but seen on some
    /// virtualized / headless setups).
    static func make(from screen: NSScreen) -> ScreenDescriptor? {
        let numberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let builtInKey = NSDeviceDescriptionKey("NSDeviceIsBuiltIn")
        guard let idNumber = screen.deviceDescription[numberKey] as? NSNumber else {
            return nil
        }
        let id = "\(idNumber.uint32Value)"
        let frame = screen.frame
        let visible = screen.visibleFrame
        let scale = screen.backingScaleFactor
        let pixels = CGSize(width: frame.width * scale, height: frame.height * scale)
        let isMain = (screen == NSScreen.main)
        let isBuiltIn = (screen.deviceDescription[builtInKey] as? Bool) ?? false

        let name: String
        let localized = screen.localizedName
        if !localized.isEmpty {
            name = localized
        } else if isBuiltIn {
            name = "Built-in Display"
        } else {
            name = "Display \(id)"
        }

        return ScreenDescriptor(
            id: id,
            name: name,
            frame: frame,
            visibleFrame: visible,
            backingScaleFactor: scale,
            pixelSize: pixels,
            isMain: isMain,
            isBuiltIn: isBuiltIn,
            nsScreen: WeakScreen(screen)
        )
    }
}
