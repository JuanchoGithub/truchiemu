import SwiftUI

// MARK: - Icon Name View

/// Renders a stored icon name: "gi:author/name" -> template image from the
/// bundled game-icons.net library (tinted by the ambient foreground style);
/// anything else -> SF Symbol. Falls back to "tag" while the library is not
/// yet unpacked or the name is empty.
struct IconNameView: View {
    let iconName: String
    var size: CGFloat = 22

    var body: some View {
        Group {
            if GamingIconService.isGamingIconName(iconName) {
                if let image = GamingIconService.shared.image(for: iconName) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "tag")
                        .font(.system(size: size * 0.55))
                }
            } else {
                Image(systemName: iconName.isEmpty ? "tag" : iconName)
                    .font(.system(size: size * 0.55))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Category Icon View

struct GameCategoryIconView: View {
    let category: GameCategory
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let customPath = category.customIconPath,
               let img = NSImage(contentsOf: URL(fileURLWithPath: customPath)) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                IconNameView(iconName: category.iconName, size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Builds a colorized, non-template NSImage for a category so macOS menus show
/// the category's icon *and* its color. Menu items ignore SwiftUI tinting
/// (`foregroundColor`) and template images, so the color is baked into the
/// bitmap. Emits the SF Symbol, or the game-icons.net image for "gi:" names
/// ("tag" fallback while the library unpacks).
@MainActor
enum GameCategoryMenuImage {
    static func image(for category: GameCategory, size: CGFloat = 16) -> NSImage {
        let color = NSColor(Color(hex: category.colorHex) ?? .blue)
        return tinted(baseImage(for: category), with: color, size: size)
    }

    private static func baseImage(for category: GameCategory) -> NSImage {
        if GamingIconService.isGamingIconName(category.iconName),
           let icon = GamingIconService.shared.image(for: category.iconName) {
            return icon
        }
        let symbolName = category.iconName.isEmpty ? "tag" : category.iconName
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            return symbol
        }
        return NSImage(systemSymbolName: "tag", accessibilityDescription: nil) ?? NSImage()
    }

    private static func tinted(_ image: NSImage, with color: NSColor, size: CGFloat) -> NSImage {
        let result = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // Draw the (template) glyph aspect-fit, then flood the opaque pixels
            // with the category color so the menu renders it in color.
            image.draw(in: aspectFitRect(for: image.size, in: rect))
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        result.isTemplate = false
        return result
    }

    private static func aspectFitRect(for imageSize: NSSize, in rect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return NSRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }
}

// MARK: - Category Badge

struct CategoryBadgeView: View {
	let category: GameCategory
	var isCompact: Bool = false
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
        if isCompact {
            // Compact mode: Icon only in a circle
            GameCategoryIconView(category: category, size: 14)
                .padding(4)
        .background(Color(hex: category.colorHex) ?? .blue)
        .foregroundColor(AppColors.textOnAccent(colorScheme))
        .clipShape(Circle())
        } else {
            // Standard mode: Icon + Text in a capsule/rounded rect
            HStack(spacing: 3) {
                GameCategoryIconView(category: category, size: 12)
                Text(category.name)
                    .font(.system(size: 10, weight: .medium))
            }
        .foregroundColor(AppColors.textOnAccent(colorScheme))
        .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: category.colorHex) ?? .blue)
            .cornerRadius(AppRadius.xs)
        }
    }
}

// MARK: - Add to Category Sheet

struct AddToCategorySheet: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject var categoryManager: CategoryManager
	let gameIDs: [UUID]
	let gameKeys: [String] = []
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
        NavigationStack {
            List {
                ForEach(categoryManager.categories) { category in
                    let alreadyContains = !Set(category.gameIDs).intersection(gameIDs).isEmpty
                        || !Set(category.gameKeys).intersection(gameKeys).isEmpty
                    Button {
                        categoryManager.addGamesToCategory(gameIDs: gameIDs, gameKeys: gameKeys, categoryID: category.id)
                        dismiss()
                    } label: {
                        HStack {
                            GameCategoryIconView(category: category, size: 18)
                                .foregroundColor(Color(hex: category.colorHex) ?? .blue)
                            Text(category.name)
                            Spacer()
                            if alreadyContains {
                Image(systemName: "checkmark")
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Add to Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 300, height: 300)
    }
}
