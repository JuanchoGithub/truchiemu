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
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var systemImage: NSImage?

    private let size: CGFloat = 144

    var body: some View {
        VStack(spacing: 10) {
            iconView
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(containerFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isFocused ? 4 : 1.5)
                )
                .shadow(color: shadowColor, radius: isFocused ? 22 : 6, y: isFocused ? 12 : 3)
                .scaleEffect(isFocused ? 1.0 : 0.92)
                .animation(.easeOut(duration: 0.22), value: isFocused)

            VStack(spacing: 4) {
                Text(entry.displayName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(textColor.opacity(0.7))
                }
            }
            .frame(width: size + 60)
        }
        .onAppear { loadSystemImage() }
        .onChange(of: entry.id) { _, _ in loadSystemImage() }
    }

    @ViewBuilder
    private var iconView: some View {
        if let system = entry.system, let img = systemImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(18)
        } else if let symbol = entry.sfSymbol {
            Image(systemName: symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(30)
                .foregroundStyle(iconColor)
        } else {
            Image(systemName: "gamecontroller")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(30)
                .foregroundStyle(iconColor)
        }
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
        guard let system = entry.system else { systemImage = nil; return }
        systemImage = system.emuImage(size: 132)
        // Fall back to a slightly larger render if no 132-sized asset is cached.
        if systemImage == nil {
            systemImage = system.emuImage(size: 600)
            if systemImage == nil { systemImage = system.emuImage(size: 120) }
        }
    }
}
