import SwiftUI
import AppKit

@MainActor final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AccentColorTheme
    @Published var customAccentColor: Color
    @Published var toolbarAccentEnabled: Bool

    var accent: Color {
        if currentTheme == .custom {
            return customAccentColor
        }
        return currentTheme.accent
    }

    var accentDimmed: Color {
        if currentTheme == .custom {
            return AccentColorTheme.dimmedColor(from: customAccentColor)
        }
        return currentTheme.accentDimmed
    }

    var accentDark: Color {
        if currentTheme == .custom {
            return AccentColorTheme.darkColor(from: customAccentColor)
        }
        return currentTheme.accentDark
    }

    init() {
        self.currentTheme = AppSettings.get("accentTheme", type: AccentColorTheme.self) ?? .cyan
        self.toolbarAccentEnabled = AppSettings.getBool("toolbarAccent", defaultValue: true)

        if let data = AppSettings.getData("customAccentColor"),
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            self.customAccentColor = Color(nsColor)
        } else {
            self.customAccentColor = Color(.sRGB, red: 0.031, green: 0.569, blue: 0.698)
        }

        AppColors.brandAccent = accent
        AppColors.brandAccentDimmed = accentDimmed
        AppColors.brandAccentDark = accentDark
    }

    func applyTheme(_ theme: AccentColorTheme, customColor: Color? = nil) {
        AppSettings.set("accentTheme", value: theme)
        currentTheme = theme

        if let customColor {
            if let nsColor = NSColor(customColor).usingColorSpace(.sRGB),
               let data = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
                AppSettings.setData("customAccentColor", value: data)
            }
            customAccentColor = customColor
        }

        AppColors.brandAccent = accent
        AppColors.brandAccentDimmed = accentDimmed
        AppColors.brandAccentDark = accentDark
    }

    func setToolbarAccent(_ enabled: Bool) {
        AppSettings.setBool("toolbarAccent", value: enabled)
        toolbarAccentEnabled = enabled
    }

    static func relaunchApp() {
        let executablePath = Bundle.main.executablePath!
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = []
        try? process.run()
        NSApp.terminate(nil)
    }
}
