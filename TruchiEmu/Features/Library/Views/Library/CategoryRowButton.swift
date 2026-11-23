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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var categoryColor: Color {
        Color(hex: category.colorHex) ?? AppColors.brandAccent
    }

    private var iconBadgeView: some View {
        GameCategoryIconView(category: category, size: 16)
            .foregroundColor(categoryColor)
            .frame(width: 16, height: 16)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        categoryColor.opacity(0.30),
                                        categoryColor.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(AppColors.cardBackgroundSubtle(colorScheme))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? categoryColor.opacity(0.30) : AppColors.cardBorder(colorScheme),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovered && !reduceMotion ? 1.06 : 1)
            .animation(reduceMotion ? nil : AppMotion.micro, value: isHovered)
    }

  var body: some View {
    Button {
      selectedFilter = .category(category.id)
    } label: {
      HStack(spacing: 8) {
        iconBadgeView

        Text(category.name)
        .lineLimit(1)
        .foregroundColor(isSelected ? .primary : AppColors.textPrimary(colorScheme))
        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular, design: .rounded))

        Spacer()

        if category.isSmart {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(categoryColor)
                .help(loc.localized("category.smartRules"))
        }

        Text("\(count)")
        .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundColor(isSelected ? .white : AppColors.textSecondary(colorScheme))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? categoryColor.opacity(0.85) : AppColors.cardBackgroundSubtle(colorScheme))
        )

        // Gutter for the context-menu button drawn by the trailing overlay.
        if isHovered || isSelected {
          Color.clear
            .frame(width: 20, height: 1)
        }
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .contentShape(Rectangle())
    }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isDropTarget
                        ? AnyShapeStyle(categoryColor.opacity(0.20))
                        : isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    categoryColor.opacity(colorScheme == .dark ? 0.24 : 0.16),
                                    categoryColor.opacity(colorScheme == .dark ? 0.08 : 0.06)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        : AnyShapeStyle(isHovered ? AppColors.cardBackgroundSubtle(colorScheme) : .clear)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? categoryColor.opacity(0.30)
                        : (isHovered ? AppColors.cardBorder(colorScheme) : .clear),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .overlay {
            if isGamepadFocused {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColors.brandAccent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [categoryColor, categoryColor.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: 18)
                    .padding(.leading, 2)
                    .shadow(color: categoryColor.opacity(0.6), radius: 3)
            }
        }
        .overlay(alignment: .trailing) {
            if isHovered || isSelected {
                Menu {
                    Group {
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
                    .menuIconsAlwaysVisible()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .tint(AppColors.textSecondary(colorScheme))
                .fixedSize()
                .padding(.trailing, 4)
                .transition(.opacity)
            }
        }
    .onHover { hovering in
      // Same scroll-gating as SidebarRowButton: rows sweeping under a
      // stationary cursor must not light up per-row mid-scroll.
      guard !ScrollActivity.isScrolling else { return }
      isHovered = hovering
    }
    .onReceive(NotificationCenter.default.publisher(for: .libraryScrollActivityChanged)) { _ in
      if ScrollActivity.isScrolling, isHovered {
        isHovered = false
      }
    }
    .animation(AppMotion.micro, value: isHovered)
    .animation(AppMotion.micro, value: isSelected)
    .onDrop(of: [.plainText], isTargeted: $isDropTarget) { items in
      handleDropOnCategory(items, category.id)
    }
        .contextMenu {
            Group {
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
            .menuIconsAlwaysVisible()
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