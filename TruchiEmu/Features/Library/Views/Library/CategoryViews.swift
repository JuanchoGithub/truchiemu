import SwiftUI

// MARK: - Category Badge

struct CategoryBadgeView: View {
	let category: GameCategory
	var isCompact: Bool = false
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
        if isCompact {
            // Compact mode: Icon only in a circle
            Image(systemName: category.iconName.isEmpty ? "tag" : category.iconName)
                .font(.system(size: 10, weight: .medium))
                .padding(4)
        .background(Color(hex: category.colorHex) ?? .blue)
        .foregroundColor(AppColors.textOnAccent(colorScheme))
        .clipShape(Circle())
        } else {
            // Standard mode: Icon + Text in a capsule/rounded rect
            HStack(spacing: 3) {
                Image(systemName: category.iconName)
                    .font(.system(size: 9, weight: .medium))
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
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
        NavigationStack {
            List {
                ForEach(categoryManager.categories) { category in
                    let alreadyContains = !Set(category.gameIDs).intersection(gameIDs).isEmpty
                    Button {
                        categoryManager.addGamesToCategory(gameIDs: gameIDs, categoryID: category.id)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: category.iconName)
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
