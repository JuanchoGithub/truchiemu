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

/// Menu-safe category icon. macOS menus bridge only direct `Image` children
/// into NSMenuItem.image; the wrapper views above are not bridged reliably.
/// Emits the SF Symbol directly, or the template gaming-icon image for
/// "gi:" names ("tag" fallback while the library unpacks).
struct GameCategoryMenuIcon: View {
    let category: GameCategory
    var size: CGFloat = 16

    var body: some View {
        if GamingIconService.isGamingIconName(category.iconName) {
            if let image = GamingIconService.shared.image(for: category.iconName) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "tag")
                    .font(.system(size: size))
            }
        } else {
            Image(systemName: category.iconName)
                .font(.system(size: size))
        }
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
