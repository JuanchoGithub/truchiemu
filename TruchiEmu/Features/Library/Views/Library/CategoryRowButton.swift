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
    @State private var showDeleteAlert = false
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
        .padding(.trailing, (isHovered || isSelected) ? 22 : 0)
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
        .overlay(alignment: .trailing) {
            if isHovered || isSelected {
                Menu {
                    Button {
                        showEditCategorySheet(category)
                    } label: {
                        Label(loc.localized("contextMenu.editCategory"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label(loc.localized("contextMenu.deleteCategory"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                }
                .menuIndicator(.hidden)
                .padding(.trailing, 4)
                .transition(.opacity)
            }
        }
    .onHover { isHovered = $0 }
    .animation(AppMotion.micro, value: isHovered)
    .animation(AppMotion.micro, value: isSelected)
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
				showDeleteAlert = true
			} label: {
                Label(loc.localized("contextMenu.deleteCategory"), systemImage: "trash")
            }
        }
        .alert(
            loc.localized("contextMenu.deleteCategory"),
            isPresented: $showDeleteAlert,
            presenting: category
        ) { cat in
            Button(loc.localized("app.cancel"), role: .cancel) {}
            Button(loc.localized("app.delete"), role: .destructive) {
                onDeleteCategory(cat.id)
            }
        } message: { cat in
            Text(String(format: loc.localized("category.deleteConfirm"), cat.name))
        }
    }
}