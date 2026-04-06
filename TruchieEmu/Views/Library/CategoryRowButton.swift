import SwiftUI

/// Category row button for the sidebar — full-row clickable with drag-and-drop support.
struct CategoryRowButton: View {
    let category: GameCategory
    let count: Int
    let isSelected: Bool
    @Binding var selectedFilter: LibraryFilter
    let handleDropOnCategory: ([NSItemProvider], String) -> Bool
    let showEditCategorySheet: (GameCategory) -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button {
            selectedFilter = .category(category.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.iconName)
                    .foregroundColor(Color(hex: category.colorHex) ?? .blue)
                    .font(.system(size: 14))
                    .frame(width: 22, height: 22)
                
                Text(category.name)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .fontWeight(isSelected ? .medium : .regular)
                
                Spacer()
                
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.08) : .clear))
        )
        .onHover { isHovered = $0 }
        .onDrop(of: [.plainText], isTargeted: nil) { items in
            handleDropOnCategory(items, category.id)
        }
        .contextMenu {
            Button {
                showEditCategorySheet(category)
            } label: {
                Label("Edit Category", systemImage: "pencil")
            }
            Button(role: .destructive) {
                // Deletion handled via tag-based List selection
            } label: {
                Label("Delete Category", systemImage: "trash")
            }
        }
    }
}