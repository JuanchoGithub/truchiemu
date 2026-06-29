import SwiftUI

// Category row button for the sidebar — full-row clickable with drag-and-drop support.
struct CategoryRowButton: View {
    let category: GameCategory
    let count: Int
    let isSelected: Bool
    @Binding var selectedFilter: LibraryFilter
	let handleDropOnCategory: ([NSItemProvider], String) -> Bool
	let showEditCategorySheet: (GameCategory) -> Void
	let onDeleteCategory: (String) -> Void
    var isGamepadFocused: Bool = false

    @State private var isHovered = false
    @State private var isDropTarget = false
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button {
      selectedFilter = .category(category.id)
    } label: {
      HStack(spacing: 6) {
        GameCategoryIconView(category: category, size: 22)
        .foregroundColor(Color(hex: category.colorHex) ?? .blue)

        Text(category.name)
        .lineLimit(1)
        .foregroundColor(isSelected ? .primary : .secondary)
        .fontWeight(isSelected ? .medium : .regular)

        Spacer()

        Text("\(count)")
        .font(.caption2.monospacedDigit())
        .foregroundColor(isSelected ? (Color(hex: category.colorHex) ?? .blue) : .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isSelected ? (Color(hex: category.colorHex) ?? .blue).opacity(0.15) : AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(6)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .contentShape(Rectangle())
    }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDropTarget ? (Color(hex: category.colorHex) ?? .blue).opacity(0.2) :
(isSelected ? (Color(hex: category.colorHex) ?? .blue).opacity(0.15) :
                        (isHovered ? AppColors.cardBackgroundSubtle(colorScheme) : .clear)))
        )
        .overlay {
            if isGamepadFocused {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.brandAccent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: category.colorHex) ?? .blue)
                    .frame(width: 3, height: 20)
                    .padding(.leading, 2)
            }
        }
    .onHover { isHovered = $0 }
    .onDrop(of: [.plainText], isTargeted: $isDropTarget) { items in
      handleDropOnCategory(items, category.id)
    }
        .contextMenu {
            Button {
                showEditCategorySheet(category)
            } label: {
                Label(loc.localized("contextMenu.editCategory"), systemImage: "pencil")
            }
		Button(role: .destructive) {
				onDeleteCategory(category.id)
			} label: {
                Label(loc.localized("contextMenu.deleteCategory"), systemImage: "trash")
            }
        }
    }
}