import SwiftUI

struct SystemSidebarView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var categoryManager: CategoryManager
    @Binding var selectedFilter: LibraryFilter
    @Binding var showCreateCategorySheet: Bool
    @Binding var editingCategory: GameCategory?

    /// Combined system entries for the sidebar. Game Boy (gb) absorbs Game Boy Color (gbc)
    /// into a single "Game Boy" display entry while keeping internal systemIDs intact.
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

            if !combinedSystemsWithROMs.isEmpty {
                Section("Systems") {
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
            }
            
            // Categories section
            Section("Categories") {
                ForEach(categoryManager.categories) { category in
                    categoryRow(category: category)
                        .tag(LibraryFilter.category(category.id))
                }
                .onMove(perform: categoryManager.reorderCategories)
                
                Button {
                    showCreateCategorySheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.secondary)
                            .frame(width: 18)
                        Text("New Category")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
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
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .frame(minWidth: 220, idealWidth: 240)
        .toolbar {
            ToolbarItem {
                Button {
                    pickFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Add ROM folder")
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(icon: String, label: String, system: SystemInfo? = nil, count: Int, tint: Color = .accentColor, filter: LibraryFilter) -> some View {
        HStack {
            if let sys = system, let img = sys.emuImage(size: 132) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: icon)
                    .foregroundColor(tint)
                    .frame(width: 18)
            }
            Text(label)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    selectedFilter = filter
                }
        )
    }

    @StateObject private var dragState = GameDragState.shared
    
    @ViewBuilder
    private func categoryRow(category: GameCategory) -> some View {
        let count = categoryManager.gamesInCategory(categoryID: category.id, fromROMs: library.roms).count
        
        HStack {
            Image(systemName: category.iconName)
                .foregroundColor(Color(hex: category.colorHex) ?? .blue)
                .frame(width: 18)
            Text(category.name)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    selectedFilter = .category(category.id)
                }
        )
        .onDrop(of: [.plainText], isTargeted: nil) { items in
            handleDropOnCategory(items: items, categoryID: category.id)
        }
        .contextMenu {
            Button {
                showEditCategorySheet(category: category)
            } label: {
                Label("Edit Category", systemImage: "pencil")
            }
            Button(role: .destructive) {
                categoryManager.deleteCategory(id: category.id)
                if case .category(let catID) = selectedFilter, catID == category.id {
                    selectedFilter = .all
                }
            } label: {
                Label("Delete Category", systemImage: "trash")
            }
        }
    }
    
    private func handleDropOnCategory(items: [NSItemProvider], categoryID: String) -> Bool {
        // Use the shared drag state to get the dragged game IDs
        guard !dragState.draggedGameIDs.isEmpty else { return false }
        
        categoryManager.addGamesToCategory(gameIDs: dragState.draggedGameIDs, categoryID: categoryID)
        dragState.endDrag()
        return true
    }
    
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            library.addLibraryFolder(url: url)
        }
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
    case system(SystemInfo)
    case category(String) // category ID
    case hidden
    
    var id: String {
        switch self {
        case .all: return "all"
        case .favorites: return "favorites"
        case .recent: return "recent"
        case .system(let system): return "system-\(system.id)"
        case .category(let id): return "category-\(id)"
        case .hidden: return "hidden"
        }
    }
}
