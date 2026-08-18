import SwiftUI

struct PendingThemeSettings {
    var theme: AccentColorTheme = .samus
    var appearanceMode: AppearanceMode = .automatic
    var customColor: Color = Color(.sRGB, red: 0.031, green: 0.569, blue: 0.698)
    var toolbarAccent: Bool = true
    var tintedSurfaces: Bool = true
}