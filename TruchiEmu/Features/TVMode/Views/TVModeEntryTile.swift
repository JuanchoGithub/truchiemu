import SwiftUI
import AppKit

/// Icon shown for a smart collection, category or system in the vertical
/// systems rail. Icon-only: the rail draws the fixed focus frame, and the
/// page header carries the focused entry's name and game count.
struct TVModeEntryTile: View {
    let entry: TVModeEntry
    let count: Int
    /// Continuous focus from `1` (sitting in the rail's focus frame) to `0`
    /// (far away). Driven by the rail's animated centre so icons brighten as
    /// they slide into the frame.
    let focus: CGFloat
    let theme: TVModeSettings.Theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tvModeScale) private var scale
    @ObservedObject private var gamingIcons = GamingIconService.shared
    @State private var systemImage: NSImage?
    @State private var controllerImage: NSImage?
    @State private var customCategoryIcon: NSImage?

    private var size: CGFloat { 52 * scale }

    /// Controller-style icons never change at runtime: one synchronous disk
    /// read per system total. Without this, every tile mount re-read its
    /// `.ico` file on the main thread, which hitched fast flights.
    private static var controllerIconCache: [String: NSImage] = [:]

    /// Decodes all row-1 icons once so fast flights never touch disk or
    /// decode images on the main thread mid-animation. Idempotent: cache hits
    /// after the first call, so re-running on entry or scale changes is free.
    static func warmIcons(for entries: [TVModeEntry], scale: CGFloat) {
        let size = Int(132 * scale)
        for entry in entries {
            guard let system = entry.system else { continue }
            _ = system.emuImage(size: size)
            _ = cachedControllerIcon(for: system.id)
        }
    }

    private static func cachedControllerIcon(for systemID: String) -> NSImage? {
        if let cached = controllerIconCache[systemID] { return cached }
        let img = Bundle.main.url(
            forResource: systemID,
            withExtension: "ico"
        ).flatMap { NSImage(contentsOf: $0) }
        if let img { controllerIconCache[systemID] = img }
        return img
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            iconView
                .frame(width: size, height: size)
                .foregroundStyle(iconColor)
                .shadow(color: shadowColor, radius: (4 + 10 * focus) * scale, y: (2 + 4 * focus) * scale)

            if count > 0 {
                Text(verbatim: "\(count)")
                    .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(theme == .bold ? AppColors.accentForScheme(colorScheme) : .white)
                    .padding(.horizontal, 5 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(
                        Capsule().fill(
                            theme == .bold
                                ? AppColors.accentForScheme(colorScheme).opacity(0.18)
                                : Color.white.opacity(0.14)
                        )
                    )
                    .opacity(max(0, focus * 2 - 1))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(0.80 + 0.20 * focus)
        .opacity(0.50 + 0.50 * focus)
        .accessibilityLabel(accessibilityLabel)
        .onAppear { loadSystemImage() }
        .onChange(of: entry.id) { _, _ in loadSystemImage() }
        .onChange(of: entry.category?.customIconPath) { _, _ in loadSystemImage() }
    }

    private var accessibilityLabel: String {
        count > 0 ? "\(entry.displayName), \(count)" : entry.displayName
    }

    @ViewBuilder
    private var iconView: some View {
        if entry.system != nil, usesControllerIcons, let img = controllerImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(4 * scale)
        } else if entry.system != nil, let img = systemImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(2 * scale)
        } else if let category = entry.category {
            // Mirror the main sidebar's `GameCategoryIconView`: custom uploaded
            // icon, game-icons.net template image, or SF Symbol — tinted with
            // the category's own color.
            categoryIcon(category)
                .padding(8 * scale)
                .foregroundStyle(categoryColor(category))
        } else if let symbol = entry.sfSymbol {
            Image(systemName: symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(8 * scale)
                .foregroundStyle(iconColor)
        } else {
            Image(systemName: "gamecontroller")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(8 * scale)
                .foregroundStyle(iconColor)
        }
    }

    @ViewBuilder
    private func categoryIcon(_ category: GameCategory) -> some View {
        if let img = customCategoryIcon {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else if GamingIconService.isGamingIconName(category.iconName),
                  let img = gamingIcons.image(for: category.iconName) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: category.iconName.isEmpty ? "tag" : category.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    private func categoryColor(_ category: GameCategory) -> Color {
        Color(hex: category.colorHex) ?? .blue
    }

    private var usesControllerIcons: Bool {
        (AppSettings.getString("tvMode_systemIconStyle", defaultValue: "default") ?? "default") == "controller"
    }

    private var iconColor: Color {
        if theme == .bold {
            return AppColors.accentForScheme(colorScheme)
        } else {
            return .white.opacity(0.9)
        }
    }

    private var shadowColor: Color {
        if let category = entry.category {
            return categoryColor(category).opacity(0.55 * focus)
        }
        if theme == .bold {
            return AppColors.accentForScheme(colorScheme).opacity(0.45 * focus)
        } else {
            return .black.opacity(0.10 + 0.25 * focus)
        }
    }

    private func loadSystemImage() {
        TVPerfTrace.time("loadIcon", thresholdMs: 3) {
            if let path = entry.category?.customIconPath {
                customCategoryIcon = NSImage(contentsOf: URL(fileURLWithPath: path))
            } else {
                customCategoryIcon = nil
            }
            guard let system = entry.system else { systemImage = nil; controllerImage = nil; return }
            systemImage = system.emuImage(size: Int(132 * scale))
            // Fall back to a slightly larger render if no 132-sized asset is cached.
            if systemImage == nil {
                systemImage = system.emuImage(size: Int(600 * scale))
                if systemImage == nil { systemImage = system.emuImage(size: Int(120 * scale)) }
            }
            controllerImage = Self.cachedControllerIcon(for: system.id)
        }
    }
}
