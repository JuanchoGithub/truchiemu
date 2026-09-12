import SwiftUI
import AppKit

/// Tile shown in row 1 for a smart collection or system. Icon-only with no
/// container card. The focused icon scales up strongly and shows its name
/// and ROM count below; side icons show art alone.
struct TVModeEntryTile: View {
    let entry: TVModeEntry
    let count: Int
    /// Center focus from `1` (exact center) to `0` (one slot away or row not
    /// active). Applied with NO animation modifier: motion comes from the row
    /// sweep itself, so each icon grows big passing through center and back
    /// to normal size leaving it.
    let focus: CGFloat
    let theme: TVModeSettings.Theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tvModeScale) private var scale
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var systemImage: NSImage?
    @State private var controllerImage: NSImage?

    private var size: CGFloat { 168 * scale }

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

    /// Fixed label area so the row does not jump when focus moves between
    /// icons. Only the centered icon fills it; side slots keep it empty.
    private var labelHeight: CGFloat { 72 * scale }

    var body: some View {
        VStack(spacing: 10 * scale) {
            iconView
                .frame(width: size, height: size)
                .shadow(color: shadowColor, radius: (8 + 16 * focus) * scale, y: (4 + 8 * focus) * scale)
                .scaleEffect(0.9 + 0.55 * focus)

            // Name and count stay mounted and crossfade with focus. Inserting
            // and removing them per step popped text in and out at flight
            // cadence, which read as choppiness.
            VStack(spacing: 4 * scale) {
                Text(entry.displayName)
                    .font(.system(size: 28 * scale, weight: .bold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 22 * scale, weight: .semibold))
                        .foregroundStyle(textColor.opacity(0.7))
                }
            }
            .frame(width: size + 60 * scale, height: labelHeight)
            .opacity(focus)
        }
        .accessibilityLabel(accessibilityLabel)
        .onAppear { loadSystemImage() }
        .onChange(of: entry.id) { _, _ in loadSystemImage() }
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
                .padding(12 * scale)
        } else if entry.system != nil, let img = systemImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(8 * scale)
        } else if let symbol = entry.sfSymbol {
            Image(systemName: symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(20 * scale)
                .foregroundStyle(iconColor)
        } else {
            Image(systemName: "gamecontroller")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(20 * scale)
                .foregroundStyle(iconColor)
        }
    }

    private var usesControllerIcons: Bool {
        (AppSettings.getString("tvMode_systemIconStyle", defaultValue: "default") ?? "default") == "controller"
    }

    private var iconColor: Color {
        if theme == .bold {
            return AppColors.accentForScheme(colorScheme)
        } else {
            return .primary.opacity(0.85)
        }
    }

    private var textColor: Color {
        if theme == .bold {
            return AppColors.textPrimary(colorScheme)
        } else {
            return .primary
        }
    }

    private var shadowColor: Color {
        if theme == .bold {
            return AppColors.accentForScheme(colorScheme).opacity(0.55 * focus)
        } else {
            return .black.opacity(0.15 + 0.25 * focus)
        }
    }

    private func loadSystemImage() {
        TVPerfTrace.time("loadIcon", thresholdMs: 3) {
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
