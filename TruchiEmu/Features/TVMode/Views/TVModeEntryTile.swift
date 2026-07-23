import SwiftUI
import AppKit

/// Tile shown in row 1 for a smart collection or system. Flat card with icon,
/// title and ROM count. The focused tile scales up and gains a tinted ring.
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

    private var size: CGFloat { 144 * scale }

    var body: some View {
        VStack(spacing: 10 * scale) {
            iconView
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 32 * scale, style: .continuous)
                        .fill(containerFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32 * scale, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isFocused ? 4 * scale : 1.5 * scale)
                )
                .shadow(color: shadowColor, radius: isFocused ? 22 * scale : 6 * scale, y: isFocused ? 12 * scale : 3 * scale)
                .scaleEffect(isFocused ? 1.0 : 0.92)
                .animation(.easeOut(duration: 0.22), value: isFocused)

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
            .frame(width: size + 60 * scale)
        }
        .onAppear { loadSystemImage() }
        .onChange(of: entry.id) { _, _ in loadSystemImage() }
    }

    @ViewBuilder
    private var iconView: some View {
        if let system = entry.system, usesControllerIcons, let img = controllerImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(30 * scale)
        } else if let system = entry.system, let img = systemImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(18 * scale)
        } else if let symbol = entry.sfSymbol {
            Image(systemName: symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(30 * scale)
                .foregroundStyle(iconColor)
        } else {
            Image(systemName: "gamecontroller")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(30 * scale)
                .foregroundStyle(iconColor)
        }
    }

    private var usesControllerIcons: Bool {
        (AppSettings.getString("tvMode_systemIconStyle", defaultValue: "default") ?? "default") == "controller"
    }

    private var containerFill: Color {
        if theme == .bold {
            return isFocused
                ? AppColors.accentForScheme(colorScheme).opacity(0.22)
                : AppColors.cardBackground(colorScheme).opacity(0.6)
        } else {
            // Muted: desaturated surfaces.
            return Color.gray.opacity(isFocused ? 0.20 : 0.12)
        }
    }

    private var borderColor: Color {
        if theme == .bold {
            return isFocused ? AppColors.accentForScheme(colorScheme) : AppColors.divider(colorScheme)
        } else {
            return isFocused ? Color.white.opacity(0.45) : Color.white.opacity(0.1)
        }
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
