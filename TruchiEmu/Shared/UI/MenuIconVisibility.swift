import SwiftUI

extension View {
    /// macOS 27 hides menu item symbol images by default in apps built with the
    /// macOS 27 SDK (release note 170480710). `.titleAndIcon` opts a menu's
    /// labels back in; the environment propagates it into nested menu content.
    /// On macOS 26 and earlier, menu icons are visible by default and
    /// `.titleAndIcon` matches the regular UI label default, so this is a no-op.
    @ViewBuilder
    func menuIconsAlwaysVisible() -> some View {
        if #available(macOS 27.0, *) {
            labelStyle(.titleAndIcon)
        } else {
            self
        }
    }
}
