import SwiftUI

struct SystemSidebarView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var categoryManager: CategoryManager
    @Binding var selectedFilter: LibraryFilter
    @Binding var showCreateCategorySheet: Bool
    @Binding var editingCategory: GameCategory?
    var onRefresh: ((SystemInfo) -> Void)? = nil
    var onSettings: ((String) -> Void)? = nil
    var onSystemAction: ((SystemInfo, SystemAction) -> Void)? = nil
    
    // Combined system entries for the sidebar. Game Boy (gb) absorbs Game Boy Color (gbc)
    // into a single "Game Boy" display entry while keeping internal systemIDs intact.
    private var combinedSystemsWithROMs: [(system: SystemInfo, combinedCount: Int)] {
        let ids = Set(library.roms.compactMap { $0.systemID })
        // Only include display-visible systems (gb visible, gbc hidden)
        let displaySystems = SystemDatabase.systemsForDisplay
        
        var result: [(SystemInfo, Int)] = []
        for sys in displaySystems {
            // Check if any ROM exists for this system or its merged partners
            let internalIDs = SystemDatabase.allInternalIDs(forDisplayID: sys.id)
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
        List(selection: $selectedFilter) {
            // All games
            sidebarRow(icon: "square.grid.2x2", label: "All Games", count: library.romCounts["all"] ?? 0, filter: .all)
                .tag(LibraryFilter.all)

            // Favorites
            let favCount = library.romCounts["favorites"] ?? 0
            if favCount > 0 {
                sidebarRow(icon: "heart.fill", label: "Favorites", count: favCount, tint: .pink, filter: .favorites)
                    .tag(LibraryFilter.favorites)
            }

            // Recently played
            let recentCount = library.romCounts["recent"] ?? 0
            sidebarRow(icon: "clock.fill", label: "Recent", count: recentCount, tint: .orange, filter: .recent)
                 .tag(LibraryFilter.recent)
            
            // Categories section — tap title row to expand/collapse; "New Category" on header hover
            Section {
                if categoriesSectionExpanded {
                    ForEach(categoryManager.categories) { category in
                        categoryRow(category: category)
                            .tag(LibraryFilter.category(category.id))
                    }
                    .onMove(perform: categoryManager.reorderCategories)
                }
            } header: {
                HStack(spacing: 8) {
                    Button {
                        categoriesSectionExpanded.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: categoriesSectionExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12, alignment: .center)
                            Text("Categories")
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(categoriesSectionExpanded ? "Collapse Categories" : "Expand Categories")

                    if categoriesHeaderHovered {
                        Button {
                            showCreateCategorySheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                                Text("New Category")
                                    .lineLimit(1)
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Create a new category")
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { categoriesHeaderHovered = $0 }
                .animation(.easeInOut(duration: 0.15), value: categoriesHeaderHovered)
            }
            

            if !combinedSystemsWithROMs.isEmpty {
                Section {
                    if systemsSectionExpanded {
                        ForEach(combinedSystemsWithROMs, id: \.system.id) { entry in
                            sidebarRow(
                                icon: entry.system.iconName,
                                label: entry.system.sidebarDisplayName,
                                system: entry.system,
                                count: entry.combinedCount,
                                filter: .system(entry.system)
                            )
                            .tag(LibraryFilter.system(entry.system))
                        }
                    }
                } header: {
                    Button {
                        systemsSectionExpanded.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: systemsSectionExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12, alignment: .center)
                            Text("Systems")
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(systemsSectionExpanded ? "Collapse Systems" : "Expand Systems")
                }
            }

            // Hidden Games section — shown only when there are hidden games
            // and the user hasn't disabled it in settings
            let hiddenCount = library.romCounts["hidden"] ?? 0
            let showHiddenCategory = AppSettings.getBool("showHiddenGamesCategory", defaultValue: true)
            if hiddenCount > 0 && showHiddenCategory {
                Section("Hidden Games") {
                    sidebarRow(icon: "eye.slash", label: "Hidden", count: hiddenCount, tint: .gray, filter: .hidden)
                        .tag(LibraryFilter.hidden)
                }
            }

            // Hidden MAME Files section — separate from general hidden games
            // Only shown when enabled in settings
            let mameNonGamesCount = library.romCounts["mameNonGames"] ?? 0
            let showHiddenMAME = SystemPreferences.shared.showHiddenMAMEFiles
            if mameNonGamesCount > 0 && showHiddenMAME {
                Section("MAME Files") {
                    sidebarRow(icon: "doc.badge.gearshape", label: "Hidden MAME Files", count: mameNonGamesCount, tint: .gray, filter: .mameNonGames)
                        .tag(LibraryFilter.mameNonGames)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .frame(minWidth: 220, idealWidth: 240)
        .navigationTitle("Library")
    }

    @ViewBuilder
    private func sidebarRow(icon: String, label: String, system: SystemInfo? = nil, count: Int, tint: Color = .accentColor, filter: LibraryFilter) -> some View {
        SidebarRowButton(
            icon: icon,
            label: label,
            system: system,
            count: count,
            tint: tint,
            filter: filter,
            selectedFilter: $selectedFilter,
            onRefresh: system != nil ? { onRefresh?(system!) } : nil,
            onSettings: system != nil ? { onSettings?(system!.defaultCoreID ?? "") } : nil,
            onSystemAction: system != nil ? { sys, action in
                if case .refresh = action {
                    onRefresh?(sys)
                } else if case .settings(let coreID) = action {
                    onSettings?(coreID)
                } else {
                    onSystemAction?(sys, action)
                }
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
    
    @State private var name: String = ""
    @State private var selectedIcon: String = "folder.fill"
    @State private var selectedColor: String = "007AFF"
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Category Name") {
                    TextField("Name", text: $name)
                }
                
                Section("Icon") {
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
                
                Section("Color") {
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
                
                Section("Preview") {
                    HStack {
                        Image(systemName: selectedIcon)
                            .font(.title2)
                            .foregroundColor(Color(hex: selectedColor) ?? .blue)
                        Text(name.isEmpty ? "Category Name" : name)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
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
    @EnvironmentObject var categoryManager: CategoryManager
    @State var category: GameCategory
    
    // Use separate state variables for selection tracking
    @State private var selectedIcon: String = ""
    @State private var selectedColor: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Category Name") {
                    TextField("Name", text: $category.name)
                }
                
                Section("Icon") {
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
                
                Section("Color") {
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
                
                Section("Preview") {
                    HStack {
                        Image(systemName: selectedIcon)
                            .font(.title2)
                            .foregroundColor(Color(hex: selectedColor) ?? .blue)
                        Text(category.name.isEmpty ? "Category Name" : category.name)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        categoryManager.updateCategory(category)
                        dismiss()
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
        }
    }
}
