import SwiftUI
import AppKit

@MainActor final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AccentColorTheme
    @Published var appearanceMode: AppearanceMode
    @Published var customAccentColor: Color
    @Published var toolbarAccentEnabled: Bool
    @Published var tintedSurfacesEnabled: Bool

    var accent: Color {
        if currentTheme == .custom { return customAccentColor }
        return currentTheme.accent
    }

    var accentDimmed: Color {
        if currentTheme == .custom { return AccentColorTheme.dimmedColor(from: customAccentColor) }
        return currentTheme.accentDimmed
    }

    var accentDark: Color {
        if currentTheme == .custom { return AccentColorTheme.darkColor(from: customAccentColor) }
        return currentTheme.accentDark
    }

    var accentSecondary: Color {
        if currentTheme == .custom { return customAccentColor }
        return currentTheme.secondaryAccent
    }

    var accentDarkMode: Color {
        if currentTheme == .custom { return customAccentColor }
        return currentTheme.accentForDarkMode
    }

    var accentDimmedDarkMode: Color {
        if currentTheme == .custom { return AccentColorTheme.dimmedColor(from: customAccentColor) }
        return currentTheme.accentDimmedForDarkMode
    }

    var accentDarkDarkMode: Color {
        if currentTheme == .custom { return AccentColorTheme.darkColor(from: customAccentColor) }
        return currentTheme.accentDarkForDarkMode
    }

    var accentSecondaryDarkMode: Color {
        if currentTheme == .custom { return customAccentColor }
        return currentTheme.secondaryAccentForDarkMode
    }

    var accentLightMode: Color {
        if currentTheme == .custom { return customAccentColor }
        return currentTheme.accentForLightMode
    }

    var accentDimmedLightMode: Color {
        if currentTheme == .custom { return AccentColorTheme.dimmedColor(from: customAccentColor) }
        return currentTheme.accentDimmedForLightMode
    }

    var accentDarkLightMode: Color {
        if currentTheme == .custom { return AccentColorTheme.darkColor(from: customAccentColor) }
        return currentTheme.accentDarkForLightMode
    }

    var accentSecondaryLightMode: Color {
        if currentTheme == .custom { return customAccentColor }
        return currentTheme.secondaryAccentForLightMode
    }

    init() {
        self.currentTheme = AppSettings.get("accentTheme", type: AccentColorTheme.self) ?? .megaMan
        self.toolbarAccentEnabled = AppSettings.getBool("toolbarAccent", defaultValue: true)
        self.tintedSurfacesEnabled = AppSettings.getBool("tintedSurfaces", defaultValue: true)
        self.appearanceMode = AppSettings.get("appearanceMode", type: AppearanceMode.self) ?? .automatic

        if let data = AppSettings.getData("customAccentColor"),
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            self.customAccentColor = Color(nsColor)
        } else {
            self.customAccentColor = Color(.sRGB, red: 0.012, green: 0.412, blue: 0.631, opacity: 1.0)
        }

        AppColors.brandAccentLight = accentLightMode
        AppColors.brandAccentDimmed = accentDimmedLightMode
        AppColors.brandAccentDark = accentDarkLightMode
        AppColors.brandAccentSecondaryLight = accentSecondaryLightMode

        AppColors.brandAccentDarkMode = accentDarkMode
        AppColors.brandAccentDimmedDarkMode = accentDimmedDarkMode
        AppColors.brandAccentDarkDarkMode = accentDarkDarkMode
        AppColors.brandAccentSecondaryDarkMode = accentSecondaryDarkMode

    }
    
    private var appearanceObservation: Any?

    func applySavedAppearance() {
        applyNSAppAppearance(appearanceMode)
        startObservingSystemAppearance()
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

        AppColors.brandAccentLight = accentLightMode
        AppColors.brandAccentDimmed = accentDimmedLightMode
        AppColors.brandAccentDark = accentDarkLightMode
        AppColors.brandAccentSecondaryLight = accentSecondaryLightMode

        AppColors.brandAccentDarkMode = accentDarkMode
        AppColors.brandAccentDimmedDarkMode = accentDimmedDarkMode
        AppColors.brandAccentDarkDarkMode = accentDarkDarkMode
        AppColors.brandAccentSecondaryDarkMode = accentSecondaryDarkMode
    }

    func setToolbarAccent(_ enabled: Bool) {
        AppSettings.setBool("toolbarAccent", value: enabled)
        toolbarAccentEnabled = enabled
    }

    func setTintedSurfaces(_ enabled: Bool) {
        AppSettings.setBool("tintedSurfaces", value: enabled)
        tintedSurfacesEnabled = enabled
    }

    func applyAppearanceMode(_ mode: AppearanceMode, save: Bool = true) {
        if save {
            AppSettings.set("appearanceMode", value: mode)
        }
        appearanceMode = mode
        applyNSAppAppearance(mode)
        startObservingSystemAppearance()
    }

    func applyNSAppAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .automatic:
            NSApp.appearance = resolvedSystemAppearance()
        }
    }

    private static func currentSystemIsDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func resolvedSystemAppearance() -> NSAppearance? {
        Self.currentSystemIsDark()
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)
    }

    private func startObservingSystemAppearance() {
        appearanceObservation = nil
        guard appearanceMode == .automatic else { return }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.appearanceMode == .automatic else { return }
                NSApp.appearance = self.resolvedSystemAppearance()
            }
        }
    }

    static func relaunchApp() {
        AppSettings.flush()
        let executablePath = Bundle.main.executablePath!
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = []
        try? process.run()
        NSApp.terminate(nil)
    }
}
