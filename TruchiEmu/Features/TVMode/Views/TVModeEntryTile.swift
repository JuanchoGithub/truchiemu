import SwiftUI
import AppKit

/// Tile shown in row 1 for a smart collection or system. Icon-only with no
/// container card. The focused icon scales up strongly and shows its name
/// and ROM count below; side icons show art alone.
struct TVModeEntryTile: View {
    let entry: TVModeEntry
    let count: Int
    let isFocused: Bool
    let theme: TVModeSettings.Theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tvModeScale) private var scale
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var systemImage: NSImage?
    @State private var controllerImage: NSImage?

    private var size: CGFloat { 168 * scale }

    /// Fixed label area so the row does not jump when focus moves between
    /// icons. Only the centered icon fills it; side slots keep it empty.
    private var labelHeight: CGFloat { 72 * scale }

    var body: some View {
        VStack(spacing: 10 * scale) {
            iconView
                .frame(width: size, height: size)
                .shadow(color: shadowColor, radius: isFocused ? 24 * scale : 8 * scale, y: isFocused ? 12 * scale : 4 * scale)
                .scaleEffect(isFocused ? 1.45 : 0.9)
                .animation(.easeOut(duration: 0.22), value: isFocused)

            VStack(spacing: 4 * scale) {
                if isFocused {
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
            }
            .frame(width: size + 60 * scale, height: labelHeight)
            .opacity(isFocused ? 1 : 0)
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
            return AppColors.accentForScheme(colorScheme).opacity(isFocused ? 0.55 : 0.0)
        } else {
            return .black.opacity(isFocused ? 0.4 : 0.15)
        }
    }

    private func loadSystemImage() {
        guard let system = entry.system else { systemImage = nil; controllerImage = nil; return }
        systemImage = system.emuImage(size: Int(132 * scale))
        // Fall back to a slightly larger render if no 132-sized asset is cached.
        if systemImage == nil {
            systemImage = system.emuImage(size: Int(600 * scale))
            if systemImage == nil { systemImage = system.emuImage(size: Int(120 * scale)) }
        }
        controllerImage = Bundle.main.url(
            forResource: system.id,
            withExtension: "ico"
        ).flatMap { NSImage(contentsOf: $0) }
    }
}
