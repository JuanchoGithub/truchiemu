import SwiftUI

struct SystemSidebarView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var categoryManager: CategoryManager
    @EnvironmentObject var coreManager: CoreManager
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var raService = RetroAchievementsService.shared
    @Binding var selectedFilter: LibraryFilter
    @Binding var showCreateCategorySheet: Bool
    @Binding var editingCategory: GameCategory?
    var onRefresh: ((SystemInfo) -> Void)? = nil
    var onSettings: ((String) -> Void)? = nil
    var onSystemAction: ((SystemInfo, SystemAction, String?) -> Void)? = nil
    var onRenameSystem: ((SystemInfo) -> Void)? = nil
    
    // Combined system entries for the sidebar. Game Boy (gb) absorbs Game Boy Color (gbc)
    // into a single "Game Boy" display entry while keeping internal systemIDs intact.
    private var combinedSystemsWithROMs: [(system: SystemInfo, combinedCount: Int)] {
        let ids = Set(library.roms.compactMap { $0.systemID })
        // Only include display-visible systems (gb visible, gbc hidden)
        let displaySystems = systemDatabase.systemsForDisplay
        
        var result: [(SystemInfo, Int)] = []
        for sys in displaySystems {
            // Check if any ROM exists for this system or its merged partners
            let internalIDs = systemDatabase.allInternalIDs(forDisplayID: sys.id)
            let total = internalIDs.reduce(0) { sum, id in
                sum + (ids.contains(id) ? (library.romCounts[id] ?? 0) : 0)
            }
            if total > 0 {
                result.append((sys, total))
            }
        }
        
        return result.sorted(by: { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(AppGradients.accent)
                        .frame(width: 48, height: 2)
                    Spacer()
                }
                .padding(.bottom, 8)

                sidebarRow(icon: "square.grid.2x2", label: loc.localized("app.allGames"), count: library.romCounts["all"] ?? 0, filter: .all)

                let favCount = library.romCounts["favorites"] ?? 0
                if favCount > 0 {
                    sidebarRow(icon: "heart.fill", label: loc.localized("app.favorites"), count: favCount, tint: .pink, filter: .favorites)
                }

        let recentCount = library.romCounts["recent"] ?? 0
        sidebarRow(icon: "clock.fill", label: loc.localized("app.recent"), count: recentCount, tint: .orange, filter: .recent)

        if raService.isEnabled {
            let raCount = library.roms.filter { $0.raMatchStatus == "matched" }.count
            if raCount > 0 {
                sidebarRow(icon: "trophy.fill", label: loc.localized("library.retroAchievements"), count: raCount, tint: AppColors.brandAccent, filter: .retroAchievements)
            }
        }

        sectionHeader(
                    title: loc.localized("app.categories"),
                    isExpanded: $categoriesSectionExpanded,
                    isHeaderHovered: $categoriesHeaderHovered,
                    onAction: { showCreateCategorySheet = true },
                    actionLabel: loc.localized("app.newCategory"),
                    showAction: categoriesHeaderHovered
                )

                if categoriesSectionExpanded {
                    ForEach(categoryManager.categories) { category in
                        categoryRow(category: category)
                    }
                }

                if !combinedSystemsWithROMs.isEmpty {
                    sectionHeader(
                        title: loc.localized("app.systems"),
                        isExpanded: $systemsSectionExpanded,
                        isHeaderHovered: .constant(false),
                        onAction: nil,
                        actionLabel: nil,
                        showAction: false
                    )

                    if systemsSectionExpanded {
                        ForEach(combinedSystemsWithROMs, id: \.system.id) { entry in
                            sidebarRow(
                                icon: entry.system.iconName,
                                label: entry.system.sidebarDisplayName,
                                system: entry.system,
                                count: entry.combinedCount,
                                filter: .system(entry.system),
                                onRename: onRenameSystem != nil ? { system in onRenameSystem?(system) } : nil
                            )
                        }
                    }
                }

                let hiddenCount = library.romCounts["hidden"] ?? 0
                let showHiddenCategory = AppSettings.getBool("showHiddenGamesCategory", defaultValue: true)
                if hiddenCount > 0 && showHiddenCategory {
                    sectionHeader(
                        title: loc.localized("app.hiddenGames"),
                        isExpanded: .constant(true),
                        isHeaderHovered: .constant(false),
                        onAction: nil,
                        actionLabel: nil,
                        showAction: false
                    )
                    sidebarRow(icon: "eye.slash", label: loc.localized("app.hidden"), count: hiddenCount, tint: .gray, filter: .hidden)
                }

                let mameNonGamesCount = library.romCounts["mameNonGames"] ?? 0
                let showHiddenMAME = SystemPreferences.shared.showHiddenMAMEFiles
                if mameNonGamesCount > 0 && showHiddenMAME {
                    sectionHeader(
                        title: loc.localized("app.mameFiles"),
                        isExpanded: .constant(true),
                        isHeaderHovered: .constant(false),
                        onAction: nil,
                        actionLabel: nil,
                        showAction: false
                    )
                    sidebarRow(icon: "doc.badge.gearshape", label: loc.localized("app.hiddenMAMEFiles"), count: mameNonGamesCount, tint: .gray, filter: .mameNonGames)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .frame(minWidth: 220, idealWidth: 240)
        .navigationTitle(loc.localized("app.library"))
    }

    @ViewBuilder
    private func sectionHeader(title: String, isExpanded: Binding<Bool>, isHeaderHovered: Binding<Bool>, onAction: (() -> Void)?, actionLabel: String?, showAction: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 4) {
            Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                        .frame(width: 12, alignment: .center)
                    Text(title)
                        .font(AppTypography.sectionHeader)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAction, let action = onAction, let label = actionLabel {
                Button(action: action) {
                    HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                        Text(label)
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHeaderHovered.wrappedValue = $0 }
        .animation(.easeInOut(duration: 0.15), value: showAction)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func sidebarRow(icon: String, label: String, system: SystemInfo? = nil, count: Int, tint: Color = AppColors.brandAccent, filter: LibraryFilter, onRename: ((SystemInfo) -> Void)? = nil) -> some View {
        SidebarRowButton(
            icon: icon,
            label: label,
            system: system,
            count: count,
            tint: tint,
            filter: filter,
            selectedFilter: $selectedFilter,
            onRefresh: system != nil ? { onRefresh?(system!) } : nil,
            onSettings: system != nil ? { onSettings?(system!.id) } : nil,
onSystemAction: system != nil ? { sys, action, targetID in
                    if case .refresh = action {
                        onRefresh?(sys)
                    } else {
                        onSystemAction?(sys, action, targetID)
                    }
                } : nil,
            onRename: onRename,
            installedCores: system != nil ? coreManager.installedCores.filter { core in
                core.systemIDs.contains(system!.id)
            } : nil
        )
    }

    @StateObject private var dragState = GameDragState.shared
    
    @State private var hoveredCategoryID: String? = nil
    @State private var categoriesHeaderHovered = false
    @State private var categoriesSectionExpanded = true
    @State private var systemsSectionExpanded = true
    
    @ViewBuilder
    private func categoryRow(category: GameCategory) -> some View {
        let count = categoryManager.gamesInCategory(categoryID: category.id, fromROMs: library.roms).count
        let isSelected = selectedFilter.id == LibraryFilter.category(category.id).id
        
        CategoryRowButton(
            category: category,
            count: count,
            isSelected: isSelected,
            selectedFilter: $selectedFilter,
            handleDropOnCategory: handleDropOnCategory,
            showEditCategorySheet: showEditCategorySheet
        )
    }
    
    private func handleDropOnCategory(items: [NSItemProvider], categoryID: String) -> Bool {
        // Use the shared drag state to get the dragged game IDs
        guard !dragState.draggedGameIDs.isEmpty else { return false }
        
        categoryManager.addGamesToCategory(gameIDs: dragState.draggedGameIDs, categoryID: categoryID)
        dragState.endDrag()
        return true
    }
    
    private func showEditCategorySheet(category: GameCategory) {
        editingCategory = category
    }
}

// MARK: - Category Sheet Views

struct CreateCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var categoryManager: CategoryManager
    @ObservedObject private var loc = LocalizationManager.shared
    
    @State private var name: String = ""
    @State private var selectedIcon: String = "gamecontroller.fill"
    @State private var selectedColor: String = "007AFF"
    
    var body: some View {
        NavigationStack {
            Form {
                Section(loc.localized("app.categoryName")) {
                    TextField(loc.localized("app.name"), text: $name)
                }
                
                Section(loc.localized("app.icon")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(GameCategory.commonIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundColor(selectedIcon == icon ? Color(hex: selectedColor) ?? .blue : .secondary)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Section(loc.localized("app.color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                        ForEach(GameCategory.colorPalette, id: \.hex) { color in
                            Button {
                                selectedColor = color.hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: color.hex) ?? .blue)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == color.hex ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Section(loc.localized("app.preview")) {
                    HStack {
                        Image(systemName: selectedIcon)
                            .font(.title2)
                            .foregroundColor(Color(hex: selectedColor) ?? .blue)
                        Text(name.isEmpty ? "Category Name" : name)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(loc.localized("app.newCategory"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.localized("app.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.localized("app.create")) {
                        categoryManager.addCategory(name: name, iconName: selectedIcon, colorHex: selectedColor)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 360, height: 500)
    }
}

struct EditCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var categoryManager: CategoryManager
    @ObservedObject private var loc = LocalizationManager.shared
    @State var category: GameCategory
    
    // Use separate state variables for selection tracking
    @State private var selectedIcon: String = ""
    @State private var selectedColor: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                    .ignoresSafeArea()

                Form {
                    Section(loc.localized("app.categoryName")) {
                        TextField(loc.localized("app.name"), text: $category.name)
                    }

                    Section(loc.localized("app.icon")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(GameCategory.commonIcons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                    category.iconName = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.title2)
                                        .foregroundColor(selectedIcon == icon ? Color(hex: selectedColor) ?? .blue : .secondary)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Section(loc.localized("app.color")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                            ForEach(GameCategory.colorPalette, id: \.hex) { color in
                                Button {
                                    selectedColor = color.hex
                                    category.colorHex = color.hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: color.hex) ?? .blue)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .stroke(selectedColor == color.hex ? Color.primary : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Section(loc.localized("app.preview")) {
                        HStack {
                            Image(systemName: selectedIcon)
                                .font(.title2)
                                .foregroundColor(Color(hex: selectedColor) ?? .blue)
                            Text(category.name.isEmpty ? "Category Name" : category.name)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .navigationTitle(loc.localized("app.editCategory"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(loc.localized("app.cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(loc.localized("app.save")) {
                            categoryManager.updateCategory(category)
                            dismiss()
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 500)
        .onAppear {
            // Initialize selection state from the category
            selectedIcon = category.iconName
            selectedColor = category.colorHex
        }
    }
}

// MARK: - Rename System Sheet

struct RenameSystemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    var system: SystemInfo
    var onRename: (String) -> Void
    
    @State private var displayName: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                    .ignoresSafeArea()

                Form {
                    Section(loc.localized("app.displayName")) {
                        TextField(loc.localized("app.name"), text: $displayName)
                    }

                    Section {
                        HStack {
                Text(loc.localized("app.original"))
                    .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                            Text(system.name)
                        }
                    }

                    Section(loc.localized("app.preview")) {
                        HStack {
                            Image(systemName: system.iconName)
                                .foregroundStyle(AppColors.brandAccent)
                            Text(displayName.isEmpty ? system.name : displayName)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .navigationTitle(loc.localized("app.renameSystem"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(loc.localized("app.cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(loc.localized("app.save")) {
                            saveRename()
                            dismiss()
                        }
                        .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .frame(width: 360, height: 280)
        .onAppear {
            displayName = system.customDisplayName ?? system.sidebarDisplayName
        }
    }
    
    private func saveRename() {
        var systems = SystemDatabase.systems
        if let index = systems.firstIndex(where: { $0.id == system.id }) {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                systems[index].customDisplayName = nil
            } else {
                systems[index].customDisplayName = trimmed
            }
            SystemDatabase.saveSystems(systems)
        }
    }
}

// MARK: - Library Filter

enum LibraryFilter: Hashable, Identifiable {
    case all
    case favorites
    case recent
    case lastAdded
    case system(SystemInfo)
    case category(String) // category ID
    case hidden
    case mameNonGames // MAME BIOS, device, mechanical, unknown
    case retroAchievements

    var id: String {
        switch self {
        case .all: return "all"
        case .favorites: return "favorites"
        case .recent: return "recent"
        case .lastAdded: return "last-added"
        case .system(let system): return "system-\(system.id)"
        case .category(let id): return "category-\(id)"
        case .hidden: return "hidden"
        case .mameNonGames: return "mame-non-games"
        case .retroAchievements: return "retro-achievements"
        }
    }

    var isSystemView: Bool {
        if case .system = self { return true }
        return false
    }
}